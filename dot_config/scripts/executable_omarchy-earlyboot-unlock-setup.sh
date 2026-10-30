#!/usr/bin/env bash
# ==============================================================================
# Omarchy Early-Boot Remote Unlock & Plymouth Setup & Manager
# ==============================================================================
# Pure Drop-in Architecture (Never modifies upstream Omarchy system files)
# Visual Debugging & Overlay Message on Plymouth Screen
# ==============================================================================

set -euo pipefail

# ANSI Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
MAGENTA='\033[1;35m'
NC='\033[0m'

# Drop-in Paths (Must sort AFTER omarchy_hooks.conf in sort -V order)
HOOKS_CONF="/etc/mkinitcpio.conf.d/remote-unlock.conf"
MODULES_CONF="/etc/mkinitcpio.conf.d/remote-unlock-driver.conf"
LIMINE_CONF="/etc/limine-entry-tool.d/remote-unlock.conf"
AUTOLOGIN_SERVICE="/etc/systemd/system/remote-unlock-no-autologin.service"
HOOK_REMOTE_UNLOCK_INSTALL="/etc/initcpio/install/remote-unlock"
HOOK_REMOTE_UNLOCK_RUN="/etc/initcpio/hooks/remote-unlock"
TINYSSH_DIR="/etc/tinyssh"
PACMAN_HOOK="/etc/pacman.d/hooks/mkinitcpio-tailscale.hook"

SSH_PORT="22456"

# Check root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        printf "${RED}[✗] این اسکریپت باید با دسترسی روت (sudo) اجرا شود.${NC}\n"
        exit 1
    fi
}

# Detect Host Profile
detect_profile() {
    local host_name=""
    local user_name="${SUDO_USER:-$USER}"
    local user_home
    user_home=$(getent passwd "${user_name}" 2>/dev/null | cut -d: -f6)
    user_home="${user_home:-$HOME}"

    if [ -f "${user_home}/.config/name" ]; then
        host_name="$(tr -d '[:space:]' < "${user_home}/.config/name")"
    fi

    if [ -z "$host_name" ]; then
        host_name="$(hostname 2>/dev/null || uname -n)"
    fi

    case "$host_name" in
        home|Home*|homeomarchy)
            PROFILE="home"
            INTERFACE="eth0"
            DRIVER_MODULE="r8169"
            HOSTNAME="homeomarchy"
            KERNEL_NET_CMD="ip=::::${HOSTNAME}:${INTERFACE}:dhcp netconf_timeout=30"
            ;;
        work|Work*|workomarchy|WorkOmarchy)
            PROFILE="work"
            INTERFACE="eth0"
            DRIVER_MODULE="e1000e"
            HOSTNAME="workomarchy"
            KERNEL_NET_CMD="ip=::::${HOSTNAME}:${INTERFACE}:dhcp netconf_timeout=30"
            ;;
        *)
            PROFILE="custom"
            HOSTNAME="omarchy"
            INTERFACE="eth0"
            DRIVER_MODULE="r8169"
            KERNEL_NET_CMD="ip=::::${HOSTNAME}:${INTERFACE}:dhcp netconf_timeout=45"
            ;;
    esac
}

