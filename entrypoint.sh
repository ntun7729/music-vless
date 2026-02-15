#!/usr/bin/env bash
set -euo pipefail

# Env vars (override in Render / docker run)
UUID="${UUID:-257daab4-768d-4d0b-b8cb-1b2c38fe61f2}"
GRPC_PORT="${GRPC_PORT:-13000}"
SERVICE_NAME="${SERVICE_NAME:-grpc-c49c652f}"
NGINX_PORT="${NGINX_PORT:-8443}"

# 1) Core config
mkdir -p /etc/core
cat >/etc/core/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${GRPC_PORT},
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

# 2) Website root
mkdir -p /var/www/music
cp -f /app/index.html /var/www/music/index.html

# 3) Self-signed cert (used only if TLS terminates here)
mkdir -p /etc/nginx
if [ ! -f /etc/nginx/s2.crt ]; then
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /etc/nginx/s2.key \
    -out /etc/nginx/s2.crt \
    -days 365 \
    -subj "/CN=localhost" >/dev/null 2>&1
fi

# 4) nginx vhost
cat >/etc/nginx/conf.d/grpc.conf <<EOF
server {
  listen ${NGINX_PORT} ssl http2;
  server_name _;

  ssl_certificate     /etc/nginx/s2.crt;
  ssl_certificate_key /etc/nginx/s2.key;

  root /var/www/music;
  index index.html;

  location / {
    try_files $uri $uri/ =404;
  }

  location /${SERVICE_NAME} {
    grpc_set_header Host               $host;
    grpc_set_header X-Real-IP          $remote_addr;
    grpc_set_header X-Forwarded-For    $proxy_add_x_forwarded_for;
    grpc_pass grpc://127.0.0.1:${GRPC_PORT};
  }
}
EOF

nginx -t >/dev/null 2>&1

# 5) Start core (silent) + nginx
/usr/bin/core run -config /etc/core/config.json >/dev/null 2>&1 &
nginx -g 'daemon off;'
