#!/usr/bin/env bash
# Runs ON THE SERVER. Manages the Matrix stack.
#
#   ./matrix.sh up                 render config, generate secrets/keys, start everything
#   ./matrix.sh down               stop everything
#   ./matrix.sh status             containers + health checks
#   ./matrix.sh logs [service]     follow logs (synapse, postgres, element, wellknown, cloudflared, caddy)
#   ./matrix.sh adduser NAME [--admin]
#   ./matrix.sh invite [USES] [DAYS]  make a sign-up token (default: 1 use, valid 7 days; 0 = unlimited)
#   ./matrix.sh invites            list invite tokens and how often they were used
#   ./matrix.sh revoke TOKEN       delete an invite token
#   ./matrix.sh update             pull newer images and restart
#   ./matrix.sh backup             dump database + synapse data to ./backups/
#   ./matrix.sh restore DIR        restore a backup into a fresh install
#   ./matrix.sh ca-cert            MODE=local: export the local CA certificate for your devices
#   ./matrix.sh compose ARGS...    run docker compose with this MODE's files
set -euo pipefail
cd "$(dirname "$0")"

die() { echo "error: $*" >&2; exit 1; }
rand() { head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
is_localhost() { [[ "$1" == localhost || "$1" == *.localhost ]]; }

load_env() {
    [[ -f .env ]] || die ".env not found (copy .env.example to .env and fill it in)"
    set -a; source .env; set +a
    for v in SERVER_NAME MATRIX_HOST ELEMENT_HOST; do
        [[ -n "${!v:-}" ]] || die "$v is not set in .env"
    done
    [[ "$SERVER_NAME" != "example.com" ]] || die "edit .env: SERVER_NAME is still example.com"

    MODE="${MODE-cloudflare}"   # unset: cloudflare (older installs); empty: must choose
    ENABLE_REGISTRATION="${ENABLE_REGISTRATION:-false}"
    ENABLE_FEDERATION="${ENABLE_FEDERATION:-false}"
    if [[ "$ENABLE_REGISTRATION" == true ]]; then REQUIRE_TOKEN=false; else REQUIRE_TOKEN=true; fi

    # Which compose files make up this mode (docker compose reads COMPOSE_FILE).
    case "$MODE" in
        cloudflare)   COMPOSE_FILE=docker-compose.yml:compose/cloudflare.yml ;;
        public|local) COMPOSE_FILE=docker-compose.yml:compose/caddy.yml ;;
        proxy)        COMPOSE_FILE=docker-compose.yml:compose/proxy.yml ;;
        *) die "set MODE in .env to cloudflare, public, local or proxy (got '$MODE'); see docs/guide.md" ;;
    esac
    export COMPOSE_FILE

    # Cloudflare's free plan rejects request bodies over 100 MB.
    if [[ "$MODE" == cloudflare ]]; then MAX_UPLOAD_SIZE="${MAX_UPLOAD_SIZE:-95M}"
    else MAX_UPLOAD_SIZE="${MAX_UPLOAD_SIZE:-200M}"; fi

    # Public URLs. MODE=local with *.localhost names is plain HTTP (browsers
    # treat localhost as secure); everything else is HTTPS.
    local port default_port
    if [[ "$MODE" == local ]] && is_localhost "$MATRIX_HOST"; then
        is_localhost "$ELEMENT_HOST" && is_localhost "$SERVER_NAME" \
            || die "MODE=local: use *.localhost for all of SERVER_NAME, MATRIX_HOST and ELEMENT_HOST, or for none of them"
        SCHEME=http; port="${HTTP_PORT:-80}"; default_port=80
    else
        SCHEME=https; default_port=443; port=443
        [[ "$MODE" == public || "$MODE" == local ]] && port="${HTTPS_PORT:-443}"
    fi
    local suffix=""; [[ "$port" == "$default_port" ]] || suffix=":$port"
    FEDERATION_PORT=443; [[ "$SCHEME" == https ]] && FEDERATION_PORT="$port"
    MATRIX_URL="$SCHEME://$MATRIX_HOST$suffix"
    ELEMENT_URL="$SCHEME://$ELEMENT_HOST$suffix"
    SERVER_URL="$SCHEME://$SERVER_NAME$suffix"
}

uses_caddy() { [[ "$MODE" == public || "$MODE" == local ]]; }

check_docker() {
    command -v docker >/dev/null || die "docker is not installed. Install it with:
    curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker \$USER
  then log out and back in."
    docker compose version >/dev/null 2>&1 || die "the docker compose plugin is missing"
    docker info >/dev/null 2>&1 || die "can't talk to the docker daemon (is your user in the 'docker' group?)"
}