show_banner() {
    clear 2>/dev/null || true
    printf "${GREEN}"
    cat << 'EOF'
  ___  __  __   _   ___  ___ _  ___   __
 / _ \|  \/  | /_\ | _ \/ __| || \ \ / /
| (_) | |\/| |/ _ \|   / (__| __ |\ V / 
 \___/|_|  |_/_/ \_\_|_\\___|_||_| |_|  
EOF
    printf "${NC}"
    printf "${CYAN} Omarchy Early-Boot Remote Unlock & Plymouth Manager${NC}\n"
    printf "================================================================\n"
    printf "${WHITE}▸ Detected Profile:  ${YELLOW}%s${NC}\n" "${PROFILE}"
    printf "${WHITE}▸ Network Interface: ${YELLOW}%s${NC} (Kernel early-boot name)\n" "${INTERFACE}"
    printf "${WHITE}▸ Ethernet Driver:   ${YELLOW}%s${NC}\n" "${DRIVER_MODULE}"
    printf "${WHITE}▸ IP Assignment:     ${YELLOW}DHCP (Auto IP & DNS)${NC}\n"
    printf "${WHITE}▸ TinySSH Port:      ${YELLOW}%s${NC}\n" "${SSH_PORT}"
    printf "================================================================\n\n"
}

# Install packages
install_dependencies() {
    local mode="$1"
    printf "${CYAN}▷ در حال بررسی بسته‌های پیش‌نیاز...${NC}\n"

    local pkgs=(mkinitcpio-netconf mkinitcpio-utils)
    if [ "$mode" = "lan" ] || [ "$mode" = "hybrid" ]; then
        pkgs+=(tinyssh mkinitcpio-tinyssh)
    fi

    local missing=()
    for pkg in "${pkgs[@]}"; do
        if ! pacman -Q "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        printf "${YELLOW}▷ نصب بسته‌های مورد نیاز با pacman: ${missing[*]}${NC}\n"
        pacman -S --needed --noconfirm "${missing[@]}"
    fi

    if [ "$mode" = "tailscale" ] || [ "$mode" = "hybrid" ]; then
        if ! pacman -Q mkinitcpio-tailscale >/dev/null 2>&1; then
            printf "${YELLOW}▷ بسته mkinitcpio-tailscale یافت نشد. در حال نصب با yay...${NC}\n"
            local real_user="${SUDO_USER:-$USER}"
            su - "${real_user}" -c "yay -S --noconfirm mkinitcpio-tailscale" || {
                printf "${RED}[✗] نصب mkinitcpio-tailscale با خطا مواجه شد. لطفاً دستی اجرا کنید: yay -S mkinitcpio-tailscale${NC}\n"
                exit 1
            }
        fi

        # Check tailscale initrd registration key
        if [ ! -d "/etc/initcpio/tailscale" ] || [ -z "$(ls -A /etc/initcpio/tailscale 2>/dev/null)" ]; then
            printf "\n${YELLOW}⚠️  کلید ثبت‌نام Tailscale برای بوت اولیه یافت نشد.${NC}\n"
            printf "${CYAN}▷ اجرای ثبت‌نام نود بوت اولیه با تگ tag:initrd...${NC}\n"
            printf "${WHITE}لطفاً لینکی که در ادامه نمایش داده می‌شود را در مرورگر باز کرده و تایید نمایید:${NC}\n\n"
            setup-initcpio-tailscale --advertise-tags=tag:initrd || true
        else
            printf "${GREEN}[✓] کلید ثبت‌نام Tailscale برای بوت اولیه در /etc/initcpio/tailscale موجود است.${NC}\n"
        fi
    fi

    printf "${GREEN}[✓] تمام بسته‌ها و وابستگی‌ها آماده هستند.${NC}\n"
}

# Setup TinySSH keys from authorized_keys
setup_tinyssh_keys() {
    printf "${CYAN}▷ در حال آماده‌سازی کلیدهای احراز هویت TinySSH...${NC}\n"
    mkdir -p "${TINYSSH_DIR}"

    local user_name="${SUDO_USER:-$USER}"
    local user_home
    user_home=$(getent passwd "${user_name}" 2>/dev/null | cut -d: -f6)
    user_home="${user_home:-$HOME}"

    if [ -f "${user_home}/.ssh/authorized_keys" ]; then
        cp "${user_home}/.ssh/authorized_keys" "${TINYSSH_DIR}/root_key"
        chmod 600 "${TINYSSH_DIR}/root_key"
        printf "${GREEN}[✓] کلیدهای احراز هویت در ${TINYSSH_DIR}/root_key ثبت شدند.${NC}\n"
    else
        printf "${RED}[✗] فایل ${user_home}/.ssh/authorized_keys یافت نشد!${NC}\n"
        exit 1
    fi

    if [ ! -d "${TINYSSH_DIR}/sshkeydir" ] || [ -z "$(ls -A "${TINYSSH_DIR}/sshkeydir" 2>/dev/null)" ]; then
        printf "${CYAN}▷ در حال تولید کلیدهای هاست TinySSH...${NC}\n"
        tinysshd-makekey "${TINYSSH_DIR}/sshkeydir" 2>/dev/null || true
        printf "${GREEN}[✓] کلیدهای هاست TinySSH ایجاد شدند.${NC}\n"
    fi
}

# Configure Kernel network parameters via Limine Entry Tool drop-in
setup_limine_network() {
    printf "${CYAN}▷ ایجاد دراپ‌این پارامتر شبکه در ${LIMINE_CONF}...${NC}\n"
    mkdir -p "$(dirname "${LIMINE_CONF}")"
    cat > "${LIMINE_CONF}" << EOF
# Omarchy Early-Boot Network Configuration (Auto-generated)
KERNEL_CMDLINE[default]+=" ${KERNEL_NET_CMD}"
EOF
    printf "${GREEN}[✓] تنظیمات کامندلاین کرنل ثبت شد.${NC}\n"
}

# Setup network driver module drop-in
setup_network_driver() {
    printf "${CYAN}▷ افزودن درایور شبکه ${DRIVER_MODULE} در ${MODULES_CONF}...${NC}\n"
    mkdir -p "$(dirname "${MODULES_CONF}")"
    cat > "${MODULES_CONF}" << EOF
# Omarchy Early-Boot Network Driver Module
MODULES+=(${DRIVER_MODULE})
EOF
    printf "${GREEN}[✓] ماژول درایور شبکه ثبت شد.${NC}\n"
}

# Custom TinySSH runner on custom port 22456
setup_tinyssh_custom_port() {
    mkdir -p /etc/initcpio/hooks
    cat > /etc/initcpio/hooks/tinyssh << EOF
#!/usr/bin/ash

run_hook ()
{
  [ -d /dev/pts ] || mkdir -p /dev/pts
  mount -t devpts none /dev/pts 2>/dev/null || mount -t devpts devpts /dev/pts 2>/dev/null || true

  # Ensure interface is up
  [ -e "/sys/class/net/${INTERFACE}" ] && /sbin/ip link set dev "${INTERFACE}" up 2>/dev/null || true

  echo "Starting TinySSH on port ${SSH_PORT}"
  /bin/tcpsvd 0 ${SSH_PORT} /usr/sbin/tinysshd -v /etc/tinyssh/sshkeydir &
  echo "\$!" > /run/tinysshd.pid
}

run_cleanuphook ()
{
  killall tcpsvd 2>/dev/null || true
  umount /dev/pts 2>/dev/null || true
}
EOF
}

# Hook Drop-in
setup_mkinitcpio_hooks_dropin() {
    local mode="$1"
    printf "${CYAN}▷ ایجاد دراپ‌این هوک‌های mkinitcpio در ${HOOKS_CONF}...${NC}\n"
    mkdir -p "$(dirname "${HOOKS_CONF}")"

    local unlock_chain="netconf"
    if [ "$mode" = "tailscale" ]; then
        unlock_chain="netconf tailscale encryptssh remote-unlock"
    elif [ "$mode" = "hybrid" ]; then
        setup_tinyssh_custom_port
        unlock_chain="netconf tinyssh tailscale encryptssh remote-unlock"
    else
        setup_tinyssh_custom_port
        unlock_chain="netconf tinyssh encryptssh remote-unlock"
    fi

    cat > "${HOOKS_CONF}" << EOF
# Omarchy Early-Boot Remote Unlock Hooks Drop-in
_earlyboot_hooks=()
for _h in "\${HOOKS[@]}"; do
  # Skip hooks that will be re-added as part of unlock_chain
  case "\$_h" in
    netconf|tinyssh|tailscale|remote-unlock) continue ;;
    encrypt|encryptssh)
      _earlyboot_hooks+=(${unlock_chain})
      ;;
    *)
      _earlyboot_hooks+=("\$_h")
      ;;
  esac
