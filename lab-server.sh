#!/usr/bin/env bash
# VPN lab — SERVER side.
# Usage: [LAB_CC=cubic] bash lab-server.sh <client_ip>
#
# Installs WireGuard, OpenVPN and sing-box (Hysteria2 + VLESS Reality) next to a small test website.
# Everything lives in /opt/colitu-lab and listens on 24xxx ports, so it can share a host with other
# services. The lab ports are only opened to <client_ip> and to the tunnel interfaces.
# LAB_CC sets the TCP congestion control of the test website (e.g. "cubic"); empty = system default.
# Undo everything with: bash lab-teardown.sh server <client_ip>
set -euo pipefail
CLIENT_IP="$1"
HERE=$(cd "$(dirname "$0")" && pwd)
LAB=/opt/colitu-lab
mkdir -p "$LAB"/{www,pki,out}
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq wireguard-tools openvpn openssl python3 curl >/dev/null

if [ ! -x "$LAB/sing-box" ]; then
  V=$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest | python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"].lstrip("v"))')
  curl -fsSL -o /tmp/sb.tgz "https://github.com/SagerNet/sing-box/releases/download/v$V/sing-box-$V-linux-amd64.tar.gz"
  tar -xzf /tmp/sb.tgz -C /tmp
  cp "/tmp/sing-box-$V-linux-amd64/sing-box" "$LAB/sing-box"
  rm -rf /tmp/sb.tgz "/tmp/sing-box-$V-linux-amd64"
fi

# Test files: one big download and one "web page" sized file.
[ -f "$LAB/www/blob" ] || head -c 64M /dev/urandom > "$LAB/www/blob"
[ -f "$LAB/www/page" ] || head -c 100K /dev/urandom > "$LAB/www/page"

cd "$LAB/pki"
if [ ! -f lab.env ]; then
  wg genkey > wg-server.key; wg pubkey < wg-server.key > wg-server.pub
  wg genkey > wg-client.key; wg pubkey < wg-client.key > wg-client.pub
  "$LAB/sing-box" generate reality-keypair > reality.txt
  REALITY_PRIV=$(awk '/PrivateKey/{print $2}' reality.txt)
  REALITY_PUB=$(awk '/PublicKey/{print $2}' reality.txt)
  cat > lab.env <<EOF
SERVER_IP=$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -1)
HY2_PW=$(openssl rand -hex 16)
VLESS_UUID=$("$LAB/sing-box" generate uuid)
REALITY_PRIV=$REALITY_PRIV
REALITY_PUB=$REALITY_PUB
REALITY_SID=$(openssl rand -hex 8)
WG_SERVER_PUB=$(cat wg-server.pub)
WG_CLIENT_KEY=$(cat wg-client.key)
EOF

  # Self-signed certificate for Hysteria2 (the client connects with insecure=true).
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 \
    -keyout hy2.key -out hy2.crt -subj /CN=lab.colitu 2>/dev/null

  # OpenVPN PKI (EC keys, valid for 30 days).
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 \
    -keyout ca.key -out ca.crt -subj /CN=colitu-lab-ca 2>/dev/null
  for who in server client; do
    eku=$([ "$who" = server ] && echo serverAuth || echo clientAuth)
    openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
      -keyout "ovpn-$who.key" -out "ovpn-$who.csr" -subj "/CN=$who" 2>/dev/null
    printf "basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyAgreement\nextendedKeyUsage=%s\n" "$eku" > "ext-$who.cnf"
    openssl x509 -req -in "ovpn-$who.csr" -CA ca.crt -CAkey ca.key -CAcreateserial -days 30 \
      -out "ovpn-$who.crt" -extfile "ext-$who.cnf" 2>/dev/null
  done
fi
# shellcheck disable=SC1091
. ./lab.env

cat > /etc/wireguard/wglab.conf <<EOF
[Interface]
Address = 10.77.0.1/24
ListenPort = 24820
PrivateKey = $(cat wg-server.key)