render() { # render TEMPLATE OUTPUT
    local resources fed rooms
    if [[ "$ENABLE_FEDERATION" == true ]]; then
        resources="client, federation"; rooms="\"$SERVER_NAME\", \"matrix.org\""
        fed=(-e '/^#FED- /d' -e 's/^#FED+ //')
    else
        resources="client"; rooms="\"$SERVER_NAME\""
        fed=(-e '/^#FED+ /d' -e 's/^#FED- //')
    fi
    sed "${fed[@]}" \
        -e "s|__SERVER_NAME__|$SERVER_NAME|g" \
        -e "s|__MATRIX_HOST__|$MATRIX_HOST|g" \
        -e "s|__MATRIX_URL__|$MATRIX_URL|g" \
        -e "s|__FEDERATION_PORT__|$FEDERATION_PORT|g" \
        -e "s|__LISTENER_RESOURCES__|$resources|g" \
        -e "s|__ROOM_DIRECTORY_SERVERS__|$rooms|g" \
        -e "s|__MAX_UPLOAD_SIZE__|$MAX_UPLOAD_SIZE|g" \
        -e "s|__ENABLE_REGISTRATION__|$ENABLE_REGISTRATION|g" \
        -e "s|__REQUIRE_TOKEN__|$REQUIRE_TOKEN|g" \
        -e "s|__POSTGRES_PASSWORD__|$POSTGRES_PASSWORD|g" \
        -e "s|__REGISTRATION_SHARED_SECRET__|$REGISTRATION_SHARED_SECRET|g" \
        -e "s|__MACAROON_SECRET_KEY__|$MACAROON_SECRET_KEY|g" \
        -e "s|__FORM_SECRET__|$FORM_SECRET|g" \
        "$1" > "$2"
}

write_caddyfile() { # routes for MODE=public / MODE=local
    local addr="" tls=""
    if [[ "$SCHEME" == http ]]; then addr="http://"        # *.localhost
    elif [[ "$MODE" == local ]]; then tls=$'\ttls internal\n'  # Caddy's own CA
    fi
    {
        echo "# Generated by matrix.sh from .env; edits are overwritten."
        if [[ "$MODE" == public && -n "${ACME_EMAIL:-}" ]]; then
            printf '{\n\temail %s\n}\n' "$ACME_EMAIL"
        fi
        # Synapse. When SERVER_NAME == MATRIX_HOST it also answers the well-knowns.
        printf '\n%s%s {\n%s\treverse_proxy synapse:8008\n}\n' "$addr" "$MATRIX_HOST" "$tls"
        # Element (plus the well-knowns, in the odd case that it's also SERVER_NAME).
        printf '\n%s%s {\n%s' "$addr" "$ELEMENT_HOST" "$tls"
        if [[ "$ELEMENT_HOST" == "$SERVER_NAME" ]]; then
            printf '\thandle /.well-known/matrix/* {\n\t\treverse_proxy wellknown:80\n\t}\n'
        fi
        printf '\treverse_proxy element:80\n}\n'
        # Bare SERVER_NAME: delegation files, everything else goes to Element.
        if [[ "$SERVER_NAME" != "$MATRIX_HOST" && "$SERVER_NAME" != "$ELEMENT_HOST" ]]; then
            printf '\n%s%s {\n%s' "$addr" "$SERVER_NAME" "$tls"
            printf '\thandle /.well-known/matrix/* {\n\t\treverse_proxy wellknown:80\n\t}\n'
            printf '\thandle {\n\t\tredir %s{uri}\n\t}\n}\n' "$ELEMENT_URL"
        fi
    } > data/Caddyfile
}

