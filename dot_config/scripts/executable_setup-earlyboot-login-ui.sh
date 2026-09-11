#!/usr/bin/env bash
# ==============================================================================
# Omarchy Early-Boot TinySSH & Plymouth Graphical Login Setup & Manager
# ==============================================================================
# Docs: ~/Notes/Tech/Linux/Early-Boot SSH/Early-Boot SSH Guide.md
# Source: ~/.local/share/chezmoi/dot_config/scripts/executable_setup-earlyboot-login-ui.sh
# Target: ~/.config/scripts/setup-earlyboot-login-ui.sh
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

HOOKS_DIR="/etc/initcpio/hooks"
INSTALL_DIR="/etc/initcpio/install"
SHELLS_DIR="/etc/initcpio/shells"
TINYSSH_DIR="/etc/tinyssh"
LIMINE_NET_CONF="/etc/limine-entry-tool.d/omarchy-network.conf"
MKINITCPIO_NET_CONF="/etc/mkinitcpio.conf.d/omarchy_network.conf"
MKINITCPIO_HOOKS_CONF="/etc/mkinitcpio.conf.d/omarchy_hooks.conf"

# Network Parameters
STATIC_IP="192.168.0.100"
GATEWAY="192.168.0.1"
NETMASK="255.255.255.0"
INTERFACE="eth0"
HOSTNAME="omarchy"
SSH_PORT="22456"

# Print Banner
show_banner() {
    clear
    printf "${GREEN}"
    cat << 'EOF'
  ___  __  __   _   ___  ___ _  ___   __
 / _ \|  \/  | /_\ | _ \/ __| || \ \ / /
| (_) | |\/| |/ _ \|   / (__| __ |\ V / 
 \___/|_|  |_/_/ \_\_|_\\___|_||_| |_|  
EOF
    printf "${NC}"
    printf "${CYAN} Early-Boot TinySSH & Plymouth Graphical Login Setup${NC}\n"
    printf "================================================================\n\n"
}

# Check root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        printf "${RED}[✗] این اسکریپت باید با دسترسی روت (sudo) اجرا شود.${NC}\n"
        exit 1
    fi
}

