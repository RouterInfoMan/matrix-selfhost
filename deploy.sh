#!/usr/bin/env bash
# Runs ON YOUR MACHINE. Copies this folder to the server over SSH and starts it.
#
#   ./deploy.sh SSH_HOST [REMOTE_DIR]
#
# SSH_HOST is anything ssh accepts (user@1.2.3.4, or a Host from ~/.ssh/config).
# REMOTE_DIR defaults to "matrix" (relative to the remote user's home).
# The server's data/ directory (database, secrets, media) is never touched.
set -euo pipefail
cd "$(dirname "$0")"

host="${1:?usage: ./deploy.sh SSH_HOST [REMOTE_DIR]}"
dir="${2:-matrix}"

[[ -f .env ]] || { echo "error: create .env first (cp .env.example .env)" >&2; exit 1; }

echo "Uploading to $host:$dir"
tar czf - docker-compose.yml compose matrix.sh .env .env.example templates scripts \
    | ssh "$host" "mkdir -p '$dir' && tar xzf - -C '$dir' && chmod 600 '$dir/.env'"

echo "Starting stack on $host"
ssh "$host" "cd '$dir' && ./matrix.sh up"
