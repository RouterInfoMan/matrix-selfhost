# Configuration

All settings live in `.env`. After changing anything, apply it by running
`./matrix.sh up` on the server, or `./deploy.sh user@server` from your
computer. Only the services whose configuration changed are restarted.

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `MODE` | *(required)* | How the server is reached: `public`, `cloudflare`, `local`, or `proxy`. See the [guide](guide.md#1-choose-how-people-will-reach-your-server). |
| `SERVER_NAME` | *(required)* | The domain in user IDs (`@alice:SERVER_NAME`). **Permanent.** |
| `MATRIX_HOST` | *(required)* | The hostname where Synapse is reached. |
| `ELEMENT_HOST` | *(required)* | The hostname where the Element web app is reached. |
| `ENABLE_REGISTRATION` | `false` | `false`: sign-up needs an invite token. `true`: anyone can sign up. |
| `ENABLE_FEDERATION` | `false` | Talk to other Matrix servers. See [Federation](#federation). |
| `MAX_UPLOAD_SIZE` | `95M` (cloudflare), `200M` (others) | The largest file users can upload. |
| `CLOUDFLARE_TUNNEL_TOKEN` | | `cloudflare` mode: the tunnel's token. |
| `ACME_EMAIL` | | `public` mode: the address Let's Encrypt contacts about certificate problems. |
| `HTTP_PORT`, `HTTPS_PORT` | `80`, `443` | `public`/`local` mode: the host ports Caddy listens on. `public` needs the defaults. |
| `BIND_ADDRESS` | `127.0.0.1` | `proxy` mode: the address the services are published on. |
| `ELEMENT_PORT`, `WELLKNOWN_PORT` | `8080`, `8081` | `proxy` mode: the ports for Element and the discovery files. |

## Things that can and can't change

- **`SERVER_NAME` can never change.** The script refuses to start if it
  differs from the value used on the first start. The only way to change it
  is to delete `data/`, which erases all accounts and messages.
- **`MODE`, `MATRIX_HOST` and `ELEMENT_HOST` can change at any time.** Data
  is kept. Remember to update DNS and routes to match.
- **Everything else can change at any time.**

## Registration

By default, Synapse's sign-up is enabled but **requires a registration
token**. With no tokens outstanding, nobody can sign up. Create tokens with
`./matrix.sh invite` (see [operations.md](operations.md#adding-people)).

`ENABLE_REGISTRATION=true` removes the token requirement, so anyone who can
reach the server can create an account. On an internet-facing server, spam
bots find open sign-ups quickly and use them for abuse. Only enable it if you
add other protections, such as a CAPTCHA or email verification, in
`templates/homeserver.yaml`.

## Federation

With `ENABLE_FEDERATION=false` (the default), your server is a private
island. Only accounts on your server can talk to each other, and it never
connects to other servers.

With `ENABLE_FEDERATION=true`, your users can talk to people and join rooms
on any other Matrix server, such as matrix.org, and others can find and
message your users.

Requirements:
- **A mode reachable from the internet:** `public`, `cloudflare`, or `proxy`.
  `local` can't federate.
- **Discovery:** if `SERVER_NAME` differs from `MATRIX_HOST`,
  `https://SERVER_NAME/.well-known/matrix/server` must reach this server.
  The mode guides cover this.
- **In `cloudflare` mode,** turn off Bot Fight Mode for `MATRIX_HOST`.

After enabling it, test your server at https://federationtester.matrix.org.

## Encryption

`templates/homeserver.yaml` sets
`encryption_enabled_by_default_for_room_type: all`, so **every new room**,
including public ones, is end-to-end encrypted. Encryption can be turned on
for an existing room in its settings, but never turned off.

Other values: `invite` enforces encryption only for private rooms and direct
messages. `off` leaves the choice to the app; Element then encrypts private
rooms and DMs, but not public rooms.

## Customising Synapse and Element

The configuration files are generated from `templates/`:

| Template | Becomes | Used by |
|---|---|---|
| `templates/homeserver.yaml` | `data/synapse-config/homeserver.yaml` | Synapse |
| `templates/log.config` | `data/synapse-config/log.config` | Synapse logging |
| `templates/element-config.json` | `data/element-config.json` | Element Web |
| `templates/wellknown.conf` | `data/wellknown.conf` | the discovery-file server |

**Edit the templates, never the files in `data/`,** because those are
overwritten every time. Placeholders like `__SERVER_NAME__` are filled in
from `.env`. Lines starting with `#FED+` or `#FED-` are kept only when
federation is on or off, respectively.

References:
- [Synapse configuration options](https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html)
- [Element Web configuration options](https://github.com/element-hq/element-web/blob/develop/docs/config.md)

In `public` and `local` modes, the Caddy configuration (`data/Caddyfile`) is
generated directly by `matrix.sh`.
