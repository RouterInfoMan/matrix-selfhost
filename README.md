# Self-hosted Matrix

A small, scripted [Matrix](https://matrix.org) chat server: **Synapse** (the
homeserver), **Postgres**, and the **Element** web client, all in Docker
Compose. One `.env` file describes the server, and one script (`matrix.sh`)
runs it.

Defaults are private on purpose: sign-up is **invite-only**, **federation is
off** (only your own accounts can talk to each other), and every new room is
**end-to-end encrypted**. Each of these is one setting in `.env`.

## Pick how people reach it

| `MODE` | Use it when | You need | Guide |
|---|---|---|---|
| `cloudflare` | The server is behind NAT/CGNAT, or you don't want open ports. | A domain whose DNS is on Cloudflare. | [docs/cloudflare-tunnel.md](docs/cloudflare-tunnel.md) |
| `public` | The server has a public IP: a VPS, or a home server with port forwarding. | A domain at **any** DNS provider, plus ports 80 and 443 open. | [docs/public-server.md](docs/public-server.md) |
| `local` | You're trying it on your own machine, or it should only work on your home network. | Nothing for `*.localhost`. For a LAN, local DNS or hosts entries. | [docs/local.md](docs/local.md) |
| `proxy` | You already run nginx, Traefik, Caddy, or similar. | Your proxy handles TLS and routing. | [docs/reverse-proxy.md](docs/reverse-proxy.md) |

Not sure? To **try it in 2 minutes**, use `local`. If it's **for real** and
your server has a public IP, use `public`. If it doesn't have a public IP,
use `cloudflare`.

## How it works

```
                 clients (Element web, Element X, FluffyChat, …)
                                     │  HTTPS
              ┌──────────────────────┼──────────────────────────┐
              │ cloudflare: cloudflared tunnel (outbound only)   │
              │ public/local: Caddy on :80/:443 (automatic TLS)  │  ← MODE picks one
              │ proxy: your own reverse proxy                    │
              └──────┬───────────────┬──────────────────┬────────┘
     matrix.example.com      chat.example.com      example.com/.well-known/matrix/*
                     ▼               ▼                  ▼
               ┌─────────┐     ┌─────────┐       ┌───────────┐
               │ synapse │     │ element │       │ wellknown │  "Matrix for example.com
               └────┬────┘     └─────────┘       └───────────┘   lives at matrix.example.com"
                    ▼
               ┌──────────┐
               │ postgres │
               └──────────┘
```

There are three names in `.env`:

- **`SERVER_NAME`** is the part after the colon in user IDs (`@alice:example.com`).
  **It can never change**, because it's baked into every account and message.
- **`MATRIX_HOST`** is where Synapse is reachable, e.g. `matrix.example.com`.
- **`ELEMENT_HOST`** is where the web client is reachable, e.g. `chat.example.com`.

If `SERVER_NAME` differs from `MATRIX_HOST`, apps and servers look up
`https://SERVER_NAME/.well-known/matrix/…` to find the real host. The
`wellknown` container answers that. If your bare domain already hosts a
website elsewhere, set `SERVER_NAME` equal to `MATRIX_HOST`. The IDs then look
like `@alice:matrix.example.com`, and no delegation is needed.

## Quick start

On any Linux machine with Docker (`curl -fsSL https://get.docker.com | sudo sh`):

```sh
git clone <this repo> matrix && cd matrix
cp .env.example .env
nano .env          # pick a MODE, set the three names (see the guide for your MODE)
./matrix.sh up
./matrix.sh adduser yourname --admin
./matrix.sh status
```

Then open `ELEMENT_HOST` in a browser and sign in.

**For a remote server,** keep the repo on your own machine and run
`./deploy.sh user@server`. It copies the repo there over SSH (to `~/matrix`)
and runs `./matrix.sh up`. Run it again after any change to `.env` or
`templates/`.

To try it locally, these values give you a working server at
http://chat.localhost:

```ini
MODE=local
SERVER_NAME=matrix.localhost
MATRIX_HOST=matrix.localhost
ELEMENT_HOST=chat.localhost
```

## Commands

All of these run on the server, in the repo folder:

```sh
./matrix.sh up                 # (re)render config and start; safe to repeat
./matrix.sh status             # containers + reachability checks
./matrix.sh logs [service]     # follow logs: synapse, postgres, element, wellknown, caddy, cloudflared
./matrix.sh adduser NAME [--admin]
./matrix.sh invite [USES] [DAYS]   # sign-up token, default 1 use / 7 days (0 = unlimited)
./matrix.sh invites            # list tokens
./matrix.sh revoke TOKEN
./matrix.sh update             # pull new images, restart
./matrix.sh backup             # → backups/<timestamp>/
./matrix.sh restore DIR        # into a fresh install
./matrix.sh ca-cert            # MODE=local on a LAN: export the CA for your devices
./matrix.sh compose ARGS…      # raw docker compose with the right files for MODE
./matrix.sh down
```

Day-to-day work (users, invites, backups, federation, moving servers) is
covered in [docs/operations.md](docs/operations.md). For problems, see
[docs/troubleshooting.md](docs/troubleshooting.md).

## Repository layout

| Path | Purpose |
|---|---|
| `.env.example` | Every setting, documented. Copy it to `.env`. |
| `matrix.sh` | Runs on the server. Generates secrets and config, and starts, stops, backs up, and manages users. |
| `deploy.sh` | Runs on your machine. Copies the repo to a server over SSH and runs `matrix.sh up`. |
| `docker-compose.yml` | Core services: postgres, synapse, element, wellknown. |
| `compose/*.yml` | Per-mode additions: `cloudflare.yml` (cloudflared), `caddy.yml` (`public`/`local`), `proxy.yml` (published ports). |
| `templates/` | Config templates. **Edit these**, not the generated copies in `data/`. |
| `scripts/admin.py` | Admin API helper behind `invite`/`invites`/`revoke`. It runs inside the Synapse container. |
| `data/` | **Server only, never committed.** Database, media, signing key, secrets, generated config, certificates. |
| `backups/` | Output of `./matrix.sh backup`. |

Secrets (the database password, registration secret, and so on) are generated
on the server on first start, in `data/secrets.env`. They never leave it
except in your backups.
