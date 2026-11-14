#!/bin/bash
# Family notes (Memos) on the K2K server, behind HTTPS at notes.<ip>.sslip.io.
# Usage: sudo bash install-memos.sh [public-ip]
set -euo pipefail
IP="${1:-217.142.143.66}"
HOST="notes.$(echo "$IP" | tr . -).sslip.io"
BASE="https://github.com/versper77-lab/rustdesk/releases/download/k2k-server"
cd /opt/k2k-server
mkdir -p memos backups
cp docker-compose.yml "docker-compose.yml.bak-$(date +%Y%m%d-%H%M%S)"

if ! grep -q "container_name: memos" docker-compose.yml; then
  cat >> docker-compose.yml <<'YML'
  memos:
    container_name: memos
    image: neosmemo/memos:stable
    environment:
      - MEMOS_ADDR=127.0.0.1
      - MEMOS_PORT=5230
    volumes:
      - ./memos:/var/opt/memos
    network_mode: "host"
    restart: unless-stopped
YML
fi

if ! grep -q "$HOST" Caddyfile; then
  cat >> Caddyfile <<CADDY

$HOST {
  reverse_proxy 127.0.0.1:5230
}
CADDY
fi

curl -fsSL "$BASE/k2k-maint.sh" -o k2k-maint.sh && chmod 755 k2k-maint.sh || true

docker compose up -d memos
docker restart caddy >/dev/null
sleep 8
docker compose ps --format '{{.Name}} {{.State}}'
echo
echo "Notes: https://$HOST"
echo "The first account you sign up becomes the admin. Then turn off public sign-up in Settings."
