# Python Virtual Environments & `uv` Workflow Guide

This document summarizes our discussion regarding dynamic virtual environment auto-switching and migrating to `uv`.

---

## 1. Current State Assessment

- **`uv` Version**: Installed at `0.12.3` (`x86_64-unknown-linux-gnu`).
- **Existing Environments**:
  - Global: `~/.venv` (Created via standard `python3 -m venv` on Python 3.14.4).
  - Project: `/home/unreal/projects/HikStatus/.venv` (Created via `python3 -m venv` on Python 3.14.4).
- **Shell**: Bash (`/bin/bash`), currently without automatic activation hooks.

---

## 2. Dynamic Switching: Two Approaches

### Approach A: The Native `uv` Way (No shell hooks needed)
`uv` automatically traverses parent directories to find a project `.venv` or `pyproject.toml`.

- **How to use**:
  ```bash
  cd /home/unreal/projects/HikStatus

  # Run scripts using project's .venv directly:
  uv run python main.py
  uv run pytest

  # Install dependencies into project's .venv:
  uv pip install requests
  # or uv add requests (if managing pyproject.toml)
  ```
- **Pros**: Zero shell configuration, lightning fast, no activation/deactivation bugs across subshells.
- **Cons**: Requires prefixing execution commands with `uv run` unless `.venv` is manually activated.

---

### Approach B: Shell Auto-Switching Hook (Traditional `python` command)
If you want to type plain `python main.py`, `pip list`, and have `(.venv)` displayed in your prompt automatically when `cd`-ing into project folders:

Add this hook to `~/.bashrc` (or chezmoi template):

```bash
auto_venv() {
  local dir="$PWD"
  local target_venv=""

  # Search upwards for a .venv folder (stopping at $HOME)
  while [[ "$dir" != "$HOME" && "$dir" != "/" ]]; do
    if [[ -d "$dir/.venv" ]]; then
      target_venv="$dir/.venv"
      break
    fi
    dir="$(dirname "$dir")"
  done

  # Fallback to ~/.venv if outside project directories
  if [[ -z "$target_venv" && -d "$HOME/.venv" ]]; then
    target_venv="$HOME/.venv"
  fi

  # Switch environment if target differs from current active one
  if [[ -n "$target_venv" ]]; then
    if [[ "$VIRTUAL_ENV" != "$target_venv" ]]; then
      command -v deactivate >/dev/null 2>&1 && deactivate
      source "$target_venv/bin/activate"
    fi
  else
    if [[ -n "$VIRTUAL_ENV" ]]; then
      command -v deactivate >/dev/null 2>&1 && deactivate
    fi
  fi
}

PROMPT_COMMAND="auto_venv${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
```

---

## 3. Recreating Environments with `uv`

To replace standard `pip`/`venv` environments with `uv`-managed environments:

### Recreate Global `~/.venv`:
```bash
rm -rf ~/.venv
uv venv ~/.venv
# Install global CLI tools/packages if needed:
uv pip install --python ~/.venv/bin/python ruff ipython yt-dlp
```

### Recreate Project `.venv` (`HikStatus`):
```bash
cd /home/unreal/projects/HikStatus
rm -rf .venv
uv venv
uv pip install -r requirements.txt
```

---

## 4. Quick Comparison

| Feature | `uv run <cmd>` | Shell Hook (`auto_venv`) |
| :--- | :--- | :--- |
| **Command syntax** | `uv run python script.py` | `python script.py` |
| **Terminal prompt indicator** | None (unless activated) | Shows `(.venv)` |
| **Shell overhead** | None | Runs check on every prompt |
| **Package installs** | `uv pip install ...` | `uv pip install ...` or `pip install ...` |
