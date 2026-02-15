# music-vless container

Silent VLESS node container that bundles:

- A VLESS core (installed as `/usr/bin/core`)
- nginx for HTTP/site + reverse proxy
- Optional Cloudflare Tunnel (token-based)

It is designed to run on PaaS platforms (Render, Sealos, etc.) and VPS, while avoiding obvious keywords and noisy logs.

## Environment variables

Common envs:

- `UUID` – VLESS user ID (default: `257daab4-768d-4d0b-b8cb-1b2c38fe61f2` – change this!)
- `PORT` – internal core port (default: `13000`)
- `SERVICE_NAME` – path / gRPC service name (default: `grpc-c49c652f`)
- `NGINX_PORT` – nginx listen port (default: `8443`)
- `TRANSPORT` – `ws` or `grpc`
  - `ws` (default) – VLESS over WebSocket (`/${SERVICE_NAME}`)
  - `grpc` – VLESS over gRPC (`serviceName = SERVICE_NAME`)
- `USE_TLS` – `0` or `1`
  - `0` – nginx listens in plain HTTP (for platforms that terminate TLS before container)
  - `1` – nginx terminates TLS itself (self-signed cert), useful when using Cloudflare Tunnel inside container

Cloudflare Tunnel envs:

- `CF_TUNNEL_ENABLE` – `0` or `1` (default `0`)
  - `1` – start `cloudflared tunnel run` inside the container
- `CF_TUNNEL_TOKEN` – token string for a **named tunnel** created in your Cloudflare account

Logs are suppressed as much as possible:

- `core` is started with stdout/stderr redirected to `/dev/null`
- `cloudflared` is started with stdout/stderr redirected to `/dev/null`

## Modes

### 1. WS mode on PaaS (no Cloudflare Tunnel)

Good for Render / Sealos when you use the platform's own HTTPS domain.

**Env example:**

```env
UUID=YOUR-UUID
PORT=13000
SERVICE_NAME=grpc-c49c652f
NGINX_PORT=8443
TRANSPORT=ws
USE_TLS=0
CF_TUNNEL_ENABLE=0
```

- Platform terminates HTTPS and sends HTTP to your container.
- nginx listens on `NGINX_PORT` in plain HTTP.
- VLESS clients use:
  - `type: vless`
  - `host: <platform-domain>`
  - `port: 443`
  - `transport: ws`
  - `path: /${SERVICE_NAME}`

### 2. gRPC mode on VPS with Cloudflare Tunnel (external `cloudflared`)

This is how `music.nyan.college` is set up on your VPS: a tunnel running on the VPS itself, not in the container. You already have this working, so it's not described in detail here.

### 3. gRPC mode on PaaS **with Cloudflare Tunnel inside the container**

This is what you asked for: use a **tunnel domain** (e.g. `node.example.com`) instead of the platform's random domain, and keep gRPC end-to-end.

The idea:

- Container runs:
  - `core` (VLESS+gRPC)
  - nginx (TLS + gRPC proxy)
  - `cloudflared tunnel run --token ...` (inside container)
- Cloudflare sees only the tunnel connection from container → CF; the PaaS HTTP ingress is bypassed for user traffic.

### Cloudflare side (once)

On a machine where you have `cloudflared` and a browser:

1. Login & create tunnel

```bash
cloudflared tunnel login
cloudflared tunnel create vless-node
```

2. In Cloudflare Zero Trust dashboard:

- Go to **Tunnels** → select `vless-node`
- Add **Public hostname**:
  - Hostname: `node.example.com`
  - Service: `https://localhost:8443`

This tells Cloudflare to send traffic for `node.example.com` through the tunnel into `https://localhost:8443` (nginx inside container). HTTPS here is important so CF speaks HTTP/2+gRPC to nginx.

3. Get the tunnel token

```bash
cloudflared tunnel token vless-node
```

Copy that token string. You will use it as `CF_TUNNEL_TOKEN` in the container.

### Container env for gRPC + Tunnel (PaaS or VPS)

Configure the service running `ghcr.io/ntun7729/music-vless:latest` with:

```env
UUID=YOUR-UUID
PORT=13000
SERVICE_NAME=grpc-c49c652f
NGINX_PORT=8443
TRANSPORT=grpc
USE_TLS=1
CF_TUNNEL_ENABLE=1
CF_TUNNEL_TOKEN=YOUR-TUNNEL-TOKEN
```

- `TRANSPORT=grpc` – core uses VLESS+gRPC inbound.
- `USE_TLS=1` – nginx terminates TLS on `NGINX_PORT` and proxies gRPC to core.
- `CF_TUNNEL_ENABLE=1` + `CF_TUNNEL_TOKEN` – starts `cloudflared tunnel run --token <token>` silently in the background.

**Client config:**

Use the tunnel hostname you set in Cloudflare (e.g. `node.example.com`):

- Type: VLESS
- Address: `node.example.com`
- Port: `443`
- UUID: your `UUID`
- Encryption: `none`
- Network: `grpc`
- TLS: on
- gRPC `serviceName`: `SERVICE_NAME` (e.g. `grpc-c49c652f`)

VLESS URL example:

```text
vless://YOUR-UUID@node.example.com:443?encryption=none&security=tls&type=grpc&serviceName=grpc-c49c652f#node-example-grpc
```

With this setup, the platform (Render/Sealos/etc.) only sees outbound connections from the container to Cloudflare; all user traffic flows through your Cloudflare tunnel and never touches the platform's HTTP router.
