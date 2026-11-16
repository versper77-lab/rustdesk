#!/bin/bash
# K2K host status for the admin page (installed to /opt/k2k-server/k2k-host.sh,
# run by /etc/cron.d/k2k-host every minute as root).
# - writes data/k2k_host.json: pending updates, reboot needed, uptime
# - reboots when the admin page asked for it (data/k2k_reboot_request)
set -u
cd /opt/k2k-server || exit 1
out=data/k2k_host.json

if [ -f data/k2k_reboot_request ]; then
  rm -f data/k2k_reboot_request
  echo "$(date -Is) reboot requested from admin page" >> status.log
  systemctl reboot
  exit 0
fi

# apt-check is slow-ish; refresh the update counts at most every 30 minutes
if [ ! -f "$out" ] || [ -n "$(find "$out" -mmin +30 2>/dev/null)" ] || [ -f /var/run/reboot-required -a "$out" -ot /var/run/reboot-required ]; then
  counts=$(/usr/lib/update-notifier/apt-check 2>&1 | tail -n 1)
  updates=${counts%%;*}
  security=${counts##*;}
  case "$updates$security" in *[!0-9]*|'') updates=-1; security=-1 ;; esac
  reboot=false
  [ -f /var/run/reboot-required ] && reboot=true
  pkgs=$(cat /var/run/reboot-required.pkgs 2>/dev/null | sort -u | head -n 10 | tr -cd 'A-Za-z0-9.+_\n-' | tr '\n' ' ')
  auto=false
  grep -qs 'Automatic-Reboot "true"' /etc/apt/apt.conf.d/52k2k-auto-reboot && auto=true
  unattended=$(systemctl is-enabled unattended-upgrades 2>/dev/null | head -n 1 | tr -cd 'a-z-')
  [ -n "$unattended" ] || unattended=unknown
  last=$(stat -c %Y /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null || echo 0)
  boot=$(( $(date +%s) - $(cut -d. -f1 /proc/uptime) ))
  printf '{"updates":%s,"security":%s,"reboot_required":%s,"reboot_pkgs":"%s","auto_reboot":%s,"unattended":"%s","last_upgrade":%s,"boot":%s,"checked":%s}\n' \
    "$updates" "$security" "$reboot" "$pkgs" "$auto" "$unattended" "$last" "$boot" "$(date +%s)" > "$out.tmp" && mv "$out.tmp" "$out"
fi
