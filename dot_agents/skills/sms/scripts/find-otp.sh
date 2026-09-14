#!/usr/bin/env bash
# find-otp.sh — scan last N inbox SMS for OTPs/codes/links.
# Usage: bash scripts/find-otp.sh [limit] [sender-address]
#   limit default 5. Optional sender filters via -f.
set -euo pipefail
LIMIT="${1:-5}"
SENDER="${2:-}"
if [ -n "$SENDER" ]; then
  JSON=$(termux-sms-list -f "$SENDER" -l "$LIMIT")
else
  JSON=$(termux-sms-list -l "$LIMIT" -t inbox)
fi
echo "$JSON" | jq -r '.[] | "\(.received) | \(.address)\n\(.body)\n---"'
echo "=== EXTRACTED CANDIDATES ==="
echo "$JSON" | jq -r '.[].body' | grep -Eo -e '\b[0-9][0-9 \t-]{3,9}[0-9]\b' -e 'https?://[^[:space:]]+' | sort -u || echo "(no code/link pattern found)"
