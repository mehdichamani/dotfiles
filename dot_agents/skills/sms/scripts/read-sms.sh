#!/usr/bin/env bash
# read-sms.sh — print last N inbox SMS in human-readable form.
# Usage: bash scripts/read-sms.sh [limit] [type]
#   limit default 1, type default inbox (all|inbox|sent|draft|outbox|failed|queued)
set -euo pipefail
LIMIT="${1:-1}"
TYPE="${2:-inbox}"
termux-sms-list -l "$LIMIT" -t "$TYPE" | jq -r '.[] | "\(.received) | \(.address) [type=\(.type)]\n\(.body)\n---"'
