FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Basic deps
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl unzip nginx openssl && \
    rm -rf /var/lib/apt/lists/*

# Install Xray
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64|amd64) XRAY_ZIP="Xray-linux-64.zip" ;; \
      aarch64|arm64) XRAY_ZIP="Xray-linux-arm64-v8a.zip" ;; \
      armv7l|armv7|arm) XRAY_ZIP="Xray-linux-arm32-v7a.zip" ;; \
      *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;; \
    esac && \
    curl -L -o /tmp/xray.zip \
      "https://github.com/XTLS/Xray-core/releases/latest/download/${XRAY_ZIP}" && \
    mkdir -p /tmp/xray && \
    unzip -o /tmp/xray.zip -d /tmp/xray >/dev/null && \
    install -m 0755 /tmp/xray/xray /usr/bin/xray && \
    mkdir -p /usr/share/xray && \
    install -m 0644 /tmp/xray/geoip.dat /usr/share/xray/geoip.dat && \
    install -m 0644 /tmp/xray/geosite.dat /usr/share/xray/geosite.dat && \
    rm -rf /tmp/xray /tmp/xray.zip

# App files
WORKDIR /app
COPY index.html /app/index.html
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Default envs (override in Render)
ENV UUID=257daab4-768d-4d0b-b8cb-1b2c38fe61f2 \
    XRAY_GRPC_PORT=13000 \
    XRAY_SERVICE_NAME=grpc-c49c652f \
    NGINX_PORT=8443

EXPOSE 8443

CMD ["/entrypoint.sh"]
