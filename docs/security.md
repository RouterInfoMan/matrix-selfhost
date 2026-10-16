# Security & privacy

## Messages

Every new room is **end-to-end encrypted** (E2EE). Messages and files are
encrypted on the sender's device, and only the participants' devices can
decrypt them. The server, its administrator, and anyone in the network path
see only ciphertext.

What isn't hidden, even with E2EE, is **metadata**: who is in which room,
who talks to whom and when, display names, avatars, room names, and IP
addresses. The server stores these, so the server's administrator can see
them.

Your encryption keys live on your devices. The **recovery key** you're
offered at first sign-in backs them up in encrypted form. If you lose every
device and the recovery key, your old messages can't be recovered by anyone.

## The server

- **Registration:** invite-only by default. Only people you give a token to
  (or create accounts for) can join.
- **Federation:** off by default. The server doesn't talk to any other
  Matrix server.
- **Secrets:** the database password, registration secret, and signing key
  are generated on the server, in `data/`. They aren't in the repository, and
  `deploy.sh` never copies them anywhere. `data/` is readable only by its
  owner.
- **Exposed ports:** no service listens publicly except the entry point of
  your chosen mode: Caddy on 80/443, the tunnel, or your proxy. Synapse's
  admin port is bound to `127.0.0.1`.
- **The admin API** (`/_synapse/admin`) is reachable through the public
  hostname, but only with an admin's access token. The invite commands use a
  dedicated `@admin-bot` account. Its login is stored in
  `data/synapse/.admin-bot.json`.

## Cloudflare mode

Cloudflare terminates HTTPS at its edge, so it can see all traffic between
apps and your server: everything in the metadata list above, plus the full
content of any **unencrypted** room. Encrypted rooms remain opaque to it.
If you don't want a third party in the path, use `public` mode.

## Backups

Backups contain the database, the server's signing key, all secrets, and,
in `local` mode, the private CA key. Anyone who has a backup can impersonate
your server. Store backups encrypted, or somewhere only you can access.

## Keeping it safe

- Run `./matrix.sh update` regularly. Synapse publishes security fixes often.
- Keep the host's OS updated, and use SSH keys rather than passwords.
- Don't share admin accounts. Make separate accounts, and grant admin only
  where it's needed.