config_sums() { # "<hash> <service> <file>" per rendered config file
    local f svc files=(data/synapse-config/homeserver.yaml data/synapse-config/log.config
                       data/element-config.json data/wellknown.conf)
    uses_caddy && files+=(data/Caddyfile)
    for f in "${files[@]}"; do
        case "$f" in
            data/synapse-config/*) svc=synapse ;;
            data/element-config.json) svc=element ;;
            data/wellknown.conf) svc=wellknown ;;
            data/Caddyfile) svc=caddy ;;
        esac
        if [[ -f "$f" ]]; then echo "$(cksum < "$f" | cut -d' ' -f1) $svc $f"; else echo "none $svc $f"; fi
    done
}

cmd_setup() {
    check_docker
    case "$MODE" in
        cloudflare) [[ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]] || echo "warning: CLOUDFLARE_TUNNEL_TOKEN is empty; the tunnel won't start" >&2 ;;
        public) is_localhost "$MATRIX_HOST" && die "MODE=public needs real domain names; use MODE=local for *.localhost"
                [[ -n "${ACME_EMAIL:-}" ]] || echo "warning: ACME_EMAIL is empty; Let's Encrypt can't warn you about certificate problems" >&2 ;;
    esac

    mkdir -p data/synapse data/synapse-config
    uses_caddy && mkdir -p data/caddy/data data/caddy/config
    # Only the owner can see secrets on the host; containers see their own mounts.
    chmod 700 data

    # Secrets are generated once, on the server, and never leave it.
    if [[ ! -f data/secrets.env ]]; then
        echo "Generating secrets -> data/secrets.env"
        (umask 077; cat > data/secrets.env <<EOF
POSTGRES_PASSWORD=$(rand)
REGISTRATION_SHARED_SECRET=$(rand)
MACAROON_SECRET_KEY=$(rand)
FORM_SECRET=$(rand)
EOF
        )
    fi
    set -a; source data/secrets.env; set +a

    # If the server name changed after first start, the database belongs to the
    # old name and Synapse will refuse to start. Catch that early.
    if [[ -f data/.server_name && "$(cat data/.server_name)" != "$SERVER_NAME" ]]; then
        die "SERVER_NAME changed from '$(cat data/.server_name)' to '$SERVER_NAME'. This isn't supported;
  either revert .env or wipe data/ to start over (destroys all accounts and messages)."
    fi
    echo "$SERVER_NAME" > data/.server_name

    echo "Rendering config: MODE=$MODE, @user:$SERVER_NAME, homeserver at $MATRIX_URL, federation=$ENABLE_FEDERATION"
    local before; before=$(config_sums)
    render templates/homeserver.yaml data/synapse-config/homeserver.yaml
    cp templates/log.config data/synapse-config/log.config
    render templates/element-config.json data/element-config.json
    render templates/wellknown.conf data/wellknown.conf
    uses_caddy && write_caddyfile
    chmod 644 data/synapse-config/* data/element-config.json data/wellknown.conf
    uses_caddy && chmod 644 data/Caddyfile
    # Services read their config at startup, and `docker compose up -d` won't
    # restart a running container just because a mounted file changed.
    # (Files that didn't exist before mean a first start: nothing to restart.)
    CHANGED_SERVICES=$(diff <(echo "$before") <(config_sums) \
        | awk '/^</ && $2 == "none" {new[$4]} /^>/ {ch[$4] = $3}
               END {for (f in ch) if (!(f in new)) print ch[f]}' | sort -u | xargs || true)

    if [[ ! -f data/synapse/signing.key ]]; then
        echo "Generating Synapse signing key"
        docker compose run --rm -T --no-deps --remove-orphans --user 0 --entrypoint sh synapse -c \
            'python -m synapse.app.homeserver --config-path /config/homeserver.yaml --generate-keys'
    fi
    # Synapse runs as uid 991 inside the container and must own its data dir.
    docker compose run --rm -T --no-deps --remove-orphans --user 0 --entrypoint chown synapse -R 991:991 /data
}

cmd_up() {
    cmd_setup
    docker compose up -d --remove-orphans
    if [[ -n "$CHANGED_SERVICES" ]]; then
        echo "Config changed, restarting: $CHANGED_SERVICES"
        docker compose restart $CHANGED_SERVICES
    fi
    echo
    echo "Started. Element: $ELEMENT_URL   Check with: ./matrix.sh status"
}

cmd_status() {
    docker compose ps
    echo
    # MODE=local: talk to Caddy on this machine directly (the names may only
    # resolve on your LAN) and accept the local CA's certificate.
    local curl=(curl -fsS --max-time 10)
    [[ "$MODE" == local ]] && curl+=(-k --connect-to ::127.0.0.1:)
    check() { # LABEL URL [print body]
        printf '%-20s %s\n%-20s ' "$1" "$2" ""
        if [[ -n "${3:-}" ]]; then "${curl[@]}" "$2" && echo || echo "NOT REACHABLE"
        else "${curl[@]}" -o /dev/null "$2" && echo OK || echo "NOT REACHABLE"; fi
    }
    printf '%-20s ' "synapse (local)"
    curl -fsS --max-time 5 http://127.0.0.1:8008/health && echo || echo "NOT RESPONDING"
    check "synapse (public)" "$MATRIX_URL/_matrix/client/versions"
    check "element (public)" "$ELEMENT_URL/"
    check "client discovery" "$SERVER_URL/.well-known/matrix/client" body
    if [[ "$ENABLE_FEDERATION" == true ]]; then
        check "server discovery" "$SERVER_URL/.well-known/matrix/server" body
        echo
        echo "Full federation test: https://federationtester.matrix.org/#$SERVER_NAME"
    fi
}

cmd_adduser() {
    local name="${1:-}"; shift || true
    [[ -n "$name" ]] || die "usage: ./matrix.sh adduser NAME [--admin]"
    local admin="--no-admin"
    [[ "${1:-}" == "--admin" ]] && admin="--admin"
    docker compose exec synapse register_new_matrix_user \
        -c /config/homeserver.yaml -u "$name" "$admin" http://localhost:8008
}

admin_py() { # runs scripts/admin.py inside the synapse container
    docker compose exec -T synapse python - "$ELEMENT_URL" "$@" < scripts/admin.py
}

cmd_backup() {
    local dir="backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$dir"
    echo "Dumping database -> $dir/synapse.sql.gz"
    docker compose exec -T postgres pg_dump -U synapse synapse | gzip > "$dir/synapse.sql.gz"
    echo "Archiving synapse data (signing key, media) -> $dir/synapse-data.tar.gz"
    docker compose run --rm -T --no-deps --user 0 --entrypoint tar synapse czf - -C /data . > "$dir/synapse-data.tar.gz"
    if [[ -d data/caddy ]]; then
        echo "Archiving Caddy certificates (and local CA) -> $dir/caddy-data.tar.gz"
        docker run --rm -v "$PWD/data/caddy:/caddy:ro" alpine tar czf - -C /caddy . > "$dir/caddy-data.tar.gz"
    fi
    cp data/secrets.env .env "$dir/"
    chmod -R go-rwx backups
    echo "Done: $dir"
}

cmd_restore() {
    local dir="${1:-}"
    [[ -n "$dir" ]] || die "usage: ./matrix.sh restore BACKUP_DIR"
    for f in synapse.sql.gz synapse-data.tar.gz secrets.env; do
        [[ -f "$dir/$f" ]] || die "$dir/$f is missing; is this a ./matrix.sh backup folder?"
    done
    [[ ! -e data/postgres ]] || die "data/ already holds a database. Restore only into a fresh install:
  ./matrix.sh down && mv data data.old"
    local backup_name; backup_name=$(sed -n 's/^SERVER_NAME=//p' "$dir/.env" 2>/dev/null || true)
    [[ -z "$backup_name" || "$backup_name" == "$SERVER_NAME" ]] \
        || die "the backup is for SERVER_NAME=$backup_name but .env says $SERVER_NAME"
    check_docker

    mkdir -p data/synapse data/synapse-config
    chmod 700 data
    (umask 077; cp "$dir/secrets.env" data/secrets.env)
    echo "Restoring synapse data (signing key, media)"
    docker compose run --rm -T --no-deps --user 0 --entrypoint tar synapse xzf - -C /data < "$dir/synapse-data.tar.gz"
    if [[ -f "$dir/caddy-data.tar.gz" ]]; then
        echo "Restoring Caddy certificates"
        mkdir -p data/caddy
        docker run --rm -i -v "$PWD/data/caddy:/caddy" alpine tar xzf - -C /caddy < "$dir/caddy-data.tar.gz"
    fi
    echo "Restoring database"
    docker compose up -d --wait postgres
    gunzip -c "$dir/synapse.sql.gz" | docker compose exec -T postgres psql -q -v ON_ERROR_STOP=1 -U synapse synapse >/dev/null
    cmd_up
}

cmd_ca_cert() {
    [[ "$MODE" == local && "$SCHEME" == https ]] || die "only MODE=local with non-.localhost names uses a local CA"
    docker compose exec -T caddy cat /data/caddy/pki/authorities/local/root.crt > matrix-local-ca.crt \
        || die "Caddy hasn't created its CA yet; run ./matrix.sh up and open $ELEMENT_URL once"
    echo "Wrote $(pwd)/matrix-local-ca.crt; install it as a trusted root CA on each device (see docs/modes/local.md)."
}

cmd="${1:-}"; shift || true
case "$cmd" in
    setup|up|down|status|logs|adduser|invite|invites|revoke|update|backup|restore|ca-cert|compose) load_env ;;
    *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
case "$cmd" in
    setup)   cmd_setup ;;
    up)      cmd_up ;;
    down)    docker compose down --remove-orphans ;;
    status)  cmd_status ;;
    logs)    docker compose logs -f --tail=100 "$@" ;;
    adduser) cmd_adduser "$@" ;;
    invite|invites|revoke) admin_py "$cmd" "$@" ;;
    update)  docker compose pull && cmd_up ;;
    backup)  cmd_backup ;;
    restore) cmd_restore "$@" ;;
    ca-cert) cmd_ca_cert ;;
    compose) docker compose "$@" ;;
esac
