#!/usr/bin/env bash
# VPN lab — CLIENT side.
# Usage: bash lab-client.sh   (client-bundle.tgz from the server must be in the same folder)
#
# Does not touch the default route: WireGuard and OpenVPN only route the lab subnets
# (10.77.0.0/24, 10.78.0.0/24) and sing-box only exposes local SOCKS ports.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
LAB=/opt/colitu-lab
mkdir -p "$LAB/pki" "$LAB/results"
tar -xzf "$HERE/client-bundle.tgz" -C "$LAB/pki"
# shellcheck disable=SC1091
. "$LAB/pki/lab.env"
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq wireguard-tools openvpn curl python3 iproute2 >/dev/null

if [ ! -x "$LAB/sing-box" ]; then
  V=$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest | python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"].lstrip("v"))')
  curl -fsSL -o /tmp/sb.tgz "https://github.com/SagerNet/sing-box/releases/download/v$V/sing-box-$V-linux-amd64.tar.gz"
  tar -xzf /tmp/sb.tgz -C /tmp
  cp "/tmp/sing-box-$V-linux-amd64/sing-box" "$LAB/sing-box"
  rm -rf /tmp/sb.tgz "/tmp/sing-box-$V-linux-amd64"
fi

cat > /etc/wireguard/wglab.conf <<EOF
[Interface]
Address = 10.77.0.2/24
PrivateKey = $WG_CLIENT_KEY

[Peer]
PublicKey = $WG_SERVER_PUB
Endpoint = $SERVER_IP:24820
AllowedIPs = 10.77.0.1/32
PersistentKeepalive = 25
EOF
chmod 600 /etc/wireguard/wglab.conf

cat > "$LAB/ovpn-client.conf" <<EOF
client
dev tunlab
dev-type tun
proto udp
remote $SERVER_IP 24194
nobind
route-nopull
remote-cert-tls server
ca $LAB/pki/ca.crt
cert $LAB/pki/ovpn-client.crt
key $LAB/pki/ovpn-client.key
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
persist-key
persist-tun
verb 3
EOF

cat > "$LAB/sb-client.json" <<EOF
{
  "log": { "level": "warn" },
  "inbounds": [
    { "type": "mixed", "tag": "in-hy2", "listen": "127.0.0.1", "listen_port": 24101 },
    { "type": "mixed", "tag": "in-vless", "listen": "127.0.0.1", "listen_port": 24102 }
  ],
  "outbounds": [
    {
      "type": "hysteria2", "tag": "hy2", "server": "$SERVER_IP", "server_port": 24443, "password": "$HY2_PW",
      "tls": { "enabled": true, "server_name": "lab.colitu", "insecure": true, "alpn": ["h3"] }
    },
    {
      "type": "vless", "tag": "vless", "server": "$SERVER_IP", "server_port": 24444,
      "uuid": "$VLESS_UUID", "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true, "server_name": "www.microsoft.com",
        "utls": { "enabled": true, "fingerprint": "chrome" },
        "reality": { "enabled": true, "public_key": "$REALITY_PUB", "short_id": "$REALITY_SID" }
      }
    },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rules": [
      { "inbound": ["in-hy2"], "outbound": "hy2" },
      { "inbound": ["in-vless"], "outbound": "vless" }
    ],
    "final": "direct"
  }
}
EOF
"$LAB/sing-box" check -c "$LAB/sb-client.json"

unit() {
  cat > "/etc/systemd/system/colitu-lab-$1.service" <<EOF
[Unit]
Description=Colitu VPN lab ($1)
After=network-online.target

[Service]
ExecStart=$2
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
}
unit sb "$LAB/sing-box run -c $LAB/sb-client.json"
unit ovpn "/usr/sbin/openvpn --config $LAB/ovpn-client.conf"
systemctl daemon-reload
systemctl enable --now colitu-lab-sb colitu-lab-ovpn wg-quick@wglab >/dev/null 2>&1
systemctl restart colitu-lab-sb colitu-lab-ovpn wg-quick@wglab
sleep 6

cp "$HERE/lab-netem.sh" "$HERE/lab-run.sh" "$LAB/"
echo "--- connectivity check (100 KB page)"
for t in "direct||http://$SERVER_IP:24080" "wireguard||http://10.77.0.1:24080" "openvpn||http://10.78.0.1:24080" \
         "hysteria2|socks5h://127.0.0.1:24101|http://127.0.0.1:24080" "vless-reality|socks5h://127.0.0.1:24102|http://127.0.0.1:24080"; do
  IFS='|' read -r name proxy base <<<"$t"
  args=(); [ -n "$proxy" ] && args=(--proxy "$proxy")
  printf '%-14s ' "$name"; curl -s -o /dev/null --max-time 10 "${args[@]}" -w '%{http_code} %{time_total}s\n' "$base/page" || echo FAIL
done
