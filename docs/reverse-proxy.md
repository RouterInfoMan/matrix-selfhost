# MODE=proxy: bring your own reverse proxy

Use this when the machine already runs nginx, Traefik, HAProxy, Caddy, or
Nginx Proxy Manager on ports 80 and 443. The stack doesn't touch those ports.
It only publishes its services for your proxy to forward to:

| Service | Address | Route these requests to it |
|---|---|---|
| synapse | `BIND_ADDRESS:8008` | everything on `MATRIX_HOST` |
| element | `BIND_ADDRESS:ELEMENT_PORT` (8080) | everything on `ELEMENT_HOST` |
| wellknown | `BIND_ADDRESS:WELLKNOWN_PORT` (8081) | `SERVER_NAME/.well-known/matrix/*` (only if `SERVER_NAME` differs from `MATRIX_HOST`) |

`BIND_ADDRESS` defaults to `127.0.0.1`, for a proxy on the same machine. If
the proxy is on another machine, set it to the server's LAN IP, and make sure
those ports aren't reachable from the internet.

```ini
MODE=proxy
SERVER_NAME=example.com
MATRIX_HOST=matrix.example.com
ELEMENT_HOST=chat.example.com
#BIND_ADDRESS=127.0.0.1
#ELEMENT_PORT=8080
#WELLKNOWN_PORT=8081
```

Your proxy is responsible for TLS certificates and DNS. All public URLs are
assumed to be `https://` on port 443.

Proxy requirements for Synapse:
- Pass the original `Host`, and set `X-Forwarded-For` and `X-Forwarded-Proto`.
- **Don't rewrite or decode the URL path.** In nginx, use
  `proxy_pass http://127.0.0.1:8008;` with **no** trailing slash or path.
- Allow request bodies at least as big as `MAX_UPLOAD_SIZE` (200M by default).

## nginx

```nginx
server {
    listen 443 ssl;
    http2 on;
    server_name matrix.example.com;
    # ssl_certificate / ssl_certificate_key: e.g. from certbot

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

    location / {
        proxy_pass http://127.0.0.1:8080;
    }
}

server {
    listen 443 ssl;
    http2 on;
    server_name example.com;

    location /.well-known/matrix/ {
        proxy_pass http://127.0.0.1:8081;
    }
    # ...your existing website for everything else...
}
```

## Caddy (an existing one)

```caddy
matrix.example.com {
	reverse_proxy 127.0.0.1:8008
}
chat.example.com {
	reverse_proxy 127.0.0.1:8080
}
example.com {
	handle /.well-known/matrix/* {
		reverse_proxy 127.0.0.1:8081
	}
	# ...your existing site...
}
```

## Traefik / Nginx Proxy Manager

Create three proxy hosts or routers matching the table at the top: for
example, `matrix.example.com` → `http://<server>:8008`, with websockets
allowed and no path rewriting. If your proxy runs in Docker on the same host,
`127.0.0.1` inside its container isn't the host. Point it at the host's LAN
IP, set `BIND_ADDRESS` to match, or use `host.docker.internal` where
supported.

## Check

```sh
./matrix.sh up
./matrix.sh status
```

The "public" checks in `status` go through your proxy. If they fail while
`synapse (local)` says OK, the proxy configuration is the problem.
