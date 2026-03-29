#!/usr/bin/env bash
# Compare download speed: cache.nixos.org vs nixcache.ru (MISS and HIT)
set -euo pipefail

PROXY="${1:-https://nixcache.ru}"
DIRECT="https://cache.nixos.org"

# Known narinfo with a reasonably sized NAR (~50KB compressed)
NARINFO_HASH="sbldylj3clbkc0aqvjjzfa6slp4zdvlj"

echo "Resolving NAR path from $PROXY..."
NARINFO=$(curl -sL "$PROXY/$NARINFO_HASH.narinfo")
NAR_PATH=$(echo "$NARINFO" | grep "^URL:" | awk '{print $2}')
NAR_SIZE=$(echo "$NARINFO" | grep "^FileSize:" | awk '{print $2}')

if [[ -z "$NAR_PATH" ]]; then
  echo "ERROR: could not resolve narinfo from $PROXY"
  exit 1
fi

echo "NAR: $NAR_PATH ($(( ${NAR_SIZE:-0} / 1024 )) KB compressed)"
echo

speed() {
  local url="$1"
  curl -sL -o /dev/null -w "%{speed_download}" "$url"
}

fmt() {
  awk "BEGIN { printf \"%.0f KB/s\", $1/1024 }"
}

run() {
  local label="$1" url="$2"
  local bytes_per_sec elapsed http_code
  read -r bytes_per_sec elapsed http_code < <(
    curl -sL -o /dev/null -w "%{speed_download} %{time_total} %{http_code}" "$url"
  ) || true
  local kb_per_sec
  kb_per_sec=$(awk "BEGIN { printf \"%.1f\", $bytes_per_sec/1024 }")
  printf "  %-40s  %6s KB/s  %.2fs  HTTP %s\n" "$label" "$kb_per_sec" "$elapsed" "$http_code"
}

echo "=== NAR download speed ==="
echo
run "cache.nixos.org (direct)"         "$DIRECT/$NAR_PATH"
run "$PROXY (1st request — MISS)"      "$PROXY/$NAR_PATH"
run "$PROXY (2nd request — HIT)"       "$PROXY/$NAR_PATH"
run "$PROXY (3rd request — HIT warm)"  "$PROXY/$NAR_PATH"

echo
echo "=== narinfo lookup speed (x5 avg) ==="
echo
total=0
for i in 1 2 3 4 5; do
  t=$(curl -sL -o /dev/null -w "%{time_total}" "$PROXY/$NARINFO_HASH.narinfo")
  total=$(awk "BEGIN { print $total + $t }")
done
avg=$(awk "BEGIN { printf \"%.3f\", $total/5 }")
printf "  %-40s  avg %.3fs\n" "$PROXY narinfo latency" "$avg"

total=0
for i in 1 2 3 4 5; do
  t=$(curl -sL -o /dev/null -w "%{time_total}" "$DIRECT/$NARINFO_HASH.narinfo")
  total=$(awk "BEGIN { print $total + $t }")
done
avg=$(awk "BEGIN { printf \"%.3f\", $total/5 }")
printf "  %-40s  avg %.3fs\n" "$DIRECT narinfo latency" "$avg"

echo
echo "=== Disk speed on proxy server (if accessible via SSH) ==="
HOST="${PROXY#https://}"
HOST="${HOST#http://}"
if ssh -o ConnectTimeout=3 -o BatchMode=yes "$HOST" true 2>/dev/null; then
  ssh "$HOST" "dd if=/dev/zero of=/var/cache/nix/.speedtest bs=1M count=64 oflag=dsync 2>&1 | tail -1 && rm -f /var/cache/nix/.speedtest"
else
  echo "  (skipped — no SSH access to $HOST)"
fi
