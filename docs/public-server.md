# MODE=public: public IP + any DNS provider

[Caddy](https://caddyserver.com) listens on ports 80 and 443, gets free
**Let's Encrypt** certificates automatically, renews them, and routes each
hostname to the right container. Your DNS can be anywhere: Namecheap,
Porkbun, OVH, Hetzner, Route 53, Cloudflare in "DNS only" mode, and so on.
No traffic passes through a third party.

## Requirements

- **A public IPv4 address (or IPv6).** Any VPS has one. At home, compare your
  router's WAN address with what `curl -4 ifconfig.me` reports. If they
  differ, or the WAN address is in `100.64.0.0/10`, you're behind **CGNAT**
  and can't accept incoming connections. Use [MODE=cloudflare](cloudflare-tunnel.md)
  or a VPS instead.
- **Ports 80 and 443 reachable from the internet.** Port 80 is needed for
  Let's Encrypt's HTTP challenge and redirects.
- **Nothing else on the server using ports 80 or 443.** If something does,
  use [MODE=proxy](reverse-proxy.md) behind it.

## 1. DNS records

At your DNS provider, create records pointing to the server's public IP:

| Name | Type | Value |
|---|---|---|
| `matrix` | A | `203.0.113.10` |
| `chat` | A | `203.0.113.10` |
| `@` (the bare domain) | A | `203.0.113.10`, only if `SERVER_NAME` is the bare domain |

Add matching **AAAA** records if the server has IPv6. **Don't** add an AAAA
record if the server isn't actually reachable over IPv6, because Let's
Encrypt prefers IPv6 and will fail.

If the bare domain already hosts a website elsewhere, don't move it. Set
`SERVER_NAME` equal to `MATRIX_HOST` instead, so user IDs become
`@you:matrix.example.com`. Advanced alternative: keep the website, and have
it serve `/.well-known/matrix/client` and `/.well-known/matrix/server`, with
the contents of `templates/wellknown.conf`.

Check the records with `dig +short matrix.example.com`, which should print
your IP. With Cloudflare DNS, set the records to **DNS only** (grey cloud).
Proxied records (orange cloud) work too, but then you're back to Cloudflare
seeing traffic, and Caddy may struggle to get certificates.

## 2. Open the ports

**Firewall on the server**, if you use ufw:
```sh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp     # HTTP/3, optional
```

**Cloud providers** (AWS security groups, Oracle Cloud, GCP, Hetzner Cloud
firewall) also need an inbound rule for 80 and 443 in their web console.

**At home,** add a port forward on your router: external 80 → server-LAN-IP:80,
and external 443 → server-LAN-IP:443. Give the server a fixed LAN IP through
a DHCP reservation.

**If your home IP changes** (dynamic IP), keep DNS updated with your
provider's dynamic DNS feature, `ddclient`, or a small cron job that calls
your DNS provider's API.

## 3. Configure `.env`

```ini
MODE=public
SERVER_NAME=example.com
MATRIX_HOST=matrix.example.com
ELEMENT_HOST=chat.example.com
ACME_EMAIL=you@example.com     # Let's Encrypt expiry/problem notices
```

## 4. Start it

```sh
./deploy.sh user@server      # or, on the server itself: ./matrix.sh up
./matrix.sh logs caddy       # watch it obtain certificates (Ctrl-C to stop)
./matrix.sh status
```

Caddy requests the certificates on first start. You should see
`certificate obtained successfully` for each hostname. Then continue with
[operations.md](operations.md#first-account).

## If certificates fail

- **DNS doesn't point here yet.** Check with `dig +short` from another
  network.
- **Port 80 or 443 is blocked.** Test from outside, for example on your phone
  over mobile data: `http://matrix.example.com` should at least connect.
- **Rate limits.** Let's Encrypt limits failed attempts. Caddy backs off and
  retries on its own, so fix the cause and wait. Don't wipe `data/caddy`
  repeatedly.

## Federation

With `ENABLE_FEDERATION=true`, other servers find yours through
`https://SERVER_NAME/.well-known/matrix/server`. That file points them at
`MATRIX_HOST:443`, so port 8448 isn't needed. Verify the setup at
https://federationtester.matrix.org.