# Preview the expected UI
preview_ui() {
    printf "${YELLOW}▶ پیش‌نمایش صفحه مانیتور فیزیکی (Physical Monitor - Plymouth):${NC}\n"
    printf "${WHITE}┌────────────────────────────────────────────────────────────────────────────┐${NC}\n"
    printf "${WHITE}│                                                                            │${NC}\n"
    printf "${CYAN}│  Enter password or remote unlock: ssh -p %-5s root@%-15s │${NC}\n" "${SSH_PORT}" "${STATIC_IP}"
    printf "${WHITE}│                                                                            │${NC}\n"
    printf "${WHITE}│                               [ Omarchy Logo ]                             │${NC}\n"
    printf "${WHITE}│                                                                            │${NC}\n"
    printf "${WHITE}│                            🔒 [ • • • • • • • • ]                          │${NC}\n"
    printf "${WHITE}│                                                                            │${NC}\n"
    printf "${WHITE}└────────────────────────────────────────────────────────────────────────────┘${NC}\n\n"

    printf "${YELLOW}▶ پیش‌نمایش صفحه نشست SSH روی گوشی (Termux / Termius):${NC}\n"
    printf "${GREEN}"
    cat << 'EOF'
  ___  __  __   _   ___  ___ _  ___   __
 / _ \|  \/  | /_\ | _ \/ __| || \ \ / /
| (_) | |\/| |/ _ \|   / (__| __ |\ V / 
 \___/|_|  |_/_/ \_\_|_\\___|_||_| |_|  
EOF
    printf "${NC}"
    printf "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}\n"
    printf "${CYAN}│${NC}  ${WHITE}Remote Early-Boot SSH Unlock Session${NC}                      ${CYAN}│${NC}\n"
    printf "${CYAN}│${NC}  ${WHITE}Target Volume:${NC} ${YELLOW}/dev/nvme0n1p2${NC}                               ${CYAN}│${NC}\n"
    printf "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}\n\n"
}

# Check and install required packages
install_dependencies() {
    printf "${CYAN}▷ در حال بررسی و نصب بسته‌های پیش‌نیاز...${NC}\n"
    local pkgs=(tinyssh mkinitcpio-tinyssh mkinitcpio-netconf mkinitcpio-utils)
    local missing=()

    for pkg in "${pkgs[@]}"; do
        if ! pacman -Q "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        printf "${YELLOW}▷ بسته‌های مورد نیاز یافت نشدند: ${missing[*]}${NC}\n"
        printf "${CYAN}▷ در حال نصب بسته‌ها با pacman...${NC}\n"
        pacman -S --needed --noconfirm "${missing[@]}"
        printf "${GREEN}[✓] تمام بسته‌ها با موفقیت نصب شدند.${NC}\n"
    else
        printf "${GREEN}[✓] تمام بسته‌های پیش‌نیاز قبلاً نصب شده‌اند.${NC}\n"
    fi
}

# Setup TinySSH keys
setup_tinyssh_keys() {
    printf "${CYAN}▷ در حال تنظیم کلیدهای احراز هویت TinySSH...${NC}\n"
    mkdir -p "${TINYSSH_DIR}"

    local user_name="${SUDO_USER:-$USER}"
    local user_home
    user_home=$(getent passwd "${user_name}" 2>/dev/null | cut -d: -f6)
    user_home="${user_home:-$HOME}"

    if [ -f "${user_home}/.ssh/authorized_keys" ]; then
        printf "${CYAN}▷ در حال کپی کلیدهای عمومی از ${user_home}/.ssh/authorized_keys...${NC}\n"
        cp "${user_home}/.ssh/authorized_keys" "${TINYSSH_DIR}/root_key"
        chmod 600 "${TINYSSH_DIR}/root_key"
        printf "${GREEN}[✓] کلیدهای مجاز برای کاربر root در TinySSH ذخیره شد.${NC}\n"
    else
        printf "${YELLOW}[!] فایل ${user_home}/.ssh/authorized_keys یافت نشد! لطفاً کلید عمومی گوشی/کلاینت را در ${TINYSSH_DIR}/root_key قرار دهید.${NC}\n"
    fi

    # Host keys
    if [ ! -d "${TINYSSH_DIR}/sshkeydir" ] || [ -z "$(ls -A "${TINYSSH_DIR}/sshkeydir" 2>/dev/null)" ]; then
        printf "${CYAN}▷ در حال ساخت کلیدهای هاست TinySSH...${NC}\n"
        tinysshd-makekey "${TINYSSH_DIR}/sshkeydir" 2>/dev/null || true
        printf "${GREEN}[✓] کلیدهای سرور TinySSH ایجاد شدند.${NC}\n"
    fi
}

# Configure Kernel network cmdline for Limine UKI
setup_limine_cmdline() {
    printf "${CYAN}▷ در حال تنظیم پارامتر شبکه در ${LIMINE_NET_CONF}...${NC}\n"
    mkdir -p "$(dirname "${LIMINE_NET_CONF}")"
    cat > "${LIMINE_NET_CONF}" << EOF
# Omarchy early-boot static network configuration for TinySSH
KERNEL_CMDLINE[default]+=" ip=${STATIC_IP}::${GATEWAY}:${NETMASK}:${HOSTNAME}:${INTERFACE}:none"
EOF
    printf "${GREEN}[✓] پارامتر شبکه برای ساخت UKI Limine ثبت شد.${NC}\n"
}

# Configure network driver in mkinitcpio
setup_mkinitcpio_network_module() {
    printf "${CYAN}▷ در حال افزودن درایور شبکه r8169 در ${MKINITCPIO_NET_CONF}...${NC}\n"
    mkdir -p "$(dirname "${MKINITCPIO_NET_CONF}")"
    cat > "${MKINITCPIO_NET_CONF}" << 'EOF'
# Load Realtek Ethernet network driver in early-boot
MODULES+=(r8169)
EOF
    printf "${GREEN}[✓] ماژول r8169 به تنظیمات mkinitcpio اضافه شد.${NC}\n"
}

# Configure Hooks in omarchy_hooks.conf
setup_mkinitcpio_hooks() {
    printf "${CYAN}▷ در حال به‌روزرسانی هوک‌ها در ${MKINITCPIO_HOOKS_CONF}...${NC}\n"
    if [ -f "${MKINITCPIO_HOOKS_CONF}" ]; then
        if [ ! -f "${MKINITCPIO_HOOKS_CONF}.bak" ]; then
            cp "${MKINITCPIO_HOOKS_CONF}" "${MKINITCPIO_HOOKS_CONF}.bak"
            printf "${YELLOW}▷ نسخه پشتیبان در ${MKINITCPIO_HOOKS_CONF}.bak ذخیره شد.${NC}\n"
        fi

        # Update the HOOKS line with netconf tinyssh and encryptssh
        sed -i 's|^HOOKS=(.*)|HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont netconf tinyssh block encryptssh filesystems fsck btrfs-overlayfs)|' "${MKINITCPIO_HOOKS_CONF}"
        printf "${GREEN}[✓] هوک‌های netconf، tinyssh و encryptssh در ${MKINITCPIO_HOOKS_CONF} تنظیم شدند.${NC}\n"
    else
        printf "${RED}[✗] فایل ${MKINITCPIO_HOOKS_CONF} یافت نشد!${NC}\n"
        exit 1
    fi
}

# Install custom hook files
install_hook_files() {
    printf "${CYAN}▷ در حال ایجاد دایرکتوری‌های مقصد در /etc/initcpio...${NC}\n"
    mkdir -p "${HOOKS_DIR}" "${INSTALL_DIR}" "${SHELLS_DIR}"

    # 1. cryptsetup_shell
    printf "${CYAN}▷ در حال ایجاد اسکریپت شل SSH (/etc/initcpio/shells/cryptsetup_shell)...${NC}\n"
    cat > "${SHELLS_DIR}/cryptsetup_shell" << 'EOF'
#!/bin/sh
clear
printf "\033[1;32m"
cat << 'BANNER'
  ___  __  __   _   ___  ___ _  ___   __
 / _ \|  \/  | /_\ | _ \/ __| || \ \ / /
| (_) | |\/| |/ _ \|   / (__| __ |\ V / 
 \___/|_|  |_/_/ \_\_|_\\___|_||_| |_|  
BANNER
printf "\033[0m"
printf "\033[1;36m┌─────────────────────────────────────────────────────────────┐\033[0m\n"
printf "\033[1;36m│\033[0m  \033[1;37mRemote Early-Boot SSH Unlock Session\033[0m                      \033[1;36m│\033[0m\n"
printf "\033[1;36m│\033[0m  \033[1;37mTarget Volume:\033[0m \033[1;33m%-43s\033[0m \033[1;36m│\033[0m\n" "`cat /.cryptdev 2>/dev/null`"
printf "\033[1;36m└─────────────────────────────────────────────────────────────┘\033[0m\n\n"

if [ -c "/dev/mapper/control" ]; then
    if eval cryptsetup open --type luks `cat /.cryptdev` `cat /.cryptname` `cat /.cryptargs` ; then
        echo > /.done
        printf "\n\033[1;32m[✓] Decryption successful! Continuing boot process...\033[0m\n\n"
        if command -v plymouth >/dev/null 2>&1 && plymouth --ping 2>/dev/null; then
            plymouth display-message --text="[OK] Unlocked remotely via SSH! Continuing boot..." 2>/dev/null || true
            pkill -x plymouth 2>/dev/null || true
        fi
    else
        printf "\n\033[1;31m[✗] Invalid passphrase.\033[0m\n\n"
    fi
else
    echo "Encryption bootup not succeeded. please wait!"
fi
EOF
    chmod +x "${SHELLS_DIR}/cryptsetup_shell"

    # 2. hooks/tinyssh (Custom port wrapper for tinyssh)
    printf "${CYAN}▷ در حال ایجاد هوک سفارشی TinySSH با پورت ${SSH_PORT} (/etc/initcpio/hooks/tinyssh)...${NC}\n"
    cat > "${HOOKS_DIR}/tinyssh" << EOF
#!/usr/bin/ash

run_hook ()
{
  [ -d /dev/pts ] || mkdir -p /dev/pts
  mount -t devpts devpts /dev/pts

  echo "Starting tinyssh on port ${SSH_PORT}"
  /bin/tcpsvd 0 ${SSH_PORT} /usr/sbin/tinysshd -v /etc/tinyssh/sshkeydir &
}

run_cleanuphook ()
{
    umount /dev/pts
    rm -R /dev/pts
    killall tcpsvd 2>/dev/null || true
}
EOF

    # 3. hooks/encryptssh
    printf "${CYAN}▷ در حال ایجاد هوک گرافیکی و SSH (/etc/initcpio/hooks/encryptssh)...${NC}\n"
    cat > "${HOOKS_DIR}/encryptssh" << EOF
#!/usr/bin/ash

run_hook ()
{
    /sbin/modprobe -a -q dm-crypt >/dev/null 2>&1
    [ "\${quiet}" = "y" ] && CSQUIET=">/dev/null"

    ckeyfile="/crypto_keyfile.bin"
    if [ -n "\$cryptkey" ]; then
        IFS=: read ckdev ckarg1 ckarg2 <<EOF2
\$cryptkey
EOF2
        if [ "\$ckdev" = "rootfs" ]; then
            ckeyfile=\$ckarg1
        elif resolved=\$(resolve_device "\${ckdev}" \${rootdelay}); then
            case \${ckarg1} in
                *[!0-9]*)
                    mkdir /ckey
                    mount -r -t "\$ckarg1" "\$resolved" /ckey
                    dd if="/ckey/\$ckarg2" of="\$ckeyfile" >/dev/null 2>&1
                    umount /ckey
                    ;;
                *)
                    dd if="\$resolved" of="\$ckeyfile" bs=1 skip="\$ckarg1" count="\$ckarg2" >/dev/null 2>&1
                    ;;
            esac
        fi
        [ ! -f "\${ckeyfile}" ] && echo "Keyfile could not be opened. Reverting to passphrase."
    fi

    if [ -n "\${cryptdevice}" ]; then
        DEPRECATED_CRYPT=0
        IFS=: read cryptdev cryptname cryptoptions <<EOF2
\$cryptdevice
EOF2
    else
        DEPRECATED_CRYPT=1
        cryptdev="\${root}"
        cryptname="root"
    fi

    if [ -b "/dev/mapper/\${cryptname}" ]; then
        return 0
    fi

    set -f
    OLDIFS="\$IFS"; IFS=,
    for cryptopt in \${cryptoptions}; do
        case \${cryptopt} in
            allow-discards|discard)
                cryptargs="\${cryptargs} --allow-discards"
                ;;
            no-read-workqueue|perf-no_read_workqueue)
                cryptargs="\${cryptargs} --perf-no_read_workqueue"
                ;;
            no-write-workqueue|perf-no_write_workqueue)
                cryptargs="\${cryptargs} --perf-no_write_workqueue"
                ;;
            sector-size=*)
                cryptargs="\${cryptargs} --sector-size \${cryptopt#*=}"
                ;;
            *)
                echo "Encryption option '\${cryptopt}' not known, ignoring." >&2
                ;;
        esac
    done
    set +f
    IFS="\$OLDIFS"
    unset OLDIFS

    echo "\${cryptname}" > /.cryptname
    echo "\${cryptargs}" > /.cryptargs

    if resolved=\$(resolve_device "\${cryptdev}" \${rootdelay}); then
        echo "\${resolved}" > /.cryptdev

        if cryptsetup isLuks "\${resolved}" >/dev/null 2>&1; then
            dopassphrase=1
            if [ -f "\${ckeyfile}" ]; then
                if eval cryptsetup --key-file "\${ckeyfile}" open --type luks "\${resolved}" "\${cryptname}" \${cryptargs} \${CSQUIET}; then
                    dopassphrase=0
                fi
            fi

            if [ \${dopassphrase} -gt 0 ]; then
                local my_ip="192.168.0.100"
                if [ -f /ip_opts ]; then
                    . /ip_opts
                    [ -n "\${address}" ] && my_ip="\${address}"
                fi

                # Plymouth GUI Handling (Option 3 - Native Minimal Overlay)
                if command -v plymouth >/dev/null 2>&1 && plymouth --ping 2>/dev/null; then
                    plymouth display-message --text="Enter password or remote unlock via SSH: ssh -p ${SSH_PORT} root@\${my_ip}" 2>/dev/null || true

                    plymouth ask-for-password \\
                        --prompt="Passphrase for \${cryptname} (\${resolved})" \\
                        --command="cryptsetup open --type luks --key-file=- \${resolved} \${cryptname} \${cryptargs} \${CSQUIET}" &
                    plymouth_pid=\$!

                    while [ ! -e "/dev/mapper/\${cryptname}" ]; do
                        if ! kill -0 "\$plymouth_pid" 2>/dev/null; then
                            wait "\$plymouth_pid" 2>/dev/null || true
                            [ -e "/dev/mapper/\${cryptname}" ] && break

                            if [ ! -e "/dev/mapper/\${cryptname}" ] && plymouth --ping 2>/dev/null; then
                                plymouth ask-for-password \\
                                    --prompt="Passphrase for \${cryptname} (\${resolved})" \\
                                    --command="cryptsetup open --type luks --key-file=- \${resolved} \${cryptname} \${cryptargs} \${CSQUIET}" &
                                plymouth_pid=\$!
                            fi
                        fi

                        if [ -e "/dev/mapper/\${cryptname}" ]; then
                            kill "\$plymouth_pid" 2>/dev/null || true
                            break
                        fi
                        sleep 0.5
                    done
                else
                    # Fallback ANSI TTY if Plymouth is inactive
                    printf "\033[2J\033[H"
                    printf "\033[1;32m"
                    cat << 'BANNER'
  ___  __  __   _   ___  ___ _  ___   __
 / _ \|  \/  | /_\ | _ \/ __| || \ \ / /