done
HOOKS=("\${_earlyboot_hooks[@]}")
unset _earlyboot_hooks _h
EOF
    printf "${GREEN}[✓] دراپ‌این هوک‌ها تنظیم شد: (${unlock_chain})${NC}\n"
}

# Setup remote-unlock runtime & install hook (with visual debug message on Plymouth)
setup_remote_unlock_hook() {
    local mode="$1"
    printf "${CYAN}▷ ایجاد هوک دیباگ بصری و هندلر ریموت در initcpio...${NC}\n"
    mkdir -p /etc/initcpio/hooks /etc/initcpio/install

    # 1. Runtime Hook: runs in background for visual status and persists SDDM flag on late hook
    cat > "${HOOK_REMOTE_UNLOCK_RUN}" << EOF
#!/usr/bin/ash

run_hook ()
{
    (
        local last_msg=""
        # Loop dynamically until disk is unlocked without arbitrary timeouts
        while [ ! -e "/dev/mapper/root" ] && [ ! -f "/.done" ]; do
            local my_ip=""
            if [ -f /ip_opts ]; then
                . /ip_opts
                [ -n "\${address}" ] && my_ip="\${address}"
            fi
            if [ -z "\${my_ip}" ]; then
                my_ip=\$(/sbin/ip -4 addr show dev ${INTERFACE} 2>/dev/null | grep inet | awk '{print \$2}' | cut -d/ -f1 | head -n1 || true)
            fi
            [ -z "\${my_ip}" ] && my_ip="[Connecting...]"

            local ts_status=""
            if [ -f /run/tailscaled.pid ] && kill -0 \$(cat /run/tailscaled.pid 2>/dev/null) 2>/dev/null; then
                ts_status="Tailscale: Online (${HOSTNAME}-initrd)"
            else
                ts_status="Tailscale: N/A"
            fi

            local msg="SSH: ssh -p ${SSH_PORT} root@\${my_ip}  |  \${ts_status}"

            # Anti-flicker: Only update Plymouth when message content actually changes
            if [ "\${msg}" != "\${last_msg}" ]; then
                if command -v plymouth >/dev/null 2>&1 && plymouth --ping 2>/dev/null; then
                    plymouth display-message --text="\${msg}" 2>/dev/null || true
                fi
                last_msg="\${msg}"
            fi

            sleep 1
        done

        if [ -f "/run/luks-remote-unlock" ]; then
            if command -v plymouth >/dev/null 2>&1 && plymouth --ping 2>/dev/null; then
                plymouth display-message --text="Disk unlocked remotely; boot continues..." 2>/dev/null || true
            fi
        fi
    ) &
}

run_latehook ()
{
    # Propagate unlock flag from initramfs tmpfs to real system /run before switch_root
    if [ -f "/run/luks-remote-unlock" ]; then
        mkdir -p /sysroot/run 2>/dev/null || true
        : > /sysroot/run/luks-remote-unlock 2>/dev/null || true
    fi
}
EOF

    # 2. Install Hook: provides resilient cryptsetup_shell with retry loop and emergency shell fallback
    cat > "${HOOK_REMOTE_UNLOCK_INSTALL}" << 'EOF'
#!/bin/bash
build() {
    add_file - /bin/cryptsetup_shell 0755 < <(
        cat << 'INSIDE_SHELL'
#!/bin/sh
if [ ! -c "/dev/mapper/control" ]; then
    echo "Encryption control device not ready. Please wait..."
    exit 1
fi

cryptdev="$(cat /.cryptdev 2>/dev/null)"
cryptname="$(cat /.cryptname 2>/dev/null)"
cryptargs="$(cat /.cryptargs 2>/dev/null)"

if [ -z "$cryptdev" ] || [ -z "$cryptname" ]; then
    echo "Encryption metadata not found in initramfs."
    exit 1
fi

if [ -b "/dev/mapper/${cryptname}" ]; then
    echo "Volume '${cryptname}' is already unlocked."
    exit 0
fi

echo ""
echo "=========================================================="
echo " Omarchy Early-Boot Remote Disk Unlock (LUKS)"
echo " Target: ${cryptdev} -> /dev/mapper/${cryptname}"
echo " Type 'shell' to open an emergency recovery shell."
echo "=========================================================="
echo ""

max_attempts=3
attempt=1

while [ $attempt -le $max_attempts ]; do
    printf "Enter LUKS passphrase (attempt %d/%d): " "$attempt" "$max_attempts"
    stty -echo 2>/dev/null || true
    read -r pass
    stty echo 2>/dev/null || true
    echo ""

    if [ "$pass" = "shell" ]; then
        echo "Entering emergency recovery shell. Type 'exit' to return to unlock prompt."
        /bin/sh
        continue
    fi

    if [ -z "$pass" ]; then
        continue
    fi

    if printf '%s' "$pass" | cryptsetup open --type luks "$cryptdev" "$cryptname" $cryptargs --key-file=- ; then
        echo > /.done
        : > /run/luks-remote-unlock
        killall -q cryptsetup 2>/dev/null || true
        if command -v plymouth >/dev/null 2>&1 && plymouth --ping 2>/dev/null; then
            plymouth display-message --text="Disk unlocked remotely; boot continues..." 2>/dev/null || true
            killall -q plymouth 2>/dev/null || true
        fi
        echo "Disk unlocked successfully! Boot continues."
        exit 0
    else
        echo "[!] Passphrase incorrect."
        attempt=$((attempt + 1))
    fi
done

echo ""
echo "[✗] $max_attempts failed passphrase attempts."
echo "Spawning emergency rescue shell..."
exec /bin/sh
INSIDE_SHELL
    )

    # Ensure Plymouth message visibility on z-index layer
    if [[ -f "${BUILDROOT}/usr/share/plymouth/themes/omarchy/omarchy.script" ]]; then
        sed -i 's/message_sprite.SetPosition(10, 10, 10000);/message_sprite.SetPosition(10, 10, 20000);/' "${BUILDROOT}/usr/share/plymouth/themes/omarchy/omarchy.script"
    fi

    # Trigger background monitor right when encryptssh initiates
    if [[ -f "${BUILDROOT}/hooks/encryptssh" ]]; then
        sed -i 's/--prompt="A password is required to access the \${cryptname} volume"/--prompt="Enter password or remote unlock via SSH (LAN or Tailscale)"/' "${BUILDROOT}/hooks/encryptssh"
        sed -i '/run_hook ()/a \ \ \ \ ( [ -x /hooks/remote-unlock ] && /hooks/remote-unlock ) 2>/dev/null || true' "${BUILDROOT}/hooks/encryptssh"
    fi

    add_runscript
}
help() {
    echo "Provides visual Plymouth debug overlay, resilient cryptsetup_shell, and remote-unlock helpers."
}
EOF
    chmod +x "${HOOK_REMOTE_UNLOCK_RUN}" "${HOOK_REMOTE_UNLOCK_INSTALL}"
    printf "${GREEN}[✓] هوک بصری و اصلاحی با موفقیت ثبت شد.${NC}\n"
}

