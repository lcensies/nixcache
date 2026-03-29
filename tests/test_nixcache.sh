#!/usr/bin/env bash
# Tests for nixcache.ru - frontend and nix proxy functionality
set -euo pipefail

HOST="${1:-nixcache.ru}"
PASS=0
FAIL=0

ok()   { echo "  PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }

# Determine base URL: follow redirect, prefer HTTPS if available
if curl -s -o /dev/null -w "%{http_code}" "https://$HOST/" 2>/dev/null | grep -q "^[23]"; then
  BASE="https://$HOST"
else
  BASE="http://$HOST"
fi

echo "=== Testing $HOST (base: $BASE) ==="

# 1. HTTP redirects to HTTPS when TLS is configured
echo
echo "--- Frontend ---"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$HOST/")
if [[ "$HTTP_STATUS" == "301" || "$HTTP_STATUS" == "302" || "$HTTP_STATUS" == "200" ]]; then
  ok "GET http://$HOST/ returns $HTTP_STATUS"
else
  fail "GET http://$HOST/ returned $HTTP_STATUS (expected 200 or 3xx redirect)"
fi

STATUS=$(curl -sL -o /dev/null -w "%{http_code}" "$BASE/")
if [[ "$STATUS" == "200" ]]; then
  ok "GET $BASE/ returns 200"
else
  fail "GET $BASE/ returned $STATUS (expected 200)"
fi

BODY=$(curl -sL "$BASE/")
if echo "$BODY" | grep -q "nixcache"; then
  ok "Frontend HTML contains 'nixcache'"
else
  fail "Frontend HTML missing 'nixcache'"
fi

# 2. Nix cache info endpoint
echo
echo "--- Nix cache API ---"
STATUS=$(curl -sL -o /dev/null -w "%{http_code}" "$BASE/nix-cache-info")
if [[ "$STATUS" == "200" ]]; then
  ok "GET /nix-cache-info returns 200"
else
  fail "GET /nix-cache-info returned $STATUS (expected 200)"
fi

BODY=$(curl -sL "$BASE/nix-cache-info")
if echo "$BODY" | grep -q "StoreDir"; then
  ok "nix-cache-info contains StoreDir"
else
  fail "nix-cache-info missing StoreDir: got: $BODY"
fi

# 3. Proxy forwards nix NAR requests
echo
echo "--- Proxy NAR fetch ---"
NARINFO_HASH="0i0jksba9y7p35hi6v9yjm6q01y5a2xn"
STATUS=$(curl -sL -o /dev/null -w "%{http_code}" "$BASE/${NARINFO_HASH}.narinfo")
if [[ "$STATUS" == "200" || "$STATUS" == "404" ]]; then
  ok "GET /${NARINFO_HASH}.narinfo proxied (status: $STATUS)"
else
  fail "GET /${NARINFO_HASH}.narinfo returned $STATUS (expected 200 or 404)"
fi

CACHE_HEADER=$(curl -sL -I "$BASE/${NARINFO_HASH}.narinfo" | grep -i "X-Cache-Status" || true)
if [[ -n "$CACHE_HEADER" ]]; then
  ok "X-Cache-Status header present: $(echo "$CACHE_HEADER" | tr -d '\r')"
else
  fail "X-Cache-Status header missing"
fi

# 4. Cache hit test — known-existing narinfo fetched twice, second must be HIT
echo
echo "--- Cache hit test ---"
CACHE_HASH="sbldylj3clbkc0aqvjjzfa6slp4zdvlj"
# First request primes the cache
curl -s -o /dev/null "$BASE/${CACHE_HASH}.narinfo"
# Second request must be a cache HIT served by our proxy
CACHE_STATUS=$(curl -sI "$BASE/${CACHE_HASH}.narinfo" | grep -i "^x-cache-status:" | tr -d '\r' | awk '{print $2}')
if [[ "$CACHE_STATUS" == "HIT" ]]; then
  ok "Second request served from cache (X-Cache-Status: HIT)"
else
  fail "Expected cache HIT on second request, got: '${CACHE_STATUS}'"
fi

# 5. Nix substituter test
echo
echo "--- Nix substituter (non-privileged) ---"
if ! command -v nix &>/dev/null; then
  echo "  SKIP: nix not found in PATH"
else
  NIX_OUT=$(nix store ping --store "$BASE" 2>&1 || true)
  if echo "$NIX_OUT" | grep -qi "trustless\|trusted\|Store URL\|version"; then
    ok "nix store ping succeeded against $BASE"
  else
    fail "nix store ping failed: $NIX_OUT"
  fi

  # Fetch a well-known narinfo without requiring root/daemon
  NARINFO_OUT=$(curl -sL "$BASE/0i0jksba9y7p35hi6v9yjm6q01y5a2xn.narinfo")
  if echo "$NARINFO_OUT" | grep -q "StorePath"; then
    ok "narinfo fetch returned valid NAR metadata"
  else
    echo "  INFO: narinfo response: $(echo "$NARINFO_OUT" | head -3)"
  fi
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