| (_) | |\/| |/ _ \|   / (__| __ |\ V / 
 \___/|_|  |_/_/ \_\_|_\\___|_||_| |_|  
BANNER
                    printf "\033[0m"
                    printf "\033[1;36m┌─────────────────────────────────────────────────────────────┐\033[0m\n"
                    printf "\033[1;36m│\033[0m  \033[1;37mSystem:\033[0m  Omarchy Linux (LUKS2 Encrypted)                    \033[1;36m│\033[0m\n"
                    printf "\033[1;36m│\033[0m  \033[1;37mNetwork:\033[0m IP: \033[1;32m%-15s\033[0m Port: \033[1;33m%-5s\033[0m (TinySSH Active) \033[1;36m│\033[0m\n" "\$my_ip" "${SSH_PORT}"
                    printf "\033[1;36m│\033[0m  \033[1;37mRemote:\033[0m  \033[1;35mssh -p %-5s root@%-15s\033[0m          \033[1;36m│\033[0m\n" "${SSH_PORT}" "\$my_ip"
                    printf "\033[1;36m└─────────────────────────────────────────────────────────────┘\033[0m\n\n"
                    printf "\033[1;37m[🔒] Enter passphrase for \033[1;33m%s\033[0m:\033[0m\n" "\$resolved"

                    while ! eval cryptsetup open --type luks "\${resolved}" "\${cryptname}" \${cryptargs} \${CSQUIET}; do
                        if [ -f /.done ] || [ -e "/dev/mapper/\${cryptname}" ]; then
                            printf "\n\033[1;32m[✓] Unlocked remotely via SSH! Continuing boot...\033[0m\n"
                            break
                        fi
                        printf "\n\033[1;31m[✗] Invalid passphrase. Please try again:\033[0m\n"
                        sleep 1
                    done
                fi

                [ -f /.done ] && rm -f /.done
                [ -f /.cryptdev ] && rm -f /.cryptdev
                [ -f /.cryptname ] && rm -f /.cryptname
                [ -f /.cryptargs ] && rm -f /.cryptargs
            fi

            if [ -e "/dev/mapper/\${cryptname}" ]; then
                [ \${DEPRECATED_CRYPT} -eq 1 ] && export root="/dev/mapper/root"
            else
                err "Password succeeded, but \${cryptname} creation failed, aborting..."
                return 1
            fi
        fi
    fi
    rm -f "\${ckeyfile}"
}
EOF

    # 4. install/encryptssh
    printf "${CYAN}▷ در حال ایجاد فایل نصب هوک (/etc/initcpio/install/encryptssh)...${NC}\n"
    cat > "${INSTALL_DIR}/encryptssh" << 'EOF'
