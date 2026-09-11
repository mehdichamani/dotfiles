#!/usr/bin/env bash
# Docs: ~/Notes/Tech/Shell/Termux-X11-XFCE-Setup.md
# Launcher for Termux-X11 and XFCE4 desktop environment in Termux

# Ensure running inside Termux
if [ -z "$PREFIX" ]; then
    PREFIX="/data/data/com.termux/files/usr"
fi

# Clean up previous dead or orphaned X11 sessions
pkill -f com.termux.x11 2>/dev/null
pkill -f xfce4-session 2>/dev/null
pkill -f termux-x11 2>/dev/null

echo "==> Launching Termux-X11 companion app..."
# Start Termux-X11 companion app on Android
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1

# Export display and audio variables
export DISPLAY=:0
export PULSE_SERVER=127.0.0.1

echo "==> Starting X11 server on :0..."
termux-x11 :0 -ac &
X11_PID=$!

# Wait briefly for X server initialization
sleep 1.2

echo "==> Launching XFCE4 Session..."
dbus-launch --exit-with-session xfce4-session

# Cleanup when XFCE session ends (User logged out)
echo "==> Cleaning up session..."
kill "$X11_PID" 2>/dev/null
pkill -f com.termux.x11 2>/dev/null
