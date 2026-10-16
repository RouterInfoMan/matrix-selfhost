# Troubleshooting

Start with `./matrix.sh status` and `./matrix.sh logs <service>`.

**`synapse (local)` OK, but the public checks fail**
: Synapse is fine, and the problem is in front of it. Check the logs of
  whatever exposes it: `logs cloudflared`, `logs caddy`, or your own proxy.

**Cloudflare: HTTP 502 on some or all hostnames**
: Usually a **second cloudflared** is connected to the same tunnel, typically
  from running the dashboard's `docker run … --token` command. Find it with
  `docker ps | grep cloudflared` and `pgrep -a cloudflared`, and remove
  everything except `matrix-cloudflared-1`. The tunnel page in the dashboard
  should list exactly one connector.
: Otherwise, the route is wrong. It needs Type **HTTP** (not HTTPS), and the
  URL must use the container name (`synapse:8008`, not `localhost:8008`).

**Cloudflare: 530 / error 1033**
: No connector is running. `./matrix.sh logs cloudflared` will show an
  invalid or empty token.

**"Registration has been disabled" / no token field**
: The running Synapse has old config. Run `./matrix.sh up`; if that doesn't
  help, run `./matrix.sh compose restart synapse`. Element only asks for the
  token **after** you submit a username and password.

**`SERVER_NAME changed from … to …`**
: This is deliberate. A server's name can't change. Revert `.env`, or wipe
  `data/` to start over, which deletes everything.

**Caddy: certificate errors (MODE=public)**
: DNS doesn't point at this server yet, ports 80/443 aren't reachable from
  outside, or there's an AAAA record without working IPv6. See
  [public-server.md](public-server.md#if-certificates-fail).

**Browser warns about the certificate (MODE=local)**
: The device doesn't trust the local CA yet. Run `./matrix.sh ca-cert` and
  install it ([local.md](local.md#2-start-it-and-export-the-ca)).

**`Bind for 0.0.0.0:80 failed: port is already allocated`**
: Something else uses the port. For MODE=local, set `HTTP_PORT`/`HTTPS_PORT`.
  For MODE=public, stop the other service or switch to MODE=proxy behind it.
  For MODE=proxy, change `ELEMENT_PORT`/`WELLKNOWN_PORT`.

**Federation tester fails (ENABLE_FEDERATION=true)**
: Check that `https://SERVER_NAME/.well-known/matrix/server` returns JSON.
  `./matrix.sh status` shows it. On Cloudflare, disable Bot Fight Mode for
  `MATRIX_HOST`. Remember that MODE=local can't federate.

**Uploads fail above ~95 MB**
: That's Cloudflare's 100 MB request limit. Other modes default to 200M
  (`MAX_UPLOAD_SIZE`).

**`permission denied … docker.sock`**
: Run `sudo usermod -aG docker $USER`, then log out and back in.

**Can't decrypt old messages on a new device**
: Use your recovery key, under **Settings → Encryption** in Element. Without
  it, history from before that device existed can't be decrypted. The server
  can't help, because it never had the keys.
