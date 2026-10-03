#!/usr/bin/env bash
# Measurement loop (runs on the client). For every loss level × run × target:
#   - one 64 MB download (capped at 20 s)            → average Mbit/s
#   - twenty 100 KB "page" requests (10 s timeout each) → load times + failures
# Targets are shuffled every run so slow drifts over time don't punish one protocol.
# Output: /opt/colitu-lab/results/<tag>.jsonl
#   bash lab-run.sh <tag> [losses="0 1 5 10"] [runs=3]
set -uo pipefail
LAB=/opt/colitu-lab
# shellcheck disable=SC1091
. "$LAB/pki/lab.env"
TAG=${1:?tag required}
LOSSES=${2:-"0 1 5 10"}
RUNS=${3:-3}
OUT="$LAB/results/$TAG.jsonl"
: > "$OUT"

TARGETS=(
  "direct||http://$SERVER_IP:24080"
  "wireguard||http://10.77.0.1:24080"
  "openvpn||http://10.78.0.1:24080"
  "hysteria2|socks5h://127.0.0.1:24101|http://127.0.0.1:24080"
  "vless-reality|socks5h://127.0.0.1:24102|http://127.0.0.1:24080"
)

trap 'bash $LAB/lab-netem.sh clear >/dev/null' EXIT

for loss in $LOSSES; do
  bash "$LAB/lab-netem.sh" set "$loss"
  sleep 3
  for run in $(seq 1 "$RUNS"); do
    mapfile -t order < <(printf '%s\n' "${TARGETS[@]}" | shuf)
    for t in "${order[@]}"; do
      IFS='|' read -r name proxy base <<<"$t"
      args=(); [ -n "$proxy" ] && args=(--proxy "$proxy")
      dl=$(curl -s -o /dev/null --max-time 20 "${args[@]}" -w '%{size_download} %{time_total}' "$base/blob"; echo " $?")
      read -r bytes secs dl_exit <<<"$dl"
      times=(); fails=0
      for _ in $(seq 1 20); do
        r=$(curl -s -o /dev/null --max-time 10 "${args[@]}" -w '%{time_total}' "$base/page"; echo " $?")
        read -r tt ex <<<"$r"
        if [ "$ex" = 0 ]; then times+=("$tt"); else fails=$((fails + 1)); fi
      done
      ptimes=$(IFS=,; echo "${times[*]:-}")
      mbps=$(python3 -c "b=$bytes;s=$secs;print(round(b*8/s/1e6,2) if s>0 else 0)")
      printf '{"loss":%s,"run":%s,"target":"%s","mbps":%s,"dl_bytes":%s,"dl_secs":%s,"dl_exit":%s,"page_secs":[%s],"page_fail":%s,"ts":"%s"}\n' \
        "$loss" "$run" "$name" "$mbps" "$bytes" "$secs" "$dl_exit" "$ptimes" "$fails" "$(date -Is)" >> "$OUT"
      printf 'loss=%-3s run=%s %-14s %7s Mbit/s  page ok=%-2s fail=%s\n' "$loss" "$run" "$name" "$mbps" "${#times[@]}" "$fails"
    done
  done
done
echo "done -> $OUT"
