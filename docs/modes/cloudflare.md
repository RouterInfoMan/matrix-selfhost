# Mode: `cloudflare`: Cloudflare Tunnel

In this mode, a small `cloudflared` service runs next to the server and opens
an **outbound** connection to Cloudflare. Cloudflare serves your hostnames
over HTTPS and passes requests through that connection. Your machine needs
**no open ports, no public IP, and no certificates**, so this works behind
CGNAT and strict firewalls.

The trade-off: Cloudflare decrypts the HTTPS connection at its edge, so it
can see the traffic. See [security.md](../security.md#cloudflare-mode). Its
free plan also limits uploads to 100 MB per file, so this kit sets a 95 MB
limit.

```ini
MODE=cloudflare
CLOUDFLARE_TUNNEL_TOKEN=     # from step 2 below
```

## 1. Add your domain to Cloudflare

At [dash.cloudflare.com](https://dash.cloudflare.com), add your domain on
the Free plan. Then, at your domain registrar, replace the nameservers with
the two Cloudflare gives you. Wait until Cloudflare shows the domain as
**Active**. This usually takes minutes, but can take up to a day.

## 2. Create a tunnel

1. Open the **Zero Trust** dashboard: [one.dash.cloudflare.com](https://one.dash.cloudflare.com).
   On first use, pick a team name and the **Free** plan.
2. Go to **Networks → Tunnels → Create a tunnel**, and choose **Cloudflared**.
   Name it, e.g. `matrix`.
3. On the **Install and run a connector** screen, choose **Docker**. The
   page shows a command containing `--token eyJ…`. Copy **only the token**
   (the long string starting with `eyJ`) into `CLOUDFLARE_TUNNEL_TOKEN` in
   your `.env`.

> ⚠️ **Don't run the command Cloudflare shows.** This kit runs `cloudflared`
> for you. A second copy would join the same tunnel without being able to
> reach the server, and Cloudflare would send some of your traffic to it.
> That shows up as random **502 errors**.

## 3. Add the routes

Click **Next** to reach the hostname routing screen. It's called **Public
hostnames** or **Published application routes**, depending on the dashboard
version. Add these entries, using your own names:

| Subdomain | Domain | Path | Service type | URL |
|---|---|---|---|---|
| `matrix` | `example.com` | *(empty)* | `HTTP` | `synapse:8008` |
| `chat` | `example.com` | *(empty)* | `HTTP` | `element:80` |
| *(empty)* | `example.com` | `.well-known/matrix/*` | `HTTP` | `wellknown:80` |

- **The service type is `HTTP`, not HTTPS.** Cloudflare handles HTTPS, and
  inside your machine the tunnel talks plain HTTP to the services by
  container name.
- **Skip the third route** if your `SERVER_NAME` equals your `MATRIX_HOST`.
- **"A DNS record already exists"** on the third route means your bare domain
  already points somewhere. If that's an unused leftover, delete it under
  **DNS → Records** in the main dashboard. If it's a real website, set
  `SERVER_NAME` equal to `MATRIX_HOST` instead, before you start the server
  for the first time.

Cloudflare creates the DNS records automatically.

## 4. Continue

Go back to [step 6 of the guide](../guide.md#6-start-the-server). A few
seconds after starting, the tunnel shows as **Healthy** in the dashboard,
with exactly **one** connector.

## Cloudflare features to avoid

- **Cloudflare Access** (Zero Trust login pages) in front of `MATRIX_HOST`
  stops Matrix apps from connecting. Protecting `ELEMENT_HOST` with it is
  fine.
- **Bot Fight Mode** and **"I'm Under Attack" mode** block traffic from other
  Matrix servers, which matters if you enable federation. Turn them off, or
  add a WAF rule that skips them for `MATRIX_HOST`.
