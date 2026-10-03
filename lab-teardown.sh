#!/usr/bin/env bash
# Removes the lab completely (services, configs, firewall rules, /opt/colitu-lab).
# Copy /opt/colitu-lab/results off the client first if you want to keep them.
#   bash lab-teardown.sh server <client_ip>
#   bash lab-teardown.sh client
set -uo pipefail
ROLE=${1:?server|client}
LAB=/opt/colitu-lab

[ "$ROLE" = client ] && [ -f "$LAB/lab-netem.sh" ] && bash "$LAB/lab-netem.sh" clear
for u in colitu-lab-sb colitu-lab-http colitu-lab-ovpn wg-quick@wglab; do
  systemctl disable --now "$u" 2>/dev/null || true
done
rm -rf /etc/systemd/system/colitu-lab-*.service /etc/systemd/system/colitu-lab-*.service.d /etc/wireguard/wglab.conf
systemctl daemon-reload

if [ "$ROLE" = server ] && command -v ufw >/dev/null; then
  CLIENT_IP=${2:?client ip}
  for spec in "24443 proto udp" "24444 proto tcp" "24820 proto udp" "24194 proto udp" "24080 proto tcp"; do
    # shellcheck disable=SC2086
    ufw delete allow from "$CLIENT_IP" to any port $spec >/dev/null 2>&1 || true
  done
  ufw delete allow in on wglab to any port 24080 proto tcp >/dev/null 2>&1 || true
  ufw delete allow in on tunlab to any port 24080 proto tcp >/dev/null 2>&1 || true
fi

rm -rf "$LAB"
echo "teardown $ROLE done (packages kept; remove with: apt purge wireguard-tools openvpn)"
