# Operations

Every command runs **on the server**, in the repository folder. From another
computer, you can wrap any of them:
`ssh user@server 'cd ~/matrix && ./matrix.sh status'`.

## Adding people

### Invite tokens (recommended)

People choose their own username and password:

```sh
./matrix.sh invite            # 1 use, valid 7 days
./matrix.sh invite 5 30       # 5 uses, valid 30 days
./matrix.sh invite 0 0        # unlimited uses, never expires (careful)
./matrix.sh invites           # list tokens and how often each was used
./matrix.sh revoke TOKEN      # delete a token early
```

`invite` prints a short message to send to the person. In Element, they
click **Create account**, enter a username and password, and are then asked
for the token.

The invite commands talk to Synapse's admin API as an `@admin-bot` account.
It's created automatically on first use, so don't deactivate it.

### Creating accounts yourself

```sh
./matrix.sh adduser alice            # normal user; asks for a password
./matrix.sh adduser bob --admin      # server administrator
```

This works even though public sign-up is closed.

## Managing users

Synapse's [admin API](https://element-hq.github.io/synapse/latest/usage/administration/admin_api/)
covers everything else. You need an admin account's access token, which you
can copy in Element under **Settings → Help & About → Advanced**. Treat it
like a password.

```sh
TOKEN=syt_...
API=http://127.0.0.1:8008/_synapse/admin
H="Authorization: Bearer $TOKEN"

# List users
curl -s -H "$H" "$API/v2/users" | python3 -m json.tool

# Reset a password (and log out their devices)
curl -s -XPOST -H "$H" "$API/v1/reset_password/@alice:example.com" \
     -d '{"new_password":"a-new-password","logout_devices":true}'

# Grant (or remove, with false) admin rights
curl -s -XPUT -H "$H" "$API/v2/users/@alice:example.com" -d '{"admin":true}'

# Deactivate an account
curl -s -XPOST -H "$H" "$API/v1/deactivate/@alice:example.com" -d '{"erase":false}'
```

Usernames can't be renamed, and deactivated usernames can't be reused.

## Updates

```sh
./matrix.sh backup
./matrix.sh update
```

`update` downloads newer versions of all images and restarts what changed.
Do this every few weeks. To update the kit itself, run `git pull`, then
`./matrix.sh up` (or `./deploy.sh`).

## Backups

```sh
./matrix.sh backup        # creates backups/<date-time>/
```

| File | Contents |
|---|---|
| `synapse.sql.gz` | The database: accounts, rooms, messages (encrypted ones stay encrypted). |
| `synapse-data.tar.gz` | The server's signing key and uploaded media. |
| `caddy-data.tar.gz` | `public`/`local` modes: certificates, and the local CA. |
| `secrets.env`, `.env` | Generated secrets and your settings. |

A backup that only exists on the same machine doesn't protect you from losing
that machine. Copy backups elsewhere, for example to your computer:

```sh
scp -r user@server:matrix/backups/<date-time> ./matrix-backups/
```

Backups contain secrets. See [security.md](security.md#backups).

**Automatic nightly backups** that keep 14 days. Add this with `crontab -e`
on the server, adjusting the path:

```
30 3 * * * cd $HOME/matrix && ./matrix.sh backup >/dev/null && find backups -mindepth 1 -maxdepth 1 -mtime +14 -exec rm -rf {} +
```

## Restoring, or moving to a new machine

1. Prepare the new machine (guide steps [2](guide.md#2-prepare-the-machine)
   and [3](guide.md#3-get-the-code)).
2. Use the `.env` from the backup: `cp /path/to/backup/.env .env`. You may
   change `MODE` and the hostnames now, but **not** `SERVER_NAME`.
3. Restore and start:
   ```sh
   ./matrix.sh restore /path/to/backup
   ```
4. Point DNS, tunnel routes, or proxy rules at the new machine. Then shut the
   old one down for good, because two servers must never run with the same
   identity.

`restore` only works on a fresh install. It refuses to overwrite an existing
`data/` folder.

## Stopping and removing

```sh
./matrix.sh down          # stop; data is kept
```

To delete everything permanently, stop the stack, then remove `data/`. The
files are owned by container users, so use `sudo rm -rf data`.