# Setup SDDM Autologin guard
setup_autologin_guard() {
    printf "${CYAN}▷ تنظیم سرویس جلوگیری از لاگین خودکار در ورود ریموت...${NC}\n"
    mkdir -p "$(dirname "${AUTOLOGIN_SERVICE}")"
    cat > "${AUTOLOGIN_SERVICE}" << 'EOF'
[Unit]
Description=Skip SDDM Autologin After Remote LUKS Unlock
ConditionPathExists=/run/luks-remote-unlock
ConditionPathExists=/etc/sddm.conf.d/autologin.conf
Before=display-manager.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/mount --bind /dev/null /etc/sddm.conf.d/autologin.conf

[Install]
WantedBy=graphical.target
EOF
    systemctl daemon-reload
    systemctl enable remote-unlock-no-autologin.service 2>/dev/null || true
    printf "${GREEN}[✓] سرویس محافظتی فعال شد.${NC}\n"
}

# Pacman hook for tailscale UKI rebuild
setup_pacman_hook() {
    if pacman -Q mkinitcpio-tailscale >/dev/null 2>&1; then
        mkdir -p "$(dirname "${PACMAN_HOOK}")"
        cat > "${PACMAN_HOOK}" << 'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = tailscale

[Action]
Description = Rebuilding UKI boot images for bundled tailscaled...
When = PostTransaction
Exec = /usr/bin/limine-mkinitcpio
EOF
    fi
}