[Peer]
PublicKey = $(cat wg-client.pub)
AllowedIPs = 10.77.0.2/32
EOF
chmod 600 /etc/wireguard/wglab.conf

cat > "$LAB/ovpn-server.conf" <<EOF
port 24194
proto udp
dev tunlab
dev-type tun
topology subnet
server 10.78.0.0 255.255.255.0
ca $LAB/pki/ca.crt
cert $LAB/pki/ovpn-server.crt
key $LAB/pki/ovpn-server.key
dh none
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
keepalive 10 60
persist-key
persist-tun
verb 3
EOF

cat > "$LAB/sb-server.json" <<EOF
{
  "log": { "level": "warn" },
  "inbounds": [
    {
      "type": "hysteria2", "tag": "hy2", "listen": "0.0.0.0", "listen_port": 24443,
      "users": [{ "password": "$HY2_PW" }],
      "tls": { "enabled": true, "alpn": ["h3"], "certificate_path": "$LAB/pki/hy2.crt", "key_path": "$LAB/pki/hy2.key" }
    },
    {
      "type": "vless", "tag": "vless", "listen": "0.0.0.0", "listen_port": 24444,
      "users": [{ "uuid": "$VLESS_UUID", "flow": "xtls-rprx-vision" }],
      "tls": {
        "enabled": true, "server_name": "www.microsoft.com",
        "reality": {
          "enabled": true,
          "handshake": { "server": "www.microsoft.com", "server_port": 443 },
          "private_key": "$REALITY_PRIV", "short_id": ["$REALITY_SID"]
        }
      }
    }
  ],
  "outbounds": [{ "type": "direct" }]
}
EOF
"$LAB/sing-box" check -c "$LAB/sb-server.json"

unit() { # name, command
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
unit sb "$LAB/sing-box run -c $LAB/sb-server.json"
unit ovpn "/usr/sbin/openvpn --config $LAB/ovpn-server.conf"
cp "$HERE/lab-www.py" "$LAB/lab-www.py"
unit http "/usr/bin/python3 $LAB/lab-www.py"
mkdir -p /etc/systemd/system/colitu-lab-http.service.d
printf '[Service]\nEnvironment=LAB_CC=%s\n' "${LAB_CC:-}" > /etc/systemd/system/colitu-lab-http.service.d/cc.conf
systemctl daemon-reload
systemctl enable --now colitu-lab-sb colitu-lab-http colitu-lab-ovpn wg-quick@wglab >/dev/null 2>&1
systemctl restart colitu-lab-sb colitu-lab-http colitu-lab-ovpn wg-quick@wglab

# Firewall: lab ports are reachable only from the client and through the tunnels.
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow from "$CLIENT_IP" to any port 24443 proto udp comment colitu-lab >/dev/null
  ufw allow from "$CLIENT_IP" to any port 24444 proto tcp comment colitu-lab >/dev/null
  ufw allow from "$CLIENT_IP" to any port 24820 proto udp comment colitu-lab >/dev/null
  ufw allow from "$CLIENT_IP" to any port 24194 proto udp comment colitu-lab >/dev/null
  ufw allow from "$CLIENT_IP" to any port 24080 proto tcp comment colitu-lab >/dev/null
  ufw allow in on wglab to any port 24080 proto tcp comment colitu-lab >/dev/null
  ufw allow in on tunlab to any port 24080 proto tcp comment colitu-lab >/dev/null
fi

# Client bundle: lab.env + OpenVPN client certificate. Copy it next to lab-client.sh on the client.
tar -czf "$LAB/out/client-bundle.tgz" -C "$LAB/pki" lab.env ca.crt ovpn-client.crt ovpn-client.key
systemctl --no-pager --plain is-active colitu-lab-sb colitu-lab-http colitu-lab-ovpn wg-quick@wglab
echo "server ready — client bundle: $LAB/out/client-bundle.tgz"
