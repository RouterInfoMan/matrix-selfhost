# Mode: `proxy`: behind your existing reverse proxy

Use this mode when the machine (or your network) already has a web server or
reverse proxy on ports 80/443, such as nginx, Traefik, Caddy, HAProxy, or
Nginx Proxy Manager. This kit doesn't touch those ports. It publishes its
services on local ports for your proxy to forward to. Your proxy handles DNS
and HTTPS certificates.

```ini
MODE=proxy
#BIND_ADDRESS=127.0.0.1    # change to the server's LAN IP if the proxy runs on another machine
#ELEMENT_PORT=8080
#WELLKNOWN_PORT=8081
```

## What to forward

| Requests for | Forward to |
|---|---|
| `https://MATRIX_HOST/` (everything) | `http://BIND_ADDRESS:8008` |
| `https://ELEMENT_HOST/` (everything) | `http://BIND_ADDRESS:ELEMENT_PORT` (default 8080) |
| `https://SERVER_NAME/.well-known/matrix/*`, only if `SERVER_NAME` differs from `MATRIX_HOST` | `http://BIND_ADDRESS:WELLKNOWN_PORT` (default 8081) |

All public addresses are assumed to be `https://` on port 443.

For the Synapse route:
- Pass the original `Host` header, and set `X-Forwarded-For` and
  `X-Forwarded-Proto`.
- **Don't rewrite or normalise the URL path.** In nginx, write
  `proxy_pass http://127.0.0.1:8008;` with nothing after the port.
- Allow request bodies at least as large as `MAX_UPLOAD_SIZE` (200M by
  default).

If the proxy runs on another machine, set `BIND_ADDRESS` to this server's LAN
IP, and make sure ports 8008, 8080 and 8081 aren't exposed to the internet.

## nginx

```nginx
server {
    listen 443 ssl;
    http2 on;
    server_name matrix.example.com;
    # ssl_certificate ...; ssl_certificate_key ...;

    client_max_body_size 200M;

    location / {
        proxy_pass http://127.0.0.1:8008;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
    }
}

server {
    listen 443 ssl;
    http2 on;
    server_name chat.example.com;
    # ssl_certificate ...; ssl_certificate_key ...;

    location / {
        proxy_pass http://127.0.0.1:8080;
    }
}

# Only if SERVER_NAME (example.com) differs from MATRIX_HOST:
server {
    listen 443 ssl;
    http2 on;
    server_name example.com;
    # ssl_certificate ...; ssl_certificate_key ...;

    location /.well-known/matrix/ {
        proxy_pass http://127.0.0.1:8081;
    }
    # ... the rest of your website ...
}
```

## Caddy

```caddy
matrix.example.com {
	reverse_proxy 127.0.0.1:8008
}

chat.example.com {
	reverse_proxy 127.0.0.1:8080
}

# Only if SERVER_NAME differs from MATRIX_HOST:
example.com {
	handle /.well-known/matrix/* {
		reverse_proxy 127.0.0.1:8081
	}
	# ... the rest of your website ...
}
```

## Traefik, Nginx Proxy Manager, and others

Create one proxy host or router per row of the table above. If the proxy
itself runs in Docker, `127.0.0.1` inside its container is **not** the host.
Use the host's LAN IP (and set `BIND_ADDRESS` to it), or
`host.docker.internal` where your setup supports it.

## Continue

Go back to [step 6 of the guide](../guide.md#6-start-the-server). The
reachability checks in `./matrix.sh status` go through your proxy. If they
fail while `synapse (local)` says OK, the proxy configuration is the
problem.
