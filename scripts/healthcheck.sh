#!/usr/bin/env bash
set -euo pipefail

URL="${1:-http://localhost:8080}"
status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL" || true)

if [ "$status" = "200" ]; then
  echo "OK: $URL returned HTTP 200"
  exit 0
else
  echo "FAIL: $URL returned HTTP ${status:-none} (expected 200)" >&2
  exit 1
fi