#!/bin/bash
make_etc_passwd() {
    echo 'root:x:0:0:root:/root:/bin/cryptsetup_shell' > "${BUILDROOT}"/etc/passwd
    echo '/bin/cryptsetup_shell' > "${BUILDROOT}"/etc/shells
}

build() {
    local mod

    add_module 'dm-crypt'
    add_module 'dm-integrity'
    if [[ $CRYPTO_MODULES ]]; then
        for mod in $CRYPTO_MODULES; do
            add_module "$mod"
        done
    else
        add_all_modules '/crypto/'
    fi

    add_binary "cryptsetup"
    add_binary "/usr/lib/libgcc_s.so.1"
    add_binary "/etc/initcpio/shells/cryptsetup_shell" "/bin/cryptsetup_shell"

    map add_udev_rule \
        '10-dm.rules' \
        '13-dm-disk.rules' \
        '95-dm-notify.rules'

    make_etc_passwd
    add_runscript
}

help() {
    cat <<HELPEOF
Enhanced styled early-boot encryptssh hook for Omarchy Linux with TinySSH and Plymouth support.
HELPEOF
}
EOF

    printf "${GREEN}[✓] تمام فایل‌های سفارشی با موفقیت در /etc/initcpio قرار گرفتند.${NC}\n\n"
}

