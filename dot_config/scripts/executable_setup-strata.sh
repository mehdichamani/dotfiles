#!/usr/bin/env bash
# ==============================================================================
# setup-strata.sh - Ensures Strata file manager & integrations are installed on Omarchy
# ==============================================================================
set -e

# Only execute on Omarchy systems
if ! command -v omarchy >/dev/null 2>&1; then
    exit 0
fi

if [ ! -d "/usr/share/omarchy" ] && [ ! -d "$HOME/.config/omarchy" ]; then
    exit 0
fi

echo -e "\n📂 Strata File Manager & Integrations:"

if command -v strata >/dev/null 2>&1; then
    echo -e "  \033[1;32m✓\033[0m Strata is already installed ($(strata --version 2>/dev/null || echo 'installed'))."
    exit 0
fi

echo "  📥 Installing Strata (with desktop launcher, file-manager default, chooser & udiskie unlock)..."

if curl -fsSL https://raw.githubusercontent.com/lgse/strata/main/install.sh | bash -s -- \
    --non-interactive \
    --with-desktop-entry \
    --with-folder-association \
    --with-file-manager \
    --with-file-chooser \
    --with-omarchy-keybinds \
    --with-udiskie-unlock; then
    echo -e "  \033[1;32m✓\033[0m Successfully installed Strata!"
else
    echo "  ⚠️ Failed to install Strata automatically."
fi
