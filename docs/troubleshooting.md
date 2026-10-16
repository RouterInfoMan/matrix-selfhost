# Troubleshooting

Start with these two commands on the server:

```sh
./matrix.sh status            # what's running, what's reachable
./matrix.sh logs synapse      # or caddy, cloudflared, postgres, element
```

If `synapse (local)` is OK but the public checks fail, Synapse itself is
fine, and the problem is in front of it: DNS, the tunnel, Caddy, or your
proxy.

---

### Docker: `permission denied … docker.sock`

Your user isn't in the `docker` group yet. Run
`sudo usermod -aG docker $USER`, then log out and back in.

### `set MODE in .env …`

`MODE` is empty. Pick one of `public`, `cloudflare`, `local`, or `proxy`; see
[the guide](guide.md#1-choose-how-people-will-reach-your-server).

### `SERVER_NAME changed from … to …`

A server's name can't be changed after the first start. Put the old value
back in `.env`, or delete `data/` to start over (this erases everything).

### `Bind for 0.0.0.0:80 failed: port is already allocated`

Another program is already using that port.
- **`local` mode:** set `HTTP_PORT` / `HTTPS_PORT` to free ports.
- **`public` mode:** stop the other program, or switch to `proxy` mode behind
  it.
- **`proxy` mode:** change `ELEMENT_PORT` / `WELLKNOWN_PORT`.

### Certificates fail (`public` mode)

DNS doesn't point to the server yet, ports 80/443 aren't reachable from the
internet, or there's an AAAA record for IPv6 that doesn't work. See
[modes/public.md](modes/public.md#if-certificates-fail).

### Browser certificate warning (`local` mode, LAN)

The device doesn't trust the local CA yet. Run `./matrix.sh ca-cert` and
install the file; see [modes/local.md](modes/local.md#3-start-then-trust-the-certificate-authority).

### Cloudflare: error 502

- **A second `cloudflared` is connected to the same tunnel.** This usually
  happens after running the `docker run` command from the dashboard. On the
  server, run `docker ps | grep cloudflared` and `pgrep -a cloudflared`, and
  remove any copy that isn't part of this stack. The tunnel's page in the
  dashboard should list exactly one connector.
- **A route is wrong.** The service type must be `HTTP` (not HTTPS), and the
  URL must use the service name (`synapse:8008`, not `localhost:8008`).

### Cloudflare: error 1033 / 530

The tunnel has no running connector. `./matrix.sh logs cloudflared` usually
shows a missing or invalid `CLOUDFLARE_TUNNEL_TOKEN`.

### "Registration has been disabled"

The running Synapse is still using older configuration. Run
`./matrix.sh up`, and if needed, `./matrix.sh compose restart synapse`.

Note that Element asks for the invite token only **after** you submit a
username and password.

### Apps say the server can't be found

The app looks up `https://SERVER_NAME/.well-known/matrix/client`. Open that
address in a browser. It should show a short JSON text naming your
`MATRIX_HOST`. If it doesn't, check the DNS record or route for the bare
`SERVER_NAME`. As a workaround, enter `MATRIX_HOST` as the server address in
the app.

### Uploads fail for large files

You've hit `MAX_UPLOAD_SIZE`. In `cloudflare` mode, the limit can't exceed
about 100 MB because of Cloudflare's free plan.

### Federation tester shows errors

Federation must be enabled (`ENABLE_FEDERATION=true`), the mode must be
reachable from the internet (not `local`), and
`https://SERVER_NAME/.well-known/matrix/server` must return JSON. In
`cloudflare` mode, disable Bot Fight Mode for `MATRIX_HOST`.

### "Unable to decrypt" messages on a new device

Verify the new device from an existing one, or enter your recovery key
(Element: **Settings → Encryption**). Without either, older messages can't
be decrypted. The server never has the keys, so it can't help.
