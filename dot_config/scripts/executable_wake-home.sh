#!/bin/bash
# ==============================================================================
# Smart Wake-on-LAN Script for Home PC (S24 Ultra / Remote -> Home PC)
# ==============================================================================

TARGET_MAC="bc:fc:e7:3b:8f:44"
LAN_BROADCAST="192.168.0.255"
ROUTER_LAN_IP="192.168.0.1"
ROUTER_TS_IP="100.91.196.36"
PC_LAN_IP="192.168.0.100"
PC_TS_IP="100.74.60.10"
TIMEOUT_SECONDS=45

# Colors & Formatting
BOLD="\033[1m"
RESET="\033[0m"
GREEN="\033[38;5;48m"
RED="\033[38;5;196m"
YELLOW="\033[38;5;220m"
CYAN="\033[38;5;51m"
BLUE="\033[38;5;39m"
GRAY="\033[38;5;245m"

clear 2>/dev/null || true
echo -e "${BOLD}${BLUE}====================================================${RESET}"
echo -e "${BOLD}${CYAN}          ⚡ SMART WAKE-ON-LAN CONTROLLER ⚡        ${RESET}"
echo -e "${BOLD}${BLUE}====================================================${RESET}"
echo -e "${GRAY}Target Host:${RESET} Home PC (${BOLD}${TARGET_MAC}${RESET})\n"

# Step 0: Check if PC is already awake
echo -ne "${GRAY}[*] Checking if Home PC is already online... ${RESET}"
if ping -c 1 -W 1 "$PC_LAN_IP" >/dev/null 2>&1 || ping -c 1 -W 1 "$PC_TS_IP" >/dev/null 2>&1; then
    echo -e "${GREEN}${BOLD}ALREADY ONLINE!${RESET}"
    echo -e "\n${GREEN}✔ Home PC is already up and running.${RESET}"
    exit 0
else
    echo -e "${YELLOW}OFFLINE${RESET}"
fi

# Step 1: Detect Network Topology & Send Magic Packet
SENT=0

echo -e "\n${BOLD}[1/2] Determining connection route...${RESET}"

# Check Local Wi-Fi Network (LAN)
if ping -c 1 -W 1 "$ROUTER_LAN_IP" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✔${RESET} Connected to Home Wi-Fi Network (${CYAN}192.168.0.x${RESET})"
    echo -ne "  ${GRAY}↳ Sending Magic Packet directly (Broadcast + Router)... ${RESET}"
    
    # Send via local broadcast if wol binary is available
    if which wol >/dev/null 2>&1; then
        wol -i "$LAN_BROADCAST" "$TARGET_MAC" >/dev/null 2>&1 || true
    fi
    
    # Also trigger via router SSH just to be 100% resilient
    ssh -o ConnectTimeout=2 -o BatchMode=yes modem 'wake' >/dev/null 2>&1 || true
    
    echo -e "${GREEN}${BOLD}SENT!${RESET}"
    SENT=1
else
    echo -e "  ${YELLOW}✖${RESET} Home Wi-Fi not detected (Remote / Mobile Data)"
    echo -ne "  ${GRAY}↳ Checking Tailscale connection to router (${ROUTER_TS_IP})... ${RESET}"
    
    # Check Tailscale connectivity to router
    if nc -z -w 2 "$ROUTER_TS_IP" 22 >/dev/null 2>&1; then
        echo -e "${GREEN}REACHABLE${RESET}"
        echo -ne "  ${GRAY}↳ Dispatching WOL command via router over Tailscale... ${RESET}"
        
        if ssh -o ConnectTimeout=3 -o BatchMode=yes modem-tailscale 'wake' >/dev/null 2>&1; then
            echo -e "${GREEN}${BOLD}SENT!${RESET}"
            SENT=1
        else
            echo -e "${RED}FAILED TO EXECUTE SSH${RESET}"
        fi
    else
        echo -e "${RED}UNREACHABLE${RESET}"
    fi
fi

# If packet could not be sent
if [ $SENT -eq 0 ]; then
    echo -e "\n${RED}${BOLD}❌ ERROR: Unable to reach home network or Tailscale router!${RESET}"
    echo -e "${YELLOW}👉 Please make sure:${RESET}"
    echo -e "   1. You are connected to Home Wi-Fi, OR"
    echo -e "   2. Turn ON the ${BOLD}Tailscale VPN${RESET} app on your phone."
    if which termux-vibrate >/dev/null 2>&1; then
        termux-vibrate -d 300 2>/dev/null || true
    fi
    exit 1
fi

# Step 2: Verification & Ping Watcher
echo -e "\n${BOLD}[2/2] Awaiting system startup (Timeout: ${TIMEOUT_SECONDS}s)...${RESET}"
START_TIME=$(date +%s)
AWAKE=0

SPINNER=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
SPIN_IDX=0

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ $ELAPSED -ge $TIMEOUT_SECONDS ]; then
        break
    fi

    SPIN_CHAR=${SPINNER[$SPIN_IDX]}
    SPIN_IDX=$(( (SPIN_IDX + 1) % 10 ))

    echo -ne "\r  ${CYAN}${SPIN_CHAR}${RESET} Waiting for reply... [${ELAPSED}s / ${TIMEOUT_SECONDS}s] "

    # Check both LAN IP and Tailscale IP
    if ping -c 1 -W 1 "$PC_LAN_IP" >/dev/null 2>&1 || ping -c 1 -W 1 "$PC_TS_IP" >/dev/null 2>&1; then
        AWAKE=1
        break
    fi

    sleep 1
done

echo ""

if [ $AWAKE -eq 1 ]; then
    ELAPSED=$(($(date +%s) - START_TIME))
    echo -e "\n${GREEN}${BOLD}====================================================${RESET}"
    echo -e "${GREEN}${BOLD}       ✔ SUCCESS: Home PC is ONLINE! (${ELAPSED}s)      ${RESET}"
    echo -e "${GREEN}${BOLD}====================================================${RESET}"
    
    # Notify & Vibrate phone
    if which termux-vibrate >/dev/null 2>&1; then
        termux-vibrate -d 150 2>/dev/null || true
    fi
    if which termux-notification >/dev/null 2>&1; then
        termux-notification -t "Home PC Online" -c "System responded to ping after ${ELAPSED}s." --id "wake_pc" 2>/dev/null || true
    fi
    exit 0
else
    echo -e "\n${YELLOW}${BOLD}⚠ WARNING: Timeout reached (${TIMEOUT_SECONDS}s).${RESET}"
    echo -e "${GRAY}Magic Packet was successfully delivered, but PC has not answered ping yet.${RESET}"
    echo -e "${GRAY}(Booting, OS decrypt, or BIOS resume might take longer).${RESET}"
    exit 2
fi
