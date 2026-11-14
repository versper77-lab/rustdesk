#!/bin/bash
# K2K server daily maintenance (installed to /opt/k2k-server/k2k-maint.sh, run by cron)
# - restarts hbbs/hbbr if they are not running
# - keeps 14 daily backups of server keys, the ID database and K2K keys in /opt/k2k-server/backups
# - writes a one-line status to /opt/k2k-server/status.log
set -u
cd /opt/k2k-server || exit 1

for c in hbbs hbbr k2k-keys caddy memos; do
  grep -q "container_name: $c" docker-compose.yml || continue
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" != "true" ]; then
    docker compose up -d >/dev/null 2>&1
    echo "$(date -Is) restarted $c" >> status.log
  fi
done

mkdir -p backups
tar -czf "backups/k2k-data-$(date +%F).tgz" data keys memos 2>/dev/null
ls -1t backups/k2k-data-*.tgz | tail -n +15 | xargs -r rm -f

peers=$(test -f data/db_v2.sqlite3 && echo ok)
disk=$(df -h / | awk 'NR==2 {print $5}')
mem=$(free -m | awk '/Mem:/ {print $3"/"$2"MB"}')
echo "$(date -Is) ok hbbs=$(docker inspect -f '{{.State.Status}}' hbbs) hbbr=$(docker inspect -f '{{.State.Status}}' hbbr) db=${peers:-?} disk=$disk mem=$mem" >> status.log
tail -n 500 status.log > status.tmp && mv status.tmp status.log