# Rebuild UKI
rebuild_boot_image() {
    printf "\n${YELLOW}▷ در حال بازسازی تصویر بوت (UKI) با limine-mkinitcpio...${NC}\n"
    if command -v limine-mkinitcpio >/dev/null 2>&1; then
        limine-mkinitcpio
    else
        mkinitcpio -P
    fi
    printf "${GREEN}[✓] تصویر بوت با موفقیت بازسازی شد.${NC}\n"
}

# Clean Uninstall
uninstall() {
    printf "${YELLOW}▷ در حال حذف کامل تمام فایل‌ها و دراپ‌این‌های سفارشی...${NC}\n"

    systemctl disable remote-unlock-no-autologin.service 2>/dev/null || true
    rm -f "${AUTOLOGIN_SERVICE}"
    rm -f "${HOOKS_CONF}" /etc/mkinitcpio.conf.d/99-earlyboot-unlock.conf
    rm -f "${MODULES_CONF}" /etc/mkinitcpio.conf.d/99-earlyboot-driver.conf
    rm -f "${LIMINE_CONF}" /etc/limine-entry-tool.d/99-earlyboot-unlock.conf
    rm -f "${HOOK_REMOTE_UNLOCK_INSTALL}"
    rm -f "${HOOK_REMOTE_UNLOCK_RUN}"
    rm -f /etc/initcpio/hooks/tinyssh
    rm -f "${PACMAN_HOOK}"
    rm -rf "${TINYSSH_DIR}"

    systemctl daemon-reload
    printf "${GREEN}[✓] کلیه دراپ‌این‌ها و تنظیمات اختصاصی پاک شدند.${NC}\n"

    rebuild_boot_image
    printf "\n${GREEN}================================================================${NC}\n"
    printf "${GREEN}✓ سیستم ۱۰۰٪ به تنظیمات اولیه کارخانه‌ای Omarchy بازگردانده شد.${NC}\n"
    printf "${GREEN}================================================================${NC}\n"
}

