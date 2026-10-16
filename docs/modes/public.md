# Mode: `public`: public server, any DNS provider

In this mode, [Caddy](https://caddyserver.com) runs in front of the server on
ports 80 and 443. It obtains free **Let's Encrypt** HTTPS certificates
automatically, renews them, and sends each hostname to the right service.
Your DNS can be at any provider. Traffic goes straight to your machine, with
no third party in between.

```ini
MODE=public
ACME_EMAIL=you@example.com    # Let's Encrypt sends certificate problem notices here
```

## Check that you can use this mode

You need a **public IP address** that reaches this machine.

- **VPS / cloud server:** you have one. It's shown in your provider's
  dashboard.
- **Home server:** compare the WAN address on your router's status page with
  the output of `curl -4 ifconfig.me`. If they differ, or the WAN address
  starts with `100.64`–`100.127`, your provider uses **CGNAT**, and incoming
  connections can't reach you. Use [`cloudflare`](cloudflare.md) instead.

Also check that **nothing else on the machine uses ports 80 or 443**, for
example with `sudo ss -ltnp | grep -E ':(80|443) '`. If something does, use
[`proxy`](proxy.md) mode behind it instead.

## 1. Create DNS records

At your DNS provider, create an **A record** for each name, pointing to the
server's public IPv4 address:

| Name | Type | Value |
|---|---|---|
| `matrix.example.com` (your `MATRIX_HOST`) | A | `203.0.113.10` |
| `chat.example.com` (your `ELEMENT_HOST`) | A | `203.0.113.10` |
| `example.com` (your `SERVER_NAME`, if it's different) | A | `203.0.113.10` |

- **IPv6:** if the server has working IPv6, add matching **AAAA** records.
  Don't add AAAA records for IPv6 that doesn't work, because certificate
  issuance will fail.
- **Cloudflare DNS:** set the records to **DNS only** (grey cloud).

Check the records from your computer. Both commands should print your
server's IP:

```sh
nslookup matrix.example.com
nslookup chat.example.com
```

Changes can take a few minutes to propagate.

## 2. Open ports 80 and 443

**Server firewall.** With ufw:

```sh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp     # HTTP/3, optional
```

**Cloud provider firewall.** Many providers (AWS, Oracle Cloud, Google
Cloud, Hetzner, …) have their own firewall or security group in the web
console. Allow inbound TCP 80 and 443 there too.

**Home router.** Forward external ports 80 and 443 to the server's LAN IP.
Give the server a fixed LAN IP with a DHCP reservation, so the forward
doesn't break.

**Dynamic home IP?** If your public IP changes, use your DNS provider's
dynamic DNS feature, or a client such as `ddclient`, to keep the records
current.

## 3. Continue

Go back to [step 6 of the guide](../guide.md#6-start-the-server). After
starting, watch Caddy get its certificates:

```sh
./matrix.sh logs caddy     # look for "certificate obtained successfully"; Ctrl-C to stop
```

## If certificates fail

- **DNS doesn't point to this server yet.** Check with `nslookup` from
  another network.
- **Ports 80 or 443 aren't reachable from outside.** Test from a phone on
  mobile data: `http://matrix.example.com` should at least load something.
- **Too many failed attempts.** Let's Encrypt rate-limits failures. Caddy
  retries on its own with a back-off, so fix the cause and wait. Don't delete
  `data/caddy` repeatedly.