# Backup working UKI before rebuild
backup_current_uki() {
    local efi_dir="/boot/EFI/Linux"
    if [ -d "$efi_dir" ]; then
        printf "${CYAN}▷ در حال بررسی و تهیه نسخه پشتیبان از UKI جاری در ${efi_dir}...${NC}\n"
        for uki in "${efi_dir}"/*.efi; do
            if [ -f "$uki" ] && [[ "$uki" != *"backup"* ]] && [[ "$uki" != *"rescue"* ]]; then
                cp "$uki" "${uki}.rescue_bak"
                printf "${GREEN}[✓] نسخه پشتیبان نجات ایجاد شد: ${uki}.rescue_bak${NC}\n"
            fi
        done
    fi
}

# Rebuild initramfs
rebuild_initramfs() {
    printf "${YELLOW}▷ آیا مایلید اکنون تصویر بوت (Initramfs) بازتولید شود؟ [Y/n]: ${NC}"
    read -r response
    response=${response:-Y}
    if [[ "$response" =~ ^[Yy]$ ]]; then
        backup_current_uki
        printf "${CYAN}▷ در حال اجرای بازتولید ایمیج بوت با limine-mkinitcpio...${NC}\n"
        if command -v limine-mkinitcpio >/dev/null 2>&1; then
            limine-mkinitcpio
        else
            mkinitcpio -P
        fi
        printf "${GREEN}[✓] ایمیج بوت با موفقیت بازسازی شد!${NC}\n"
    else
        printf "${YELLOW}[!] لطفاً در زمان مناسب با دستور 'sudo limine-mkinitcpio' یا 'sudo mkinitcpio -P' ایمیج بوت را بازسازی کنید.${NC}\n"
    fi
}

# Uninstall / Restore
uninstall_ui() {
    printf "${YELLOW}▷ در حال حذف فایل‌های سفارشی و بازگردانی تنظیمات پیش‌فرض...${NC}\n"
    rm -f "${HOOKS_DIR}/numlock"
    rm -f "${INSTALL_DIR}/numlock"
    rm -f "${HOOKS_DIR}/tinyssh"
    rm -f "${HOOKS_DIR}/encryptssh"
    rm -f "${INSTALL_DIR}/encryptssh"
    rm -rf "${SHELLS_DIR}"
    rm -f "${LIMINE_NET_CONF}"
    rm -f "${MKINITCPIO_NET_CONF}"

    if [ -f "${MKINITCPIO_HOOKS_CONF}.bak" ]; then
        mv "${MKINITCPIO_HOOKS_CONF}.bak" "${MKINITCPIO_HOOKS_CONF}"
        printf "${GREEN}[✓] فایل ${MKINITCPIO_HOOKS_CONF} از نسخه پشتیبان بازگردانی شد.${NC}\n"
    else
        sed -i 's|netconf tinyssh block encryptssh|block encrypt|' "${MKINITCPIO_HOOKS_CONF}" 2>/dev/null || true
    fi

    printf "${GREEN}[✓] سیستم به تنظیمات استاندارد Omarchy بازگشت.${NC}\n\n"
    rebuild_initramfs
}

# Main Execution Flow
main() {
    check_root
    show_banner

    if [ "${1:-}" = "--uninstall" ] || [ "${1:-}" = "-u" ]; then
        uninstall_ui
        exit 0
    fi

    preview_ui

    printf "${WHITE}این اسکریپت سرویس TinySSH را فعال کرده و صفحه ورود رمز پشت مانیتور را با رابط گرافیکی Plymouth و نمایش آی‌پی و پورت اتصال هماهنگ می‌کند.${NC}\n\n"
    printf "${GREEN}آیا مایل به اعمال این تغییرات هستید؟ [Y/n]: ${NC}"
    read -r confirm
    confirm=${confirm:-Y}

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        printf "${RED}[!] عملیات لغو شد.${NC}\n"
        exit 0
    fi

    printf "\n"
    install_dependencies
    setup_tinyssh_keys
    setup_limine_cmdline
    setup_mkinitcpio_network_module
    setup_mkinitcpio_hooks
    install_hook_files
    rebuild_initramfs

    printf "\n${GREEN}================================================================${NC}\n"
    printf "${GREEN}✓ عملیات با موفقیت به پایان رسید!${NC}\n"
    printf "${WHITE}برای بازگردانی به حالت پیش‌فرض در آینده: ${YELLOW}sudo ./setup-earlyboot-login-ui.sh --uninstall${NC}\n"
    printf "${GREEN}================================================================${NC}\n"
}

main "$@"
