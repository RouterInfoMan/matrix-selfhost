# matrix-selfhost

Run your own private [Matrix](https://matrix.org) chat server, with
end-to-end encrypted messages, group rooms, and file sharing, on a machine
you control.

This kit packages the official components into a single, scripted Docker
Compose setup:

- **[Synapse](https://github.com/element-hq/synapse)**: the Matrix homeserver.
- **PostgreSQL**: its database.
- **[Element Web](https://github.com/element-hq/element-web)**: a chat client
  in the browser. Any Matrix app (Element X, FluffyChat, …) works too.

You fill in one config file and run one command. The script generates
secrets, renders the config, creates keys, and starts everything.

## Features

- **Choose how the server is reached:** a Cloudflare Tunnel, a public server
  with automatic Let's Encrypt certificates and any DNS provider, your own
  computer or home network only, or behind a reverse proxy you already run.
- **Private by default:** sign-up is invite-only, every new room is
  end-to-end encrypted, and federation with other Matrix servers is off until
  you enable it.
- **Simple day-to-day management:** `./matrix.sh invite`, `adduser`,
  `backup`, `restore`, `update`, and `status`.
- **Secrets never leave the server.** They're generated on first start, and
  nothing sensitive is stored in the repository.

## What you need

- A Linux machine with Docker: a VPS, a home server, a Raspberry Pi 4/5, or
  your own computer for a local trial. 2 GB of RAM is comfortable for a
  small group.
- A domain name. You don't need one for a local trial.
- About 30 minutes.

## Get started

➡️ **Follow the [installation guide](docs/guide.md).** It walks through every
step, from an empty machine to your first chat.

Just want to see it running on your own computer?

```sh
git clone <repository-url> matrix && cd matrix
cp .env.example .env
# set: MODE=local  SERVER_NAME=matrix.localhost  MATRIX_HOST=matrix.localhost  ELEMENT_HOST=chat.localhost
./matrix.sh up
./matrix.sh adduser me --admin
```

Then open http://chat.localhost.

## Documentation

| | |
|---|---|
| [Installation guide](docs/guide.md) | Step by step, start here. |
| [Cloudflare Tunnel](docs/modes/cloudflare.md) · [Public server](docs/modes/public.md) · [Local / LAN](docs/modes/local.md) · [Reverse proxy](docs/modes/proxy.md) | Setup specific to each way of exposing the server. |
| [Configuration](docs/configuration.md) | Every setting in `.env`, and how to customise Synapse. |
| [Operations](docs/operations.md) | Users, invites, backups, updates, moving servers. |
| [Security & privacy](docs/security.md) | What's protected, and from whom. |
| [Troubleshooting](docs/troubleshooting.md) | Common problems and fixes. |

## Commands

Run these on the server, in the repository folder:

| Command | What it does |
|---|---|
| `./matrix.sh up` | Render config and start or update everything. Safe to repeat. |
| `./matrix.sh status` | Container state and reachability checks. |
| `./matrix.sh logs [service]` | Follow logs (`synapse`, `postgres`, `element`, `caddy`, `cloudflared`, …). |
| `./matrix.sh adduser NAME [--admin]` | Create an account. |
| `./matrix.sh invite [USES] [DAYS]` | Create a sign-up token (default: 1 use, 7 days). |
| `./matrix.sh invites` / `revoke TOKEN` | List or delete tokens. |
| `./matrix.sh backup` / `restore DIR` | Back up, or restore into a fresh install. |
| `./matrix.sh update` | Pull newer images and restart. |
| `./matrix.sh ca-cert` | Local/LAN mode: export the certificate authority for your devices. |
| `./matrix.sh down` | Stop everything. |
| `./deploy.sh user@host` | Run this **on your own computer**: copy the repo to a server over SSH and start it. |

## How it fits together

```
            browsers and Matrix apps
                       │ HTTPS
       ┌───────────────┴────────────────┐
       │ Cloudflare Tunnel, Caddy, or   │  ← chosen by MODE
       │ your own reverse proxy         │
       └──┬─────────────┬────────────┬──┘
          │             │            │
   matrix.<domain> chat.<domain> <domain>/.well-known/matrix/*
          ▼             ▼            ▼
     ┌─────────┐   ┌─────────┐  ┌───────────┐
     │ Synapse │   │ Element │  │ wellknown │  tells apps where Synapse is
     └────┬────┘   └─────────┘  └───────────┘
          ▼
     ┌──────────┐
     │ Postgres │
     └──────────┘
```

| Path | Purpose |
|---|---|
| `.env.example` | All settings, commented. Copy it to `.env`. |
| `matrix.sh` | Management script; runs on the server. |
| `deploy.sh` | Copies the repo to a remote server and starts it. |
| `docker-compose.yml`, `compose/` | Core services, plus the extra service each mode adds. |
| `templates/` | Synapse, Element, and discovery config templates. Customise here. |
| `scripts/admin.py` | Synapse admin API helper used by the invite commands. |
| `data/` | Created on the server: database, media, keys, secrets. Never committed. |

## Credits

This kit only orchestrates other people's work: [Synapse](https://github.com/element-hq/synapse)
and [Element](https://github.com/element-hq/element-web) by Element,
[Caddy](https://caddyserver.com), [cloudflared](https://github.com/cloudflare/cloudflared),
and [PostgreSQL](https://www.postgresql.org).
