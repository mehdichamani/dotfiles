---
name: sms
description: Read, search, and send SMS on Termux Android via termux-api. Use when user says read/check my sms, last sms, find OTP/code/link, list conversations, or send sms/text message.
---

# SMS (Termux)

Manage SMS on this Termux Android device using the `Termux:API` app
(`com.termux.api`) + `termux-api` CLI. Parse all JSON output with `jq`.

## Prerequisites

- CLI tools: `termux-sms-list`, `termux-sms-send`, `jq`.
  If missing: `pkg install -y termux-api`.
- Android permissions on the `Termux:API` app: `READ_SMS` + `READ_CONTACTS`.
  Grant via Settings > Apps > Termux:API > Permissions.
  - Error `{"error":"Please grant ... READ_SMS ... READ_CONTACTS"}` means
    ask user to grant permissions, then retry.
  - Cannot `pm grant` from inside Termux. ADB from PC if needed:
    `adb shell pm grant com.termux.api android.permission.READ_SMS`
    `adb shell pm grant com.termux.api android.permission.READ_CONTACTS`

## 1. Reading SMS

Default sort is `date DESC` reversed — latest message ends up LAST
unless `--message-return-no-order-reverse` is passed.
Single-message queries (`-l 1`) are unaffected.

```bash
# Last 1 inbox message (most common: "last sms")
termux-sms-list -l 1 -t inbox | jq .

# Body only, human readable
termux-sms-list -l 1 -t inbox | jq -r '.[0] | "\(.received) | \(.address)\n\(.body)"'

# Last N inbox (use -l 5 when searching for OTP/code)
termux-sms-list -l 5 -t inbox | jq .

# By type: all | inbox | sent | draft | outbox | failed | queued
termux-sms-list -l 1 -t all | jq .
termux-sms-list -l 1 -t sent | jq .

# Without jq fallback
termux-sms-list -l 1 -t inbox | python3 -m json.tool
```

Output fields: `_id, thread_id/threadid, address/number, received/date,
body, type, read`. Types: `1=inbox, 2=sent, 3=draft, 4=outbox, 5=failed, 6=queued`.

## 2. Searching / filtering

```bash
# By sender address
termux-sms-list -f 666 -l 10 | jq .
termux-sms-list --message-selection="address == '666'" --message-limit=10 | jq .

# Inbox from sender starting with text (SQL LIKE)
termux-sms-list --message-selection="type == 1 and address == '666' and body LIKE 'Bar %'" --message-limit=1 | jq .

# OTP / code extraction (see scripts/find-otp.sh)
termux-sms-list -l 5 -t inbox | jq -r '.[].body'
```

For OTP/code/link requests: fetch `-l 5 -t inbox`, scan `body` fields,
extract with regex, and report code + sender + timestamp. See
[otp.md](docs/otp.md).

## 3. Conversations

```bash
# 1 message per conversation (default)
termux-sms-list --conversation-list | jq .

# 10 messages per conversation
termux-sms-list --conversation-list --conversation-return-multiple-messages | jq .

# Nested view, latest conversation + latest 5 messages
termux-sms-list --conversation-list --conversation-return-multiple-messages \
  --conversation-return-nested-view --conversation-limit=1 --message-limit=5 | jq .

# Filter conversation by address or thread
termux-sms-list --conversation-list --conversation-return-multiple-messages \
  --conversation-return-nested-view --conversation-selection="address == '666'" | jq .
```

## 4. Sending SMS

```bash
# termux-sms-send -n number[,number2,...] [-s slot] [text]
termux-sms-send -n +15551234567 "Hello from Termux"
echo "Hello from Termux" | termux-sms-send -n +15551234567

# Always confirm recipient + body with user before sending.
# Never send without explicit user approval.
```

## 5. Scripts

- `scripts/read-sms.sh` — human-readable last-N inbox printer.
- `scripts/find-otp.sh` — scan last-N inbox for OTP/code/link.
- Run directly; only script output enters context:
  `bash scripts/read-sms.sh 1`
  `bash scripts/find-otp.sh 5`

## 6. Extra docs

- [troubleshooting.md](docs/troubleshooting.md) — permission errors,
  missing CLI, empty results.
- [reference.md](docs/reference.md) — full flag tables for
  `termux-sms-list` / `termux-sms-send`.

## Rules

- Non-interactive shell only. Never use pagers.
- Always use absolute paths when reading bundled files.
- Trigger phrases: "read my last sms", "check my sms", "read my sms for
  [code/OTP/link/...]" → run `termux-sms-list -l 1 -t inbox`
  (or `-l 5` when searching) and parse with `jq`.
- Sending is sensitive: confirm first, report delivery result after.
