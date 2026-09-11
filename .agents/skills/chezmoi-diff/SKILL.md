---
name: chezmoi-diff
description: Inspect chezmoi diff and status to explain line-by-line code changes, impact, and intent between live system state and source repository. Trigger when analyzing chezmoi diffs, chezmoi status, or explaining dotfile changes.
---

# Chezmoi Diff Explanation & Analysis Workflow

This skill focuses on **analyzing and explaining code changes** between the live system state (`~/.config/...`) and the Chezmoi source repository (`~/.local/share/chezmoi/...`). 

Instead of just showing command outputs (which the user can inspect visually via `cdiff`), this skill directs the agent to analyze **what changed, line-by-line impact, and potential side-effects**.

---

## 1. Inspection Methods

When reviewing chezmoi differences:
- Command-line status & diff:
  ```bash
  chezmoi status
  chezmoi diff
  ```
- Visual side-by-side diff (used by user):
  ```fish
  cdiff [target]
  ```

---

## 2. Line-by-Line Code Explanation Protocol

When analyzing a diff, structure the explanation to clearly answer **"What do these specific line changes actually do?"**:

### A. Context & Target Identification
- Identify the target file (e.g. `dot_config/hypr/bindings.lua` -> `~/.config/hypr/bindings.lua`).
- State whether the modification is on the **Live System** (uncommitted local edit) or in the **Source Repository**.

### B. Explanation of Added / Deleted / Modified Lines
- **`-` (Removed from Live / Missing in Source):** Explain what functionality is being removed or replaced, and what features will break or change if applied.
- **`+` (Added to Live / New in Source):** Explain what the new code does, parameter values, keybindings, flags, or syntax behavior introduced.
- **Changed Logic:** Break down complex syntax changes (e.g. Fish functions, Lua config tables, Hyprland window rules, PowerShell parameters).

### C. Technical Impact Assessment
- **Behavioral Impact:** How does this change affect the desktop environment, window manager, shell environment, or tool configurations?
- **Side Effects / Potential Issues:** Highlight potential syntax errors, missing dependencies, or breaking changes across target devices (`home`, `work`, `s24`).

---

## 3. Decision Guidance & Action Plan

After explaining the code changes, summarize the resolution options in 2-3 clear points:

- **`chezmoi re-add <file>`**: Use when the user edited the live system file and wants to preserve those exact code changes into the git repository.
- **`chezmoi apply <file>`**: Use when the repository contains the authoritative code version and the live system should be overwritten to match.
- **Manual Merge (`cdiff`)**: Use when both sides contain valid code edits that need manual unification.
