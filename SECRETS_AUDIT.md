# Repository Sensitive Information Audit & Sanitization Report

**Generated Date:** 2026-08-16  
**Repository:** chezmoi dotfiles (`/home/unreal/.local/share/chezmoi`)  
**Status:** Audit Complete — Pending Action before Public Release

---

## 1. Discovered Sensitive Information Summary

| # | Item / Secret | Location | Line / Context | Recommended Action |
|---|---|---|---|---|
| **1** | **Jellyfin / Emby API Key** | `dot_config/scripts/mkvOrganizer.py` | Line 11: `API_KEY = "972dab4257924504b582f9bb4968cc34"` | Move to `dot_config/fish/secrets.fish` as `JELLYFIN_API_KEY` and load via `os.environ.get("JELLYFIN_API_KEY", "")` |
| **2** | **Obsidian MCP Token & URL** | `dot_config/fish/secrets.fish` | Lines 2-3: `OBSIDIAN_API_KEY`, `OBSIDIAN_BASE_URL` | Kept in `secrets.fish` (verified already ignored in `.gitignore`) |
| **3** | **Public Static IPs, Ports & Usernames** | `dot_ssh/config` | Entire file (IPs: `5.202.33.161`, `5.201.141.186`, `217.219.149.57`, custom ports `22456`, `22789`, usernames `unreal`, `mehdi`, `u0_a355`, `admin`) | Add `dot_ssh/config` to `.gitignore` or convert to a sanitized template |
| **4** | **Wake-on-LAN MAC Address & Internal IP** | `dot_config/fish/aliases.fish`<br>`dot_bash_aliases` | Lines 30-31 (fish) / 27-28 (bash):<br>`wake-workpc='ssh 2011 "/tool wol mac=5C:62:8B:C4:DE:9B..."'`<br>`ping-workpc='ssh 2011 "/ping 172.20.2.200"'` | Move MAC and internal IP to variables in `secrets.fish` |
| **5** | **Git User Email** | `dot_gitconfig` | Line 3: `email = mahdi.chamani20@gmail.com` | Keep if intended for public commits, or template if private |

---

## 2. Recommended `dot_config/fish/secrets.fish` Setup

Ensure `dot_config/fish/secrets.fish` (which is in `.gitignore`) contains:

```fish
# Obsidian MCP
set -gx OBSIDIAN_API_KEY "4916f5990d21997ecc7d906196e586298cb244a14df4d5f5f05858e983d66d5f"
set -gx OBSIDIAN_BASE_URL "https://127.0.0.1:27124"

# Jellyfin / Emby
set -gx JELLYFIN_API_KEY "972dab4257924504b582f9bb4968cc34"
set -gx JELLYFIN_URL "http://localhost:8096"

# Network & Hardware IDs
set -gx WORK_PC_MAC "5C:62:8B:C4:DE:9B"
set -gx WORK_PC_IP "172.20.2.200"
```

---

## 3. Code Modifications Required Before Publishing

### A. `dot_config/scripts/mkvOrganizer.py`
Change:
```python
JELLYFIN_URL = "http://localhost:8096"
API_KEY = "972dab4257924504b582f9bb4968cc34"
```
To:
```python
JELLYFIN_URL = os.environ.get("JELLYFIN_URL", "http://localhost:8096")
API_KEY = os.environ.get("JELLYFIN_API_KEY", "")
```

### B. `dot_config/fish/aliases.fish`
Change:
```fish
alias wake-workpc='ssh 2011 "/tool wol mac=5C:62:8B:C4:DE:9B interface=ether2"'
alias ping-workpc='ssh 2011 "/ping 172.20.2.200"'
```
To:
```fish
alias wake-workpc='ssh 2011 "/tool wol mac=$WORK_PC_MAC interface=ether2"'
alias ping-workpc='ssh 2011 "/ping $WORK_PC_IP"'
```

### C. `dot_bash_aliases`
Change:
```bash
alias wake-workpc='ssh 2011 "/tool wol mac=5C:62:8B:C4:DE:9B interface=ether2"'
alias ping-workpc='ssh 2011 "/ping 172.20.2.200"'
```
To:
```bash
alias wake-workpc='ssh 2011 "/tool wol mac=${WORK_PC_MAC} interface=ether2"'
alias ping-workpc='ssh 2011 "/ping ${WORK_PC_IP}"'
```

### D. `.gitignore`
Append `dot_ssh/config` to `.gitignore`:
```gitignore
dot_config/fish/secrets.fish
dot_ssh/config

# Docker
projects/winapps/dot_env
*.iso
```

---

## 4. CRITICAL: Git Commit History Warning

> ⚠️ **IMPORTANT**: The Emby/Jellyfin API key and SSH host configs exist in past Git commits (e.g. commit `1f18e97` and commit `997a4e9`).
>
> Simply removing or editing them in a new commit will **NOT** remove them from Git history. Anyone who clones the repo will be able to see them via `git log -p`.

### Solutions before pushing to GitHub / public remote:
1. **Option 1 (Clean slate for public repo)**:
   Create a fresh orphan branch or clean initial commit without history:
   ```bash
   git checkout --orphan public-release
   git add -A
   git commit -m "feat: initial public dotfiles release"
   ```
2. **Option 2 (Rewrite history with git-filter-repo)**:
   ```bash
   pip install git-filter-repo
   git-filter-repo --replace-text <(echo "972dab4257924504b582f9bb4968cc34==>REDACTED")
   ```
