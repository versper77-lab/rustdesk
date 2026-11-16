#!/bin/bash
# K2K key service installer for the Oracle server.
# - replaces hbbs with the K2K build (only key-activated devices may register,
#   enforced only after you switch it on in the admin page)
# - limits relay bandwidth (hbbr)
# - adds the key service + admin page behind HTTPS (Caddy, sslip.io name)
# Usage: sudo bash install-keys.sh [public-ip]
set -euo pipefail
IP="${1:-217.142.143.66}"
HOST="$(echo "$IP" | tr . -).sslip.io"
BASE="https://github.com/versper77-lab/rustdesk/releases/download/k2k-server"
cd /opt/k2k-server

stamp=$(date +%Y%m%d-%H%M%S)
cp docker-compose.yml "docker-compose.yml.bak-$stamp"
mkdir -p backups bin keys caddy
tar -czf "backups/before-keys-$stamp.tgz" data

curl -fsSL "$BASE/hbbs" -o bin/hbbs.new
chmod +x bin/hbbs.new
mv bin/hbbs.new bin/hbbs
curl -fsSL "$BASE/k2k-keys.py" -o k2k-keys.py
curl -fsSL "$BASE/k2k-maint.sh" -o k2k-maint.sh
chmod 755 k2k-maint.sh
curl -fsSL "$BASE/k2k-host.sh" -o k2k-host.sh
chmod 755 k2k-host.sh
echo '* * * * * root /opt/k2k-server/k2k-host.sh >/dev/null 2>&1' > /etc/cron.d/k2k-host
chmod 644 /etc/cron.d/k2k-host
# security updates install daily by themselves; reboot only when one needs it, at 04:30 KST
printf 'Unattended-Upgrade::Automatic-Reboot "true";\nUnattended-Upgrade::Automatic-Reboot-Time "19:30";\n' \
  > /etc/apt/apt.conf.d/52k2k-auto-reboot

cat > Caddyfile <<CADDY
$HOST {
  reverse_proxy 127.0.0.1:8080
}
CADDY

cat > docker-compose.yml <<'YML'
services:
  hbbs:
    container_name: hbbs
    image: ubuntu:24.04
    working_dir: /root
    command: /k2k/hbbs -k _
    volumes:
      - ./data:/root
      - ./bin:/k2k:ro
    network_mode: "host"
    depends_on:
      - hbbr
    restart: unless-stopped
  hbbr:
    container_name: hbbr
    image: rustdesk/rustdesk-server:latest
    command: hbbr -k _
    environment:
      - TOTAL_BANDWIDTH=40
      - SINGLE_BANDWIDTH=10
    volumes:
      - ./data:/root
    network_mode: "host"
    restart: unless-stopped
  k2k-keys:
    container_name: k2k-keys
    image: python:3.12-alpine
    command: python /app/k2k-keys.py
    volumes:
      - ./keys:/keys
      - ./data:/data
      - ./k2k-keys.py:/app/k2k-keys.py:ro
      # lets the admin page switch hbbs/hbbr on and off
      - /var/run/docker.sock:/var/run/docker.sock
    network_mode: "host"
    restart: unless-stopped
  caddy:
    container_name: caddy
    image: caddy:2
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./caddy:/data
    network_mode: "host"
    restart: unless-stopped
YML

for p in 80 443; do
  if ! iptables -C INPUT -p tcp --dport $p -j ACCEPT 2>/dev/null; then
    POS=$(iptables -L INPUT --line-numbers -n | awk '/REJECT/ {print $1; exit}')
    if [ -n "$POS" ]; then
      iptables -I INPUT "$POS" -p tcp --dport $p -j ACCEPT
    else
      iptables -A INPUT -p tcp --dport $p -j ACCEPT
    fi
  fi
done
netfilter-persistent save >/dev/null 2>&1 || true

docker compose up -d --remove-orphans
docker restart k2k-keys >/dev/null  # pick up a new k2k-keys.py even when the compose file is unchanged
/opt/k2k-server/k2k-host.sh || true
sleep 8
docker compose ps --format '{{.Name}} {{.State}}'
echo
echo "Admin page : https://$HOST/admin"
PW=$(docker logs k2k-keys 2>&1 | grep -o 'K2K admin password: .*' | tail -1 || true)
if [ -n "$PW" ]; then
  echo "$PW   (write it down, then change it in the admin page)"
else
  echo "Admin password was set earlier (unchanged)."
fi
