# Troubleshooting

## `{"error":"Please grant ... READ_SMS ... READ_CONTACTS"}`

`Termux:API` app lacks permissions.
1. Ask user to open Settings > Apps > Termux:API > Permissions and Allow SMS + Contacts.
2. Retry `termux-sms-list -l 1 -t inbox | jq .`.

## `termux-sms-list: command not found`

CLI package missing: `pkg install -y termux-api`.

## Empty array `[]`

No messages of that type exist, or offset/limit skipped them.
Try `-t all -l 10` to confirm any messages exist.

## SMS send silently fails

- Check recipient format (`-n +15551234567`).
- Dual-SIM: try `-s 0` vs `-s 1`. Invalid slot fails silently and may need
  `READ_PHONE_STATE` (grant via ADB: `adb shell pm grant com.termux.api android.permission.READ_PHONE_STATE`).
- Carrier may block API-sent SMS.

## Cannot `pm grant` from inside Termux

Expected — fails with `GRANT_RUNTIME_PERMISSIONS`. Use ADB from a PC:
`adb shell pm grant com.termux.api android.permission.READ_SMS`
`adb shell pm grant com.termux.api android.permission.READ_CONTACTS`

## `jq` missing

`pkg install -y jq`, or fallback: `termux-sms-list -l 1 -t inbox | python3 -m json.tool`.
