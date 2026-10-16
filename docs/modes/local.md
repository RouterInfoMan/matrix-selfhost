# Mode: `local`: this computer or your home network

In this mode, [Caddy](https://caddyserver.com) serves the chat on your
machine. Nothing is reachable from the internet, and federation isn't
possible. There are two variants, chosen by the names you use:

- **A. Trial on this computer:** names ending in `.localhost`. Plain HTTP, no
  setup needed.
- **B. Home network (LAN):** any other names. HTTPS with certificates from a
  private certificate authority (CA) that Caddy creates; your devices need
  to trust it.

---

## A. Trial on this computer

```ini
MODE=local
SERVER_NAME=matrix.localhost
MATRIX_HOST=matrix.localhost
ELEMENT_HOST=chat.localhost
```

That's all. Go back to [step 6 of the guide](../guide.md#6-start-the-server),
then open **http://chat.localhost**.

Browsers resolve every `*.localhost` name to your own computer and treat it
as secure, so encryption works without certificates.

- **Port 80 already in use?** Set `HTTP_PORT=8880` in `.env`, and open
  `http://chat.localhost:8880` instead.
- **WSL2 on Windows:** Windows browsers can open it too.
- **Other devices can't use this variant,** because `localhost` always means
  "this device". Use variant B for them.

---

## B. Home network (LAN)

Use names that only exist on your network. `home.arpa` is reserved for
exactly this purpose, so it never clashes with real websites:

```ini
MODE=local
SERVER_NAME=home.arpa
MATRIX_HOST=matrix.home.arpa
ELEMENT_HOST=chat.home.arpa
```

### 1. Give the server a fixed address

Find the server's LAN IP (`ip -4 addr`, e.g. `192.168.1.50`), and reserve it
in your router's DHCP settings so it never changes.

### 2. Make the names point to the server

Choose one of these:

- **Local DNS (recommended).** Most routers, and tools like Pi-hole and
  AdGuard Home, let you add local DNS records. Point `home.arpa`,
  `matrix.home.arpa` and `chat.home.arpa` to `192.168.1.50`. Every device on
  the network then finds them automatically.
- **Hosts file on each computer.** Add this line:
  ```
  192.168.1.50  home.arpa matrix.home.arpa chat.home.arpa
  ```
  It goes in `/etc/hosts` on Linux and macOS, and in
  `C:\Windows\System32\drivers\etc\hosts` on Windows (edit as Administrator).
  Phones can't easily do this, so use local DNS for them.

### 3. Start, then trust the certificate authority

Go through [step 6 of the guide](../guide.md#6-start-the-server). Then
export Caddy's CA certificate:

```sh
./matrix.sh ca-cert      # writes matrix-local-ca.crt
```

Copy `matrix-local-ca.crt` to each device and install it as a **trusted root
certificate**:

| Device | How to install it |
|---|---|
| Windows | Double-click it → **Install Certificate** → Local Machine → **Place all certificates in the following store** → *Trusted Root Certification Authorities*. |
| macOS | Double-click it to add it to Keychain Access. Then open it, expand **Trust**, and set **When using this certificate** to *Always Trust*. |
| Linux (Debian/Ubuntu) | `sudo cp matrix-local-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates` |
| Firefox (any OS) | Settings → Privacy & Security → **View Certificates** → Authorities → **Import**, then tick "trust this CA to identify websites". |
| iPhone / iPad | Send the file to the device and open it. Then go to Settings → **Profile Downloaded** → Install, and turn it on under Settings → General → About → **Certificate Trust Settings**. |
| Android | Settings → Security → Encryption & credentials → **Install a certificate** → *CA certificate*. |

Then open **https://chat.home.arpa** and continue with
[step 7 of the guide](../guide.md#7-create-your-account-and-sign-in).

**Phone apps:** many Android apps ignore user-installed certificates, and
some native apps may refuse a private CA. The browser version works on any
device that trusts the CA. If you need the native apps on your network, a
real domain with [`public`](public.md) or [`cloudflare`](cloudflare.md) mode
is more reliable.

`data/caddy/` holds the CA's private key. Backups include it, so keep them
private. If the key is lost, Caddy creates a new CA, and you'll need to
install the new certificate on every device again.

---

## Using a home-network server while away

Connect to your home network with a VPN, such as **WireGuard** or
**Tailscale**, so your devices can reach the server without opening it to the
internet. With Tailscale, use its DNS settings to point your names at the
server's Tailscale IP.
