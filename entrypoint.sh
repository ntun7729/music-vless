#!/usr/bin/env bash
set -euo pipefail

# Env vars (override in Render / VPS / Sealos)
UUID="${UUID:-257daab4-768d-4d0b-b8cb-1b2c38fe61f2}"
PORT="${PORT:-13000}"
SERVICE_NAME="${SERVICE_NAME:-grpc-c49c652f}"
NGINX_PORT="${NGINX_PORT:-8443}"
USE_TLS="${USE_TLS:-0}"           # 0 = plain HTTP on NGINX_PORT, 1 = nginx terminates TLS
TRANSPORT="${TRANSPORT:-ws}"      # ws | grpc
CF_TUNNEL_ENABLE="${CF_TUNNEL_ENABLE:-0}"
CF_TUNNEL_TOKEN="${CF_TUNNEL_TOKEN:-}"

# 1) Core config
mkdir -p /etc/core

if [ "${TRANSPORT}" = "ws" ]; then
  cat >/etc/core/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "${UUID}" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/${SERVICE_NAME}"
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {} }
  ]
}
EOF
else
  cat >/etc/core/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "${UUID}" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "${SERVICE_NAME}"
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {} }
  ]
}
EOF
fi

# 2) Website root
mkdir -p /var/www/music
cp -f /app/index.html /var/www/music/index.html

# 3) TLS assets (only when USE_TLS=1)
mkdir -p /etc/nginx
if [ "${USE_TLS}" = "1" ] && [ ! -f /etc/nginx/s2.crt ]; then
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /etc/nginx/s2.key \
    -out /etc/nginx/s2.crt \
    -days 365 \
    -subj "/CN=localhost" >/dev/null 2>&1
fi

mkdir -p /etc/nginx/conf.d

# 4) nginx vhost
if [ "${USE_TLS}" = "1" ]; then
  if [ "${TRANSPORT}" = "ws" ]; then
    cat >/etc/nginx/conf.d/grpc.conf <<EOF
server {
  listen ${NGINX_PORT} ssl http2;
  server_name _;

  ssl_certificate     /etc/nginx/s2.crt;
  ssl_certificate_key /etc/nginx/s2.key;

  root /var/www/music;
  index index.html;

  location / {
    try_files \$uri \$uri/ =404;
  }

  location /${SERVICE_NAME} {
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_pass http://127.0.0.1:${PORT};
  }
}
EOF
  else
    cat >/etc/nginx/conf.d/grpc.conf <<EOF
server {
  listen ${NGINX_PORT} ssl http2;
  server_name _;

  ssl_certificate     /etc/nginx/s2.crt;
  ssl_certificate_key /etc/nginx/s2.key;

  root /var/www/music;
  index index.html;

  location / {
    try_files \$uri \$uri/ =404;
  }

  location /${SERVICE_NAME} {
    grpc_set_header Host               \$host;
    grpc_set_header X-Real-IP          \$remote_addr;
    grpc_set_header X-Forwarded-For    \$proxy_add_x_forwarded_for;
    grpc_pass grpc://127.0.0.1:${PORT};
  }
}
EOF
  fi
else
  if [ "${TRANSPORT}" = "ws" ]; then
    cat >/etc/nginx/conf.d/grpc.conf <<EOF
server {
  listen ${NGINX_PORT};
  server_name _;

  root /var/www/music;
  index index.html;

  location / {
    try_files \$uri \$uri/ =404;
  }

  location /${SERVICE_NAME} {
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_pass http://127.0.0.1:${PORT};
  }
}
EOF
  else
    cat >/etc/nginx/conf.d/grpc.conf <<EOF
server {
  listen ${NGINX_PORT};
  server_name _;

  root /var/www/music;
  index index.html;

  location / {
    try_files \$uri \$uri/ =404;
  }

  location /${SERVICE_NAME} {
    grpc_set_header Host               \$host;
    grpc_set_header X-Real-IP          \$remote_addr;
    grpc_set_header X-Forwarded-For    \$proxy_add_x_forwarded_for;
    grpc_pass grpc://127.0.0.1:${PORT};
  }
}
EOF
  fi
fi

nginx -t >/dev/null 2>&1

# 5) Start core (silent)
/usr/bin/core run -config /etc/core/config.json >/dev/null 2>&1 &

# 6) Optional Cloudflare Tunnel (token-based)
if [ "${CF_TUNNEL_ENABLE}" = "1" ] && [ -n "${CF_TUNNEL_TOKEN}" ]; then
  /usr/bin/cloudflared tunnel run --token "${CF_TUNNEL_TOKEN}" >/dev/null 2>&1 &
fi

# 7) Start nginx in foreground
inginx -g 'daemon off;'
