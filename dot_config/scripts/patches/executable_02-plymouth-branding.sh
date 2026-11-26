#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-install}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

NAME_FILE="$HOME/.config/name"
HOST_NAME=""
if [[ -f "$NAME_FILE" ]]; then
    HOST_NAME="$(tr -d '[:space:]' < "$NAME_FILE")"
fi

case "$HOST_NAME" in
    home) FG_COLOR="#94e2d5" ;;
    work) FG_COLOR="#ff8800" ;;
    *)    FG_COLOR="" ;;
esac

SCREENSAVER_FILE="$HOME/.config/omarchy/branding/screensaver.txt"
if [[ ! -f "$SCREENSAVER_FILE" ]]; then
    REPO_SCREENSAVER="$SCRIPT_DIR/../../omarchy/branding/screensaver.txt"
    if [[ -f "$REPO_SCREENSAVER" ]]; then
        SCREENSAVER_FILE="$REPO_SCREENSAVER"
    fi
fi

LOGO_FILE="$HOME/.config/omarchy/branding/plymouth-${HOST_NAME}.png"
FONT_FILE="/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf"

if [[ "$ACTION" == "status" ]]; then
    if [[ -z "$FG_COLOR" ]]; then
        echo "Status: NOT READY (unknown or missing ~/.config/name: '$HOST_NAME')"
        exit 0
    fi
    if [[ ! -f "$SCREENSAVER_FILE" ]]; then
        echo "Status: NOT READY (missing screensaver.txt)"
        exit 0
    fi
    if [[ -f "$LOGO_FILE" ]]; then
        echo "Status: READY (host: $HOST_NAME, color: $FG_COLOR, logo: $LOGO_FILE)"
    else
        echo "Status: NOT GENERATED (host: $HOST_NAME, color: $FG_COLOR, source: $SCREENSAVER_FILE)"
    fi
    exit 0
fi

if [[ -z "$FG_COLOR" ]]; then
    echo "Error: Unknown or missing ~/.config/name: '$HOST_NAME' (expected 'home' or 'work')" >&2
    exit 1
fi

if [[ ! -f "$SCREENSAVER_FILE" ]]; then
    echo "Error: screensaver.txt not found at $SCREENSAVER_FILE" >&2
    exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
    echo "Error: 'magick' (ImageMagick) is not installed." >&2
    exit 1
fi

mkdir -p "$(dirname "$LOGO_FILE")"

echo "Generating $LOGO_FILE from $SCREENSAVER_FILE ($HOST_NAME: $FG_COLOR)..."
magick -background none -fill "$FG_COLOR" -font "$FONT_FILE" -pointsize 20 label:@"$SCREENSAVER_FILE" "$LOGO_FILE"

echo "Applying Plymouth branding via omarchy plymouth set..."
omarchy plymouth set '#1e1e2e' "$FG_COLOR" "$LOGO_FILE"
