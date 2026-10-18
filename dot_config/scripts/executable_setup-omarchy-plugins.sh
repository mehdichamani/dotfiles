#!/usr/bin/env bash
# ==============================================================================
# setup-omarchy-plugins.sh - Ensures third-party Omarchy shell plugins are installed
# ==============================================================================
set -e

# Only execute on Omarchy systems
if ! command -v omarchy >/dev/null 2>&1; then
    exit 0
fi

if [ ! -d "/usr/share/omarchy" ] && [ ! -d "$HOME/.config/omarchy" ]; then
    exit 0
fi

echo -e "\n🧩 Omarchy Shell Plugins:"

PLUGINS_DIR="$HOME/.config/omarchy/plugins"
mkdir -p "$PLUGINS_DIR"

# Defined Third-Party Plugins: ID|URL
PLUGINS=(
    "tornikegomareli.spaces|https://github.com/tornikegomareli/omarchy-spaces"
    "crmne.hyprmoncfg|https://github.com/crmne/omarchy-hyprmoncfg.git"
    "omarchy-menu-omni|https://github.com/filip-spaldon/omarchy-menu.git"
    "io.github.codesmith28.omalt-tab|https://github.com/Codesmith28/omalt-tab"
)

NEWLY_INSTALLED=0

for item in "${PLUGINS[@]}"; do
    plugin_id="${item%%|*}"
    plugin_url="${item##*|}"
    target_path="$PLUGINS_DIR/$plugin_id"

    if [ -d "$target_path" ]; then
        echo -e "  \033[1;32m✓\033[0m Plugin '$plugin_id' is already installed."
    else
        echo "  📥 Installing missing plugin '$plugin_id' from $plugin_url..."
        if omarchy plugin add "$plugin_url" --enable --yes; then
            echo -e "  \033[1;32m✓\033[0m Successfully installed and enabled '$plugin_id'."
            NEWLY_INSTALLED=1
        else
            echo "  ⚠️ Failed to install plugin '$plugin_id'. Continuing..."
        fi
    fi
done

if [ "$NEWLY_INSTALLED" -eq 1 ]; then
    echo "🔄 Reloading Omarchy shell to activate new plugins..."
    if command -v omarchy-restart-shell >/dev/null 2>&1; then
        omarchy-restart-shell >/dev/null 2>&1 || true
    elif pgrep -x quickshell >/dev/null 2>&1; then
        pkill -x quickshell || true
    fi
    echo "✅ Omarchy shell plugins synchronized!"
fi