# Main installer flow
main() {
    check_root
    detect_profile

    case "${1:-}" in
        --uninstall|-u)
            uninstall
            exit 0
            ;;
        --help|-h)
            printf "Usage: sudo %s [OPTION]\n" "$0"
            printf "  --install, -i       Install or update Early-Boot Remote Unlock (Interactive)\n"
            printf "  --uninstall, -u     100%% clean uninstall and restore Omarchy defaults\n"
            exit 0
            ;;
    esac

    show_banner

    printf "${WHITE}روش آنلاک از راه دور را انتخاب کنید:${NC}\n"
    printf "  ${GREEN}1)${NC} متد استاندارد شبکه محلی با TinySSH (پیش‌فرض LAN مودم)\n"
    printf "  ${GREEN}2)${NC} متد Tailscale SSH (برای باز کردن ایمن دیسک از بستر اینترنت)\n"
    printf "  ${GREEN}3)${NC} متد ترکیبی هوشمند (هم‌زمان TinySSH روی پورت %s و Tailscale)\n" "${SSH_PORT}"
    printf "انتخاب شما [1-3] (پیش‌فرض 3 - ترکیبی): "
    read -r method_choice
    method_choice="${method_choice:-3}"

    # Clean up previous names if present
    rm -f /etc/mkinitcpio.conf.d/99-earlyboot-unlock.conf \
          /etc/mkinitcpio.conf.d/99-earlyboot-driver.conf \
          /etc/limine-entry-tool.d/99-earlyboot-unlock.conf 2>/dev/null || true

    local selected_mode="hybrid"
    case "$method_choice" in
        1) selected_mode="lan" ;;
        2) selected_mode="tailscale" ;;
        *) selected_mode="hybrid" ;;
    esac

    printf "\n${CYAN}▷ حالت انتخاب شده: ${WHITE}%s${NC}\n\n" "${selected_mode}"

    install_dependencies "${selected_mode}"
    if [ "$selected_mode" = "lan" ] || [ "$selected_mode" = "hybrid" ]; then
        setup_tinyssh_keys
    fi
    setup_limine_network
    setup_network_driver
    setup_remote_unlock_hook "${selected_mode}"
    setup_mkinitcpio_hooks_dropin "${selected_mode}"
    setup_autologin_guard
    setup_pacman_hook
    rebuild_boot_image

    printf "\n${GREEN}================================================================${NC}\n"
    printf "${GREEN}✓ پیکربندی با موفقیت انجام شد!${NC}\n"
    printf "${WHITE}برای بازگردانی کامل به حالت اولیه در هر زمان: ${YELLOW}sudo %s --uninstall${NC}\n" "$0"
    printf "${GREEN}================================================================${NC}\n"
}

main "$@"
