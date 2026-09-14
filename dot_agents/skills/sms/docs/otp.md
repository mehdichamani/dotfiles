# OTP / Code / Link Extraction

Use when user asks for a verification code, OTP, 2FA code, or link from SMS.

## Process

1. Fetch last 5 inbox messages (codes often arrive seconds before the ask,
   but an older message may hold the valid one):
   ```bash
   termux-sms-list -l 5 -t inbox | jq .
   ```
2. Scan each `body` for patterns:
   - 4–8 digit codes: `\b\d{4,8}\b` (optionally with separators: `12-34-56`, `123 456`)
   - Labeled codes: `(code|OTP|PIN|passcode|verification)[^\d]{0,20}(\d{4,8})`
   - URLs: `https?://\S+`
3. Or run the bundled script:
   ```bash
   bash scripts/find-otp.sh 5
   bash scripts/find-otp.sh 10 "666"
   ```
4. Report: the code/link itself (copy-pasteable, in bold/code ticks),
   sender (`address`), timestamp (`received`), and the full body for context.
5. If no code found in 5, widen to `-l 10` or filter by sender with `-f <address>`.

## Notes

- Multiple codes may appear — prefer the latest message unless user names a sender.
- Do not guess digits; quote exactly as in `body`.
- Some senders split codes with spaces/dashes — normalize when reporting
  (e.g. `123 456` → `123456`) but also show the raw form.
