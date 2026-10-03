#!/usr/bin/env bash
# Bad-network simulator. Shapes ONLY the traffic to and from the lab server, in both directions.
#   bash lab-netem.sh set <loss_%> [one_way_delay_ms=20] [rate_mbit=100]
#   bash lab-netem.sh clear
set -euo pipefail
# shellcheck disable=SC1091
. /opt/colitu-lab/pki/lab.env
DEV=$(ip -4 route get "$SERVER_IP" | grep -oP 'dev \K\S+')
IFB=ifb-lab

clear_all() {
  tc qdisc del dev "$DEV" root 2>/dev/null || true
  tc qdisc del dev "$DEV" ingress 2>/dev/null || true
  ip link del "$IFB" 2>/dev/null || true
}

case "${1:-}" in
  clear) clear_all; echo "netem cleared on $DEV" ;;
  set)
    LOSS=$2; DELAY=${3:-20}; RATE=${4:-100}
    clear_all
    NETEM="delay ${DELAY}ms loss ${LOSS}% rate ${RATE}mbit limit 10000"
    # Outgoing: all other traffic goes to band 1:2, only packets to the lab server hit netem on 1:4.
    tc qdisc add dev "$DEV" root handle 1: prio bands 4 priomap 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
    tc qdisc add dev "$DEV" parent 1:4 handle 40: netem $NETEM
    tc filter add dev "$DEV" parent 1: protocol ip prio 1 u32 match ip dst "$SERVER_IP/32" flowid 1:4
    # Incoming: only packets from the lab server are redirected through an IFB device with netem.
    modprobe ifb numifbs=0
    ip link add "$IFB" type ifb
    ip link set "$IFB" up
    tc qdisc add dev "$IFB" root netem $NETEM
    tc qdisc add dev "$DEV" handle ffff: ingress
    tc filter add dev "$DEV" parent ffff: protocol ip prio 1 u32 match ip src "$SERVER_IP/32" action mirred egress redirect dev "$IFB"
    echo "netem on $DEV <-> lab server: $NETEM (each direction)"
    ;;
  *) echo "usage: $0 set <loss%> [delay_ms] [rate_mbit] | clear" >&2; exit 2 ;;
esac
