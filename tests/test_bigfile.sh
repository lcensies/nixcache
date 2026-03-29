#!/usr/bin/env bash
# Test download speed with a large NAR file (5-10 MB) to compare locations.
# Usage: ./tests/test_bigfile.sh [proxy_url]
set -euo pipefail

PROXY="${1:-https://nixcache.ru}"
DIRECT="https://cache.nixos.org"
MIN_SIZE=$(( 2 * 1024 * 1024 ))
MAX_SIZE=$(( 5 * 1024 * 1024 ))

echo "Scanning /nix/store for a 2–5 MB NAR to use as benchmark..."

RESULT=""
# Shuffle store paths so we don't always try the same ones
while IFS= read -r entry; do
  hash="${entry:0:32}"
  # Skip .drv files
  [[ "$entry" == *.drv ]] && continue
  info=$(curl -sf --max-time 3 "$DIRECT/$hash.narinfo" 2>/dev/null) || continue
  path=$(echo "$info" | grep "^URL:" | awk '{print $2}')
  size=$(echo "$info" | grep "^FileSize:" | awk '{print $2}')
  [[ -z "$path" || -z "$size" ]] && continue
  if (( size >= MIN_SIZE && size <= MAX_SIZE )); then
    RESULT="$hash $path $size"
    break
  fi
done < <(ls /nix/store | shuf)

if [[ -z "$RESULT" ]]; then
  echo "ERROR: could not find a large NAR in /nix/store that exists on $DIRECT" >&2
  exit 1
fi

read -r HASH NAR_PATH NAR_SIZE <<< "$RESULT"

echo
echo "NAR : $NAR_PATH"
echo "Size: $(( NAR_SIZE / 1024 / 1024 )) MB compressed  (hash: $HASH)"
echo

run() {
  local label="$1" url="$2"
  local bps elapsed http_code
  read -r bps elapsed http_code < <(
    curl -sL -o /dev/null -w "%{speed_download} %{time_total} %{http_code}" "$url"
  ) || true
  local mbps
  mbps=$(awk "BEGIN { printf \"%.2f\", $bps/1024/1024 }")
  printf "  %-45s  %5s MB/s  %.2fs  HTTP %s\n" "$label" "$mbps" "$elapsed" "$http_code"
}

echo "=== Large NAR download speed ==="
echo
# run "cache.nixos.org  (direct)"            "$DIRECT/$NAR_PATH"
run "$PROXY  (1st request — MISS/fetch)"   "$PROXY/$NAR_PATH"
run "$PROXY  (2nd request — HIT cached)"   "$PROXY/$NAR_PATH"
run "$PROXY  (3rd request — HIT warm)"     "$PROXY/$NAR_PATH"

echo
echo "Done."
