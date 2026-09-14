# CLI Reference

## termux-sms-list

Lists SMS messages (default) or conversations (`--conversation-list`).

| Flag | Meaning | Default |
| ---- | ------- | ------- |
| `-l <n>` / `--message-limit=<n>` | Max messages returned | `10` |
| `-o <n>` / `--message-offset=<n>` | SQL offset | `0` |
| `-t <type>` / `--message-type=<type>` | `all\|inbox\|sent\|draft\|outbox\|failed\|queued` | `inbox` |
| `-f <addr>` / `--message-address=<addr>` | Filter by sender address | — |
| `--message-selection="<sql>"` | Raw SQL WHERE (overrides `-f`, `-t`) | — |
| `--message-sort-order="<order>"` | SQL ORDER BY | `date DESC` |
| `--message-return-no-order-reverse` | Keep SQL order (default reverses so latest is last) | off |
| `-c` / `--conversation-list` | Conversation list mode | off |
| `--conversation-limit=<n>` / `--conversation-offset=<n>` | Paging for conversations | — |
| `--conversation-selection="<sql>"` | Filter conversations, e.g. `"address == '666'"`, `"thread_id == 6"` | — |
| `--conversation-sort-order="<order>"` | Conversation ORDER BY | `date DESC` |
| `--conversation-return-multiple-messages` | N messages per conversation (else 1) | off |
| `--conversation-return-nested-view` | Nested `{thread_id: [msgs]}` view | off |
| `--conversation-return-no-order-reverse` | Keep conversation sort order | off |

Message types: `1=inbox, 2=sent, 3=draft, 4=outbox, 5=failed, 6=queued`.
Fields per message: `_id, thread_id/threadid, address/number, received/date, body, type, read`.

Examples: see `SKILL.md` sections 1–3.

## termux-sms-send

```
termux-sms-send -n number[,number2,...] [-s slot] [text]
```

Text from args or stdin. `-s` selects SIM slot (invalid slot fails silently).

Android docs: https://developer.android.com/reference/android/provider/Telephony
