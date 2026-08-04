#!/usr/bin/env bash

CONTAINER_NAME="WinApps"
WINAPPS_BIN="/home/unreal/.local/bin/winapps"
IDLE_WAIT_SECONDS=600  # 10 minutes
LOCK_FILE="/tmp/winapps_launcher.pid"

# 1. Check if a countdown timer is already running from a previous session
if [ -f "$LOCK_FILE" ]; then
    PREV_PID=$(cat "$LOCK_FILE")
    # Kill the background sleep process so Docker doesn't stop mid-session
    kill "$PREV_PID" 2>/dev/null
    rm -f "$LOCK_FILE"
    echo "[+] Cancelled previous shutdown timer."
fi

# 2. Make sure the container is running
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" != "true" ]; then
    echo "[+] Starting $CONTAINER_NAME container..."
    docker start "$CONTAINER_NAME" > /dev/null 2>&1

    until [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" = "true" ]; do
        sleep 1
    done
    sleep 2
fi

# 3. Open the RDP window (blocks until you close the window)
echo "[+] Opening Windows workspace..."
"$WINAPPS_BIN" windows

# 4. Window closed -> Start the 10-minute countdown in the background
echo "[+] RDP window closed. Starting 10-minute idle timer..."

(
    sleep "$IDLE_WAIT_SECONDS"
    echo "[+] 10 minutes elapsed. Stopping $CONTAINER_NAME..."
    docker stop "$CONTAINER_NAME" > /dev/null 2>&1
    rm -f "$LOCK_FILE"
) &

# Store the background process PID so a new click can cancel it
echo $! > "$LOCK_FILE"
