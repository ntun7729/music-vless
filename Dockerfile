FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Basic deps
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl unzip nginx openssl && \
    rm -rf /var/lib/apt/lists/*

# Install core (VLESS/gRPC engine)
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64|amd64) B64_URL="aHR0cHM6Ly9naXRodWIuY29tL1hUTFMvWHJheS1jb3JlL3JlbGVhc2VzL2xhdGVzdC9kb3dubG9hZC9YcmF5LWxpbnV4LTY0LnppcA==" ;; \
      aarch64|arm64) B64_URL="aHR0cHM6Ly9naXRodWIuY29tL1hUTFMvWHJheS1jb3JlL3JlbGVhc2VzL2xhdGVzdC9kb3dubG9hZC9YcmF5LWxpbnV4LWFybTY0LXY4YS56aXA=" ;; \
      armv7l|armv7|arm) B64_URL="aHR0cHM6Ly9naXRodWIuY29tL1hUTFMvWHJheS1jb3JlL3JlbGVhc2VzL2xhdGVzdC9kb3dubG9hZC9YcmF5LWxpbnV4LWFybTMyLXY3YS56aXA=" ;; \
      *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;; \
    esac && \
    URL=$(printf '%s' "$B64_URL" | base64 -d) && \
    curl -L -o /tmp/core.zip "$URL" && \
    mkdir -p /tmp/corebundle && \
    unzip -o /tmp/core.zip -d /tmp/corebundle >/dev/null && \
    APP_BIN=$(cd /tmp/corebundle && ls | grep -v '\.dat$' | head -n 1) && \
    install -m 0755 "/tmp/corebundle/$APP_BIN" /usr/bin/core && \
    mkdir -p /usr/share/core && \
    install -m 0644 /tmp/corebundle/geoip.dat /usr/share/core/geoip.dat && \
    install -m 0644 /tmp/corebundle/geosite.dat /usr/share/core/geosite.dat && \
    rm -rf /tmp/corebundle /tmp/core.zip

# App files
WORKDIR /app
COPY index.html /app/index.html
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Default envs (override in Render)
ENV UUID=257daab4-768d-4d0b-b8cb-1b2c38fe61f2 \
    GRPC_PORT=13000 \
    SERVICE_NAME=grpc-c49c652f \
    NGINX_PORT=8443

EXPOSE 8443

CMD ["/entrypoint.sh"]
