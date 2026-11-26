#!/usr/bin/env bash
# ==============================================================================
# patch-omarchy-icon-font.sh
# Manually patches /usr/share/omarchy/shell/Commons/Style.qml to allow overriding
# bar icon-font size via ~/.config/omarchy/shell.toml under [bar] section.
# ==============================================================================
set -euo pipefail

TARGET="/usr/share/omarchy/shell/Commons/Style.qml"
BACKUP="${TARGET}.orig"

ORIG_CODE='key === "size-horizontal" || key === "size-vertical"'
PATCH_CODE='key === "size-horizontal" || key === "size-vertical" || key === "icon-font"'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

action="${1:-install}"

if [ ! -f "$TARGET" ]; then
    echo -e "${RED}Error: Target file '$TARGET' not found!${NC}" >&2
    exit 1
fi

status() {
    if grep -Fq "$PATCH_CODE" "$TARGET"; then
        echo -e "${GREEN}Status: PATCHED${NC} (icon-font override is active)"
        return 0
    elif grep -Fq "$ORIG_CODE" "$TARGET"; then
        echo -e "${YELLOW}Status: UNPATCHED${NC} (stock Omarchy code)"
        return 1
    else
        echo -e "${RED}Status: UNKNOWN${NC} (code pattern not found in $TARGET)"
        return 2
    fi
}

reload_shell() {
    echo -e "${BLUE}🔄 Restarting Omarchy shell...${NC}"
    if command -v omarchy-restart-shell >/dev/null 2>&1; then
        omarchy-restart-shell >/dev/null 2>&1 || true
        echo -e "${GREEN}✓ Omarchy shell restarted.${NC}"
    elif pgrep -x quickshell >/dev/null 2>&1; then
        pkill -x quickshell || true
        echo -e "${GREEN}✓ Quickshell reloaded.${NC}"
    else
        echo "Quickshell is not currently running."
    fi
}

install_patch() {
    if grep -Fq "$PATCH_CODE" "$TARGET"; then
        echo -e "${GREEN}✓ Style.qml is already patched.${NC}"
        status
        exit 0
    fi

    if ! grep -Fq "$ORIG_CODE" "$TARGET"; then
        echo -e "${RED}Error: Expected original code pattern not found in '$TARGET'. Omarchy version might have changed.${NC}" >&2
        exit 1
    fi

    echo -e "${YELLOW}Applying patch to $TARGET...${NC}"
    echo "Root privileges required for modifying system file:"
    
    # Create backup if not exists
    if [ ! -f "$BACKUP" ]; then
        sudo cp -p "$TARGET" "$BACKUP"
        echo "Created backup at $BACKUP"
    fi

    sudo python3 -c '
import sys
p = sys.argv[1]
with open(p, "r", encoding="utf-8") as f: c = f.read()
target = '\''key === "size-horizontal" || key === "size-vertical"'\''
rep = '\''key === "size-horizontal" || key === "size-vertical" || key === "icon-font"'\''
if target in c:
    with open(p, "w", encoding="utf-8") as f: f.write(c.replace(target, rep, 1))
' "$TARGET"

    if grep -Fq "$PATCH_CODE" "$TARGET"; then
        echo -e "${GREEN}✓ Successfully patched Style.qml!${NC}"
        reload_shell
    else
        echo -e "${RED}Failed to apply patch.${NC}" >&2
        exit 1
    fi
}

uninstall_patch() {
    if ! grep -Fq "$PATCH_CODE" "$TARGET"; then
        echo -e "${YELLOW}Patch is not currently applied.${NC}"
        status
        exit 0
    fi

    echo -e "${YELLOW}Reverting patch in $TARGET...${NC}"
    echo "Root privileges required for modifying system file:"

    if [ -f "$BACKUP" ]; then
        sudo cp -p "$BACKUP" "$TARGET"
        echo -e "${GREEN}✓ Restored from backup ($BACKUP).${NC}"
    else
        sudo python3 -c '
import sys
p = sys.argv[1]
with open(p, "r", encoding="utf-8") as f: c = f.read()
target = '\''key === "size-horizontal" || key === "size-vertical" || key === "icon-font"'\''
rep = '\''key === "size-horizontal" || key === "size-vertical"'\''
if target in c:
    with open(p, "w", encoding="utf-8") as f: f.write(c.replace(target, rep, 1))
' "$TARGET"
        echo -e "${GREEN}✓ Reverted patch line in Style.qml.${NC}"
    fi

    reload_shell
}

case "$action" in
    install|apply)
        install_patch
        ;;
    uninstall|revert|remove)
        uninstall_patch
        ;;
    status|check)
        status
        ;;
    *)
        echo "Usage: $0 [install|uninstall|status]"
        echo "  install   : Apply icon-font support patch (default)"
        echo "  uninstall : Revert to original stock code"
        echo "  status    : Check whether patch is currently installed"
        exit 1
        ;;
esac
