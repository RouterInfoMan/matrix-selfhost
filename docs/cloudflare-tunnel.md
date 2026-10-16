# MODE=cloudflare: Cloudflare Tunnel

`cloudflared` runs next to Synapse and opens an **outbound** connection to
Cloudflare. Cloudflare serves your hostnames over HTTPS and forwards requests
through the tunnel. The server needs **no open ports, no public IP, and no
certificates**, so this works behind NAT, CGNAT, and strict firewalls.

The trade-off is that Cloudflare decrypts HTTPS at its edge, so it can see
the traffic. That includes who talks to whom and when, plus message contents
in **unencrypted** rooms. Encrypted rooms (the default here) stay opaque.
Requests are also limited to 100 MB on the free plan, so uploads are capped
at 95 MB.

## 1. Put your domain on Cloudflare

At dash.cloudflare.com, add the domain and switch your registrar's nameservers
to the two Cloudflare gives you. Wait until the domain shows **Active**.

## 2. Configure `.env`

```ini
MODE=cloudflare
SERVER_NAME=example.com
MATRIX_HOST=matrix.example.com
ELEMENT_HOST=chat.example.com
CLOUDFLARE_TUNNEL_TOKEN=          # filled in next
```

## 3. Create the tunnel

1. Open **one.dash.cloudflare.com** (Zero Trust). The first time, choose a team
   name and the **Free** plan.
2. Go to **Networks → Tunnels → Create a tunnel → Cloudflared**, and name it
   (e.g. `matrix`).
3. On the "install connector" screen, pick **Docker**. Copy **only the token**
   (the long `eyJ…` string after `--token`) into `CLOUDFLARE_TUNNEL_TOKEN`.

> ⚠️ **Don't run the `docker run` command Cloudflare shows you.** The stack
> already runs cloudflared. A second copy outside the stack's Docker network
> joins the same tunnel and can't reach the containers. Cloudflare then sends
> some requests to it, and those fail with **502** errors.

## 4. Add the routes

These are called **Public hostnames** or **Published application routes**:

| Subdomain | Domain | Path | Type | URL |
|---|---|---|---|---|
| `matrix` | example.com | | **HTTP** | `synapse:8008` |
| `chat` | example.com | | **HTTP** | `element:80` |
| *(empty)* | example.com | `.well-known/matrix/*` | **HTTP** | `wellknown:80` |

- **Type must be HTTP.** TLS ends at Cloudflare, and inside the server the
  tunnel talks plain HTTP to the containers **by name**, not `localhost`.
- **Skip the third route** if `SERVER_NAME` equals `MATRIX_HOST`.
- **"DNS record already exists" on the third route** means your bare domain
  already points somewhere else. Delete that record if it's unused, or set
  `SERVER_NAME=MATRIX_HOST` **before the first start**.

Cloudflare creates the DNS records for you.

## 5. Start it

```sh
./deploy.sh user@server      # or, on the server itself: ./matrix.sh up
```

The tunnel should show **HEALTHY** in the dashboard, with exactly **one**
connector. Then continue with [operations.md](operations.md#first-account).

## Cloudflare settings that break Matrix

- **Cloudflare Access** (the Zero Trust login page) in front of `MATRIX_HOST`
  stops apps from working. You can put it in front of `ELEMENT_HOST` only, if
  you like.
- **Bot Fight Mode** and **"I'm Under Attack"** (in the main dashboard, under
  Security) block other Matrix servers. This only matters with
  `ENABLE_FEDERATION=true`. Turn them off, or add a WAF skip rule for
  `MATRIX_HOST`.

## Other tunnels on the same machine

Other `cloudflared` instances, for example a systemd service with
`/etc/cloudflared/config.yml` serving other sites, are fine **as long as they
run a different tunnel**. To see which tunnel a token belongs to, decode it
with `echo <token> | base64 -d`. The `"t"` field is the tunnel ID. It must
match the target of your `*.cfargotunnel.com` DNS records.
