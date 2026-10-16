# Running the server

Every command here runs **on the server**, in the repo folder (e.g. `~/matrix`).
From your own machine you can wrap any of them:
`ssh server 'cd ~/matrix && ./matrix.sh status'`.

## First account

```sh
./matrix.sh adduser yourname --admin
```

Sign in at `ELEMENT_HOST` with that name and password, using **Sign in**, not
**Create account**. Any Matrix app works too, such as Element X (iOS/Android),
Element desktop, or FluffyChat. When the app asks for a server, enter
`SERVER_NAME`.

The first time you sign in, Element offers to set up a **recovery key**.
Save it somewhere safe. Without it, a new device can't read your old
encrypted messages.

## Adding people

**Invite tokens (recommended).** People pick their own username and password:

```sh
./matrix.sh invite            # 1 use, valid 7 days
./matrix.sh invite 5 30       # 5 uses, valid 30 days (0 = unlimited / never)
./matrix.sh invites           # what exists, how often each was used
./matrix.sh revoke TOKEN
```

`invite` prints a message to send to them. They click **Create account**,
fill in a username and password, and are then asked for the token.

The script talks to Synapse's admin API as an `@admin-bot` account that it
creates on first use. Its login is stored in `data/synapse/.admin-bot.json`.
Don't deactivate that account.

**Creating accounts directly:**
```sh
./matrix.sh adduser bob           # prompts for a password; add --admin for admins
```
This works through Synapse's registration shared secret, so it works even
when sign-up is closed.

**Open sign-up:** with `ENABLE_REGISTRATION=true`, anyone who can reach the
server can create an account. Avoid this on a public server, because spam
bots find open servers quickly.

## Other user management (admin API)

You need an admin's access token. In Element, it's under **Settings → Help &
About → Advanced → Access Token**. Treat it like a password.

```sh
TOKEN=syt_...
API=http://127.0.0.1:8008/_synapse/admin
H="Authorization: Bearer $TOKEN"

curl -s -H "$H" "$API/v2/users" | python3 -m json.tool                                   # list users
curl -s -XPOST -H "$H" "$API/v1/reset_password/@bob:example.com" \
     -d '{"new_password":"...","logout_devices":true}'                                    # reset password
curl -s -XPUT  -H "$H" "$API/v2/users/@bob:example.com" -d '{"admin":true}'                # make admin
curl -s -XPOST -H "$H" "$API/v1/deactivate/@bob:example.com" -d '{"erase":false}'          # deactivate
```

Reference: https://element-hq.github.io/synapse/latest/usage/administration/admin_api/

Usernames can't be renamed or reused. Deactivated names stay reserved.

## Settings in `.env`

After changing anything in `.env` or `templates/`, run `./matrix.sh up`
(or `./deploy.sh server` from your machine). It re-renders the config and
restarts only the services whose config changed.

| Setting | Effect |
|---|---|
| `ENABLE_FEDERATION=true` | Talk to matrix.org and every other server. Needs a publicly reachable mode, and the `SERVER_NAME` discovery route if `SERVER_NAME` differs from `MATRIX_HOST`. Test it at https://federationtester.matrix.org. |
| `ENABLE_REGISTRATION=true` | Open sign-up, with no token needed. |
| `MAX_UPLOAD_SIZE=500M` | Raise the upload limit. Cloudflare's free plan caps requests at 100 MB regardless. |
| `MODE=…` | Switch how the server is exposed. Data is kept, and leftover containers (e.g. cloudflared) are removed. |

**`SERVER_NAME` can't be changed.** The script refuses to start if it
differs from the first start. Changing it means wiping `data/`, which loses
all accounts and messages.

**Encryption:** every new room, including public ones, is end-to-end
encrypted (`encryption_enabled_by_default_for_room_type` in
`templates/homeserver.yaml`). Existing rooms keep their setting. You can
enable encryption in **Room settings → Security & Privacy**, but it can't be
turned off afterwards.

Any other Synapse option goes into `templates/homeserver.yaml`. See the
[config reference](https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html).
Never edit the copies in `data/`, because they're overwritten.

## Updates

```sh
./matrix.sh update      # pull newer images, restart what changed
```

Run this every few weeks, since Synapse releases security fixes regularly.
Take a backup first.

## Backups

```sh
./matrix.sh backup      # → backups/<timestamp>/
```

| File | Contains |
|---|---|
| `synapse.sql.gz` | The database: accounts, rooms, messages. |
| `synapse-data.tar.gz` | The **signing key** (the server's identity) and uploaded media. |
| `caddy-data.tar.gz` | MODE=public/local only: certificates and the local CA. |
| `secrets.env`, `.env` | Generated secrets and your settings. |

Backups contain secrets, so **copy them off the server** and keep them
private:
```sh
scp -r server:matrix/backups/<timestamp> ./matrix-backups/
```

To automate backups, add a cron job (`crontab -e`) that runs a nightly backup
and deletes backups older than 14 days:
```
30 3 * * * cd ~/matrix && ./matrix.sh backup >/dev/null && find backups -mindepth 1 -maxdepth 1 -mtime +14 -exec rm -rf {} +
```

## Restore, or move to a new server

On the new machine:

```sh
# 1. Get the repo, and use the .env from the backup
git clone <this repo> matrix && cd matrix
cp /path/to/backup/.env .env
#    (change MODE or hostnames now if you're switching how it's exposed;
#     SERVER_NAME must stay the same)

# 2. Restore and start
./matrix.sh restore /path/to/backup
```

`restore` refuses to run if `data/` already holds a database. Move the old
`data/` aside first. Afterwards, point DNS or the tunnel routes at the new
machine, and stop the old server. Two servers with the same identity must
never run at the same time.
