#!/usr/bin/env bash
set -euo pipefail

# Env vars (override in Render / docker run)
UUID="${UUID:-257daab4-768d-4d0b-b8cb-1b2c38fe61f2}"
XRAY_GRPC_PORT="${XRAY_GRPC_PORT:-13000}"
XRAY_SERVICE_NAME="${XRAY_SERVICE_NAME:-grpc-c49c652f}"
NGINX_PORT="${NGINX_PORT:-8443}"

echo "[*] Starting Xray + nginx"
echo "    UUID=${UUID}"
echo "    XRAY_GRPC_PORT=${XRAY_GRPC_PORT}"
echo "    XRAY_SERVICE_NAME=${XRAY_SERVICE_NAME}"
echo "    NGINX_PORT=${NGINX_PORT}"

# 1) Xray config
mkdir -p /etc/xray
cat >/etc/xray/config.grpc.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${XRAY_GRPC_PORT},
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
          "serviceName": "${XRAY_SERVICE_NAME}"
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
    -subj "/CN=localhost"
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

  location /${XRAY_SERVICE_NAME} {
    grpc_set_header Host               $host;
    grpc_set_header X-Real-IP          $remote_addr;
    grpc_set_header X-Forwarded-For    $proxy_add_x_forwarded_for;
    grpc_pass grpc://127.0.0.1:${XRAY_GRPC_PORT};
  }
}
EOF

nginx -t

# 5) Start Xray + nginx in foreground
/usr/bin/xray run -config /etc/xray/config.grpc.json &
XPID=$!
nginx
NPID=$!

echo "[*] Xray PID=${XPID}, nginx PID=${NPID}"
wait -n "$XPID" "$NPID"
