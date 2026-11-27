---
name: syncthing
description: Manage Syncthing folders, versioning, and cleanup across home, work, and phone (s24) devices. Enforces max 7-day trashcan versioning and documents how to connect to the phone's Syncthing REST API.
---

# Syncthing Management Skill

## Rules
1. **Max 7-day trash:** All Syncthing folders on all devices (`home`, `work`, `s24`) must use `trashcan` versioning with `cleanoutDays` set to **at most `7`** (or no versioning). Never leave `cleanoutDays` at `0` (infinite retention).
2. **Secrets:** Never hardcode the phone's API key or credentials in scripts or docs. Always load them from `~/.ssh/secrets/syncthing.env`.

---

## Linux Devices (`home`, `work`)
Use `syncthing cli` directly (locally on `home`, or via `ssh work-tailscale` / `s work`):

```fish
# List folders
syncthing cli config folders list

# Enforce 7-day trashcan versioning on all folders
for f in (syncthing cli config folders list)
    syncthing cli config folders $f versioning type set trashcan
    syncthing cli config folders $f versioning params set cleanoutDays 7
end
```

---

## Phone (`s24`) via REST API
The Android Syncthing app does not expose `syncthing cli` over Termux SSH, so settings are managed via its HTTPS REST API.

1. **Load credentials** from `~/.ssh/secrets/syncthing.env`:
   - `SYNCTHING_PHONE_PORT` (default `8384`)
   - `SYNCTHING_PHONE_API_KEY`
   - `SYNCTHING_PHONE_USER`

2. **Resolve the phone IP dynamically** based on `~/.config/name` (never hardcode it):
   - `home`: `192.168.0.101`
   - `work`: `192.168.1.101` or `172.20.0.101`
   - Fallback / remote: Tailscale `100.102.24.24`

   ```fish
   source ~/.ssh/secrets/syncthing.env
   switch (cat ~/.config/name)
       case home
           set phone_ip 192.168.0.101
       case work
           set phone_ip 192.168.1.101
       case '*'
           set phone_ip 100.102.24.24
   end
   set phone_url "https://$phone_ip:$SYNCTHING_PHONE_PORT"
   ```

3. **Query folders:**
   ```fish
   curl -sk -H "X-API-Key: $SYNCTHING_PHONE_API_KEY" "$phone_url/rest/config/folders" | jq '[.[] | {id, label, path, versioning}]'
   ```

4. **Set 7-day trashcan versioning on all phone folders:**
   ```fish
   curl -sk -H "X-API-Key: $SYNCTHING_PHONE_API_KEY" "$phone_url/rest/config/folders" \
     | jq '[.[] | .versioning.type = "trashcan" | .versioning.params = {"cleanoutDays": "7"}]' \
     | curl -sk -X PUT -H "X-API-Key: $SYNCTHING_PHONE_API_KEY" -H "Content-Type: application/json" -d @- "$phone_url/rest/config/folders"
   ```

5. **Clean `.stversions` on phone** (via SSH):
   ```fish
   s s24 'rm -rf /sdcard/media/.stversions/* /sdcard/Notes/.stversions/* /sdcard/insync/.stversions/*'
   ```
