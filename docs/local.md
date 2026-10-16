# MODE=local: your machine or your home network

There are two variants. Which one you get depends on the names in `.env`.

| Names | Result |
|---|---|
| `*.localhost` | Plain HTTP, **this computer only**. No setup needed, good for trying things out. |
| anything else (e.g. `home.arpa`) | HTTPS with certificates from **Caddy's own certificate authority**. Works for **every device on your LAN** once they trust that CA. |

Either way, nothing is reachable from the internet unless you forward ports.
Federation can't work either, so leave `ENABLE_FEDERATION=false`.

---

## A. Try it on this computer (`*.localhost`)

```ini
MODE=local
SERVER_NAME=matrix.localhost
MATRIX_HOST=matrix.localhost
ELEMENT_HOST=chat.localhost
```

```sh
./matrix.sh up
./matrix.sh adduser me --admin
```

Open **http://chat.localhost** and sign in. Browsers resolve any `*.localhost`
name to your own machine and treat it as secure, so encryption works without
certificates.

- **Port 80 already in use?** Set `HTTP_PORT=8880`, then open
  http://chat.localhost:8880. The script includes the port in every URL.
- **WSL2:** browsers on Windows reach it as well, because WSL forwards
  `localhost` ports to Windows.
- **Not for phones.** `matrix.localhost` on your phone means the phone itself.
  Use variant B for other devices.

---

## B. Home network (LAN) with HTTPS

Pick names that only exist on your network. `home.arpa` is reserved for
exactly this purpose, so it can never clash with a real website:

```ini
MODE=local
SERVER_NAME=home.arpa
MATRIX_HOST=matrix.home.arpa
ELEMENT_HOST=chat.home.arpa
```

A domain you own (`matrix.example.com`) works too. It just won't be reachable
from outside.

### 1. Make the names resolve to the server

Find the server's LAN IP with `ip -4 addr`, e.g. `192.168.1.50`, and give it a
fixed address through a DHCP reservation on your router. Then choose one of
these:

- **Router / Pi-hole / AdGuard Home:** add local DNS records for
  `home.arpa`, `matrix.home.arpa` and `chat.home.arpa`, each pointing to
  `192.168.1.50`. Every device on the network picks them up automatically.
  This is the best option.
- **Hosts file on each device:** add this line:
  ```
  192.168.1.50  home.arpa matrix.home.arpa chat.home.arpa
  ```
  It goes in `/etc/hosts` on Linux and macOS, and in
  `C:\Windows\System32\drivers\etc\hosts` on Windows (edit as Administrator).
  Phones can't easily edit hosts files, so use router DNS for them.

### 2. Start it and export the CA

```sh
./matrix.sh up
./matrix.sh ca-cert        # writes matrix-local-ca.crt
```

Copy `matrix-local-ca.crt` to each device and install it as a **trusted root
certificate**:

| Device | How |
|---|---|
| Windows | Double-click → **Install Certificate** → Local Machine → "Place all certificates in…" → **Trusted Root Certification Authorities**. Or, as Administrator, run `certutil -addstore -f Root matrix-local-ca.crt`. |
| macOS | `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain matrix-local-ca.crt` |
| Linux (Debian/Ubuntu) | `sudo cp matrix-local-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates` |
| Firefox (any OS) | Settings → Privacy & Security → Certificates → View Certificates → Authorities → Import. Or enable `security.enterprise_roots.enabled` in `about:config` so Firefox uses the OS store. |
| iOS | Send yourself the file → Settings → **Profile Downloaded** → Install. Then go to Settings → General → About → **Certificate Trust Settings** and turn it on. |
| Android | Settings → Security → Encryption & credentials → **Install a certificate** → CA certificate. |

Then open **https://chat.home.arpa**.

**Phone apps:** Android apps ignore user-installed CAs unless the app opts
in, and native apps like Element X may refuse the certificate. The browser
version at `https://chat.home.arpa` works on any device that trusts the CA.
If the apps matter to you, use a real domain with
[MODE=public](public-server.md) or [MODE=cloudflare](cloudflare-tunnel.md),
or the Tailscale option below.

`data/caddy/` holds the CA's private key. `./matrix.sh backup` includes it,
so keep your backups private. If it's lost, Caddy creates a new CA, and
you'll have to install the new certificate on every device again.

---

## Reaching a LAN server from outside, without opening ports

Use a VPN such as **WireGuard** or **Tailscale**. Away from home, your devices
join the network and use the server as if they were on the LAN. With
Tailscale, point the names at the server's Tailscale IP using its "split DNS"
feature, or use hosts entries.
