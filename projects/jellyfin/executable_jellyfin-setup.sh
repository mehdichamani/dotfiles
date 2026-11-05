#!/usr/bin/env bash
# ==============================================================================
# Jellyfin Automated Manager & Setup Wizard
# ==============================================================================
# مدیریت خودکار کانتینر Jellyfin، ولوم‌های استوریج و گارد امنیتی Udev
# ==============================================================================
set -e

# رنگ‌ها و استایل‌ها
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
BOLD="\033[1m"
RESET="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

IMAGE_NAME="jellyfin/jellyfin:latest"
DRIVE_LABEL="TUF_Data"
FALLBACK_MOUNT="/run/media/${USER:-unreal}/${DRIVE_LABEL}"
PROXY_PORT=10808
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

# مسیرهای گارد سیستمی Udev
UDEV_RULE_FILE="/etc/udev/rules.d/99-jellyfin-tuf-guard.rules"
GUARD_TRIGGER_SCRIPT="/usr/local/bin/jellyfin-drive-guard.sh"
JELLYFIN_SCRIPT="${SCRIPT_DIR}/jellyfin-setup.sh"

log_info()    { echo -e "${BLUE}[*]${RESET} $1"; }
log_success() { echo -e "${GREEN}[✓]${RESET} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${RESET} $1"; }
log_error()   { echo -e "${RED}[-]${RESET} $1"; }

ask_confirm() {
    local prompt_msg="$1"
    local default_ans="${2:-y}"
    local prompt_suffix="[Y/n]"
    [ "$default_ans" = "n" ] && prompt_suffix="[y/N]"

    echo -ne "${CYAN}${BOLD}? ${prompt_msg} ${prompt_suffix}: ${RESET}"
    read -r user_choice
    user_choice="${user_choice:-$default_ans}"
    case "$user_choice" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

print_header() {
    echo -e "${BOLD}${CYAN}======================================================${RESET}"
    echo -e "${BOLD}${CYAN}          🎬 Jellyfin Automated Setup & Guard          ${RESET}"
    echo -e "${BOLD}${CYAN}======================================================${RESET}"
    echo ""
}

# ------------------------------------------------------------------------------
# 1. مدیریت داکر و دسترسی‌ها
# ------------------------------------------------------------------------------
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "دستور docker یافت نشد! لطفاً Docker را نصب کنید."
        exit 1
    fi

    if docker info &> /dev/null; then
        DOCKER_CMD="docker"
    else
        log_warn "دسترسی مستقیم کاربر به داکر برقرار نیست."
        if sudo docker info &> /dev/null; then
            DOCKER_CMD="sudo docker"
            log_info "اجرا با دسترسی sudo داکر ادامه خواهد یافت."
        else
            log_error "سرویس داکر در حال اجرا نیست."
            exit 1
        fi
    fi

    if ! $DOCKER_CMD compose version &> /dev/null; then
        log_error "پلاگین docker compose یافت نشد."
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# 2. تشخیص پویا و اعتبارسنجی مانت استوریج
# ------------------------------------------------------------------------------
resolve_storage_mount() {
    local detected_mount
    detected_mount=$(findmnt -rn -S "LABEL=${DRIVE_LABEL}" -o TARGET 2>/dev/null | head -n1 || true)

    if [ -n "$detected_mount" ] && [ -d "$detected_mount" ]; then
        MEDIA_MOUNT="$detected_mount"
        return 0
    elif [ -d "$FALLBACK_MOUNT" ] && mountpoint -q "$FALLBACK_MOUNT"; then
        MEDIA_MOUNT="$FALLBACK_MOUNT"
        return 0
    fi

    MEDIA_MOUNT=""
    return 1
}

mount_storage_action() {
    log_info "جستجوی پارتیشن با برچسب '${DRIVE_LABEL}'..."
    local dev_part
    dev_part=$(lsblk -rn -o NAME,LABEL | awk -v lbl="$DRIVE_LABEL" '$2==lbl {print "/dev/"$1}' | head -n1)

    if [ -z "$dev_part" ]; then
        log_error "پارتیشن با برچسب '${DRIVE_LABEL}' روی سیستم یافت نشد. آیا هارد اکسترنال متصل است؟"
        return 1
    fi

    log_info "تلاش برای مانت ${dev_part} از طریق udisksctl..."
    if command -v udisksctl &>/dev/null; then
        if udisksctl mount -b "$dev_part"; then
            log_success "پارتیشن با موفقیت مانت شد."
            resolve_storage_mount
            return 0
        fi
    fi

    log_warn "مانت خودکار با خطا مواجه شد. تلاش با sudo mount..."
    sudo mkdir -p "$FALLBACK_MOUNT"
    if sudo mount "$dev_part" "$FALLBACK_MOUNT"; then
        log_success "پارتیشن روی ${FALLBACK_MOUNT} مانت شد."
        MEDIA_MOUNT="$FALLBACK_MOUNT"
        return 0
    fi

    log_error "امکان مانت پارتیشن وجود ندارد."
    return 1
}

check_storage_and_media() {
    log_info "بررسی وضعیت هارد مدیا (${DRIVE_LABEL})..."

    if ! resolve_storage_mount; then
        log_warn "هارد مدیا با برچسب '${DRIVE_LABEL}' مانت نیست!"
        if ask_confirm "آیا مایلید هارد اکنون مانت شود؟" "y"; then
            mount_storage_action || exit 1
        else
            log_error "بدون اتصال هارد مدیا، راه‌اندازی Jellyfin امکان‌پذیر نیست."
            exit 1
        fi
    fi

    log_success "هارد در مسیر ${MEDIA_MOUNT} متصل و آماده است."

    # اعتبارسنجی و آماده‌سازی دایرکتوری‌های دیتا
    for dir in "${MEDIA_MOUNT}/jellyfin_data/config" \
               "${MEDIA_MOUNT}/jellyfin_data/cache" \
               "${MEDIA_MOUNT}/media" \
               "${MEDIA_MOUNT}/media_archive"; do
        if [ ! -d "$dir" ]; then
            log_warn "پوشه $dir یافت نشد."
            if ask_confirm "آیا پوشه ایجاد شود؟" "y"; then
                mkdir -p "$dir"
                log_success "پوشه ایجاد شد: $dir"
            fi
        fi
    done
}

# ------------------------------------------------------------------------------
# 3. پیکربندی گروه سخت‌افزاری گرافیک (VA-API / Render)
# ------------------------------------------------------------------------------
get_system_proxy_info() {
    local proxy_file="${HOME}/.config/proxy_state"
    local raw_url=""
    if [ -s "$proxy_file" ]; then
        raw_url=$(cat "$proxy_file" 2>/dev/null | tr -d '[:space:]')
    fi

    if [ -z "$raw_url" ]; then
        echo ""
        return 0
    fi

    local port
    port=$(python3 -c "
import urllib.parse
u = urllib.parse.urlparse('$raw_url')
print(u.port or '')
" 2>/dev/null || true)

    if [ -n "$port" ]; then
        echo "http://host.docker.internal:${port}"
    else
        echo "$raw_url"
    fi
}

configure_environment() {
    log_info "پیکربندی محیط و متغیرهای داینامیک (.env)..."
    local r_gid v_gid
    r_gid=$(getent group render | cut -d: -f3 || true)
    v_gid=$(getent group video | cut -d: -f3 || true)

    r_gid=${r_gid:-987}
    v_gid=${v_gid:-983}

    local storage_root="${MEDIA_MOUNT:-$FALLBACK_MOUNT}"
    local env_file="${SCRIPT_DIR}/.env"
    local container_proxy
    container_proxy=$(get_system_proxy_info)

    cat > "$env_file" <<EOF
# Jellyfin Dynamic Local Environment (Auto-generated by jellyfin-setup.sh)
RENDER_GID=${r_gid}
VIDEO_GID=${v_gid}
JELLYFIN_STORAGE_ROOT=${storage_root}
JELLYFIN_MEDIA_DIR=${storage_root}/media
JELLYFIN_ARCHIVE_DIR=${storage_root}/media_archive
JELLYFIN_HTTP_PROXY=${container_proxy}
JELLYFIN_HTTPS_PROXY=${container_proxy}
EOF

    log_success "فایل .env به صورت خودکار با مسیر هارد (${storage_root})، پروکسی و GIDهای گرافیک هماهنگ شد."
}

# ------------------------------------------------------------------------------
# 4. بارگذاری و ذخیره آفلاین ایمیج داکر
# ------------------------------------------------------------------------------
get_backup_image_path() {
    if resolve_storage_mount; then
        echo "${MEDIA_MOUNT}/Programs/docker-images/jellyfin-latest.tar"
    else
        echo "${FALLBACK_MOUNT}/Programs/docker-images/jellyfin-latest.tar"
    fi
}

load_offline_image() {
    local img_path
    img_path=$(get_backup_image_path)

    if [ ! -f "$img_path" ]; then
        log_error "فایل بکاپ ایمیج یافت نشد: $img_path"
        return 1
    fi

    log_info "بارگذاری ایمیج از: $img_path"
    if command -v pv &> /dev/null; then
        pv -N "Load Image" "$img_path" | $DOCKER_CMD load
    else
        $DOCKER_CMD load -i "$img_path"
    fi
    log_success "ایمیج با موفقیت بارگذاری شد."
}

save_offline_image() {
    local img_path
    img_path=$(get_backup_image_path)
    local img_dir
    img_dir="$(dirname "$img_path")"

    if ! resolve_storage_mount; then
        log_error "هارد اکسترنال متصل نیست."
        return 1
    fi

    mkdir -p "$img_dir"

    if ! $DOCKER_CMD image inspect "${IMAGE_NAME}" &> /dev/null; then
        log_error "ایمیج ${IMAGE_NAME} در داکر وجود ندارد."
        return 1
    fi

    log_info "در حال ذخیره‌سازی ایمیج در ${img_path} ..."
    if command -v pv &> /dev/null; then
        $DOCKER_CMD save "${IMAGE_NAME}" | pv -N "Save Image" > "$img_path"
    else
        $DOCKER_CMD save -o "$img_path" "${IMAGE_NAME}"
    fi
    log_success "ایمیج با موفقیت ذخیره شد."
    ls -lh "$img_path"
}

check_docker_image() {
    log_info "بررسی ایمیج داکر ${IMAGE_NAME}..."
    if ! $DOCKER_CMD image inspect "${IMAGE_NAME}" &> /dev/null; then
        log_warn "ایمیج در سیستم یافت نشد."
        local img_path
        img_path=$(get_backup_image_path)
        if [ -f "$img_path" ]; then
            if ask_confirm "آیا مایلید ایمیج از فایل آفلاین ($img_path) بارگذاری شود؟" "y"; then
                load_offline_image
                return 0
            fi
        fi

        if ask_confirm "آیا مایلید ایمیج از اینترنت (Docker Hub) دانلود شود؟" "y"; then
            $DOCKER_CMD pull "${IMAGE_NAME}"
            log_success "ایمیج دانلود شد."
        else
            log_error "ایمیج در دسترس نیست."
            exit 1
        fi
    else
        log_success "ایمیج داکر آماده است."
    fi
}

# ------------------------------------------------------------------------------
# 5. بررسی وضعیت پراکسی
# ------------------------------------------------------------------------------
check_proxy() {
    local sys_proxy_file="${HOME}/.config/proxy_state"
    if [ -s "$sys_proxy_file" ]; then
        local raw_url
        raw_url=$(cat "$sys_proxy_file" 2>/dev/null | tr -d '[:space:]')
        log_info "پراکسی سیستم فعال است: ${raw_url}"
    else
        log_warn "پراکسی سیستم خاموش یا تنظیم‌نشده است (ترافیک کانتینر مستقیم ارسال می‌شود)."
    fi
}

# ------------------------------------------------------------------------------
# 6. مدیریت سرویس (Start / Stop / Restart / Logs)
# ------------------------------------------------------------------------------
service_start() {
    check_docker
    check_storage_and_media
    configure_environment
    check_docker_image
    check_proxy

    log_info "راه‌اندازی کانتینر Jellyfin..."
    $DOCKER_CMD compose -f "$COMPOSE_FILE" up -d
    log_success "کانتینر Jellyfin فعال شد."

    local local_ip
    local_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || echo "localhost")
    echo -e "\n${BOLD}${GREEN}======================================================${RESET}"
    echo -e " 🌐 مرورگر سیستم:  ${CYAN}http://localhost:8096${RESET}"
    echo -e " 📱 شبکه داخلی:    ${CYAN}http://${local_ip}:8096${RESET}"
    echo -e "${BOLD}${GREEN}======================================================${RESET}\n"
}

service_stop() {
    check_docker
    log_info "متوقف‌سازی سریع کانتینر Jellyfin..."
    $DOCKER_CMD compose -f "$COMPOSE_FILE" stop -t 2
    log_success "کانتینر Jellyfin با موفقیت متوقف شد."
}

service_restart() {
    check_docker
    check_storage_and_media
    configure_environment
    check_proxy
    log_info "راه‌اندازی مجدد کانتینر با اعمال آخرین تنظیمات و پروکسی..."
    $DOCKER_CMD compose -f "$COMPOSE_FILE" up -d --force-recreate
    log_success "کانتینر با موفقیت به‌روزرسانی و مجدداً راه‌اندازی شد."
}

service_status() {
    check_docker
    print_header
    echo -e "${BOLD}وضعیت اجزای Jellyfin:${RESET}"

    # ۱. وضعیت کانتینر
    echo -ne " • وضعیت کانتینر داکر: "
    local c_status
    c_status=$($DOCKER_CMD ps --filter "name=jellyfin" --format "{{.Status}}" 2>/dev/null || true)
    if [ -n "$c_status" ]; then
        echo -e "${GREEN}روشن / فعال (${c_status})${RESET}"
    else
        echo -e "${YELLOW}متوقف (Offline)${RESET}"
    fi

    # ۲. وضعیت هارد
    echo -ne " • هارد مدیا (${DRIVE_LABEL}): "
    if resolve_storage_mount; then
        echo -e "${GREEN}مانت است در ${MEDIA_MOUNT}${RESET}"
    else
        echo -e "${RED}قطع / مانت نیست${RESET}"
    fi

    # ۳. بررسی وضعیت پروکسی سیستم و کانتینر
    local sys_proxy_file="${HOME}/.config/proxy_state"
    local sys_proxy="OFF"
    if [ -s "$sys_proxy_file" ]; then
        sys_proxy=$(cat "$sys_proxy_file" 2>/dev/null | tr -d '[:space:]')
    fi

    local container_proxy
    container_proxy=$($DOCKER_CMD inspect jellyfin --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | awk -F= '$1=="HTTP_PROXY" {print $2}' || true)
    container_proxy=${container_proxy:-OFF}

    echo -ne " • پروکسی سیستم: "
    if [ "$sys_proxy" != "OFF" ]; then
        echo -e "${CYAN}${sys_proxy}${RESET}"
    else
        echo -e "${YELLOW}خاموش / مستقیم${RESET}"
    fi

    echo -ne " • پروکسی کانتینر: "
    if [ "$container_proxy" != "OFF" ]; then
        echo -e "${CYAN}${container_proxy}${RESET}"
    else
        echo -e "${YELLOW}خاموش / مستقیم${RESET}"
    fi

    echo -ne " • هماهنگی پروکسی (Sync): "
    local expected_container_proxy
    expected_container_proxy=$(get_system_proxy_info)
    expected_container_proxy=${expected_container_proxy:-OFF}

    if [ "$c_status" = "" ]; then
        echo -e "${YELLOW}کانتینر خاموش است${RESET}"
    elif [ "$container_proxy" = "$expected_container_proxy" ]; then
        echo -e "${GREEN}کاملاً هماهنگ (In Sync)${RESET}"
    else
        echo -e "${RED}ناهماهنگ! (با jellyfin restart هماهنگ می‌شود)${RESET}"
    fi

    # ۴. وضعیت گارد Udev
    echo -ne " • گارد امنیتی Udev: "
    if [ -f "$UDEV_RULE_FILE" ] && [ -f "$GUARD_TRIGGER_SCRIPT" ]; then
        echo -e "${GREEN}نصب و فعال${RESET}"
    else
        echo -e "${YELLOW}غیرفعال / نصب‌نشده${RESET}"
    fi
    echo ""
}

# ------------------------------------------------------------------------------
# 7. سیستم گارد امنیتی Udev
# ------------------------------------------------------------------------------
install_guard() {
    log_info "نصب گارد محافظتی و لایف‌سایکل خودکار Udev برای هارد ${DRIVE_LABEL}..."
    echo "نیاز به دسترسی sudo جهت ثبت قوانین در /etc/udev/rules.d/ :"

    # ۱. ایجاد اسکریپت تریگر
    sudo tee "$GUARD_TRIGGER_SCRIPT" > /dev/null <<EOF
#!/usr/bin/env bash
# Jellyfin Hardware & Lifecycle Guard for ${DRIVE_LABEL}
ACTION_TYPE="\$1"
TARGET_USER="${USER:-unreal}"
COMPOSE_FILE="${COMPOSE_FILE}"
MOUNT_PATH="${FALLBACK_MOUNT}"

case "\$ACTION_TYPE" in
    remove)
        # در صورت قطع شدن فیزیکی هارد، کانتینر فورا متوقف و مسیر تمیز می‌شود
        systemd-run --no-block runuser -u "\$TARGET_USER" -- docker compose -f "\$COMPOSE_FILE" stop -t 2 >/dev/null 2>&1 || true
        # اگر پوشه خالی در مسیر مانت رم باقی مانده باشد آن را پاک می‌کنیم تا تداخل نام ایجاد نشود
        if [ -d "\$MOUNT_PATH" ] && ! mountpoint -q "\$MOUNT_PATH"; then
            rm -rf "\$MOUNT_PATH" >/dev/null 2>&1 || true
        fi
        ;;
    add)
        # به محض اتصال هارد، تا مانت شدن توسط سیستم منتظر مانده و سپس با اسکریپت اصلی کانتینر را استارت می‌کند
        (
            for i in {1..15}; do
                if mountpoint -q "\$MOUNT_PATH"; then
                    runuser -u "\$TARGET_USER" -- /home/\$TARGET_USER/projects/jellyfin/jellyfin-setup.sh start >/dev/null 2>&1 || true
                    break
                fi
                sleep 1
            done
        ) &
        ;;
esac
EOF
    sudo chmod +x "$GUARD_TRIGGER_SCRIPT"

    # ۲. ایجاد فایل قانون udev (پشتیبانی از حذف و اتصال هارد)
    sudo tee "$UDEV_RULE_FILE" > /dev/null <<EOF
# Omarchy / Jellyfin Hardware Lifecycle Guard for ${DRIVE_LABEL}
ACTION=="remove", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="${DRIVE_LABEL}", RUN+="${GUARD_TRIGGER_SCRIPT} remove"
ACTION=="remove", SUBSYSTEM=="block", ENV{ID_SERIAL_SHORT}=="S2D0AP043732", RUN+="${GUARD_TRIGGER_SCRIPT} remove"
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="${DRIVE_LABEL}", RUN+="${GUARD_TRIGGER_SCRIPT} add"
EOF

    # ۳. ریلود udev
    sudo udevadm control --reload
    sudo udevadm trigger --subsystem-match=block || true

    log_success "گارد و اتوماسیون Udev با موفقیت نصب و فعال شد!"
    log_info "فایل قانون: ${UDEV_RULE_FILE}"
    log_info "اسکریپت اجرا: ${GUARD_TRIGGER_SCRIPT}"
}

uninstall_guard() {
    log_info "حذف گارد محافظتی Udev..."
    if [ -f "$UDEV_RULE_FILE" ]; then
        sudo rm -f "$UDEV_RULE_FILE"
        log_success "فایل ${UDEV_RULE_FILE} حذف شد."
    fi
    if [ -f "$GUARD_TRIGGER_SCRIPT" ]; then
        sudo rm -f "$GUARD_TRIGGER_SCRIPT"
        log_success "فایل ${GUARD_TRIGGER_SCRIPT} حذف شد."
    fi
    sudo udevadm control --reload
    log_success "گارد Udev با موفقیت غیرفعال شد."
}

# ------------------------------------------------------------------------------
# 8. منوی تعاملی
# ------------------------------------------------------------------------------
interactive_menu() {
    while true; do
        echo -e "${BOLD}منوی مدیریت Jellyfin:${RESET}"
        echo "  1) بررسی کامل پیش‌نیازها و راه‌اندازی (Run Setup / Start)"
        echo "  2) مشاهده وضعیت کامل سیستم (Status)"
        echo "  3) مشاهده لاگ‌های زنده (Logs)"
        echo "  4) ری‌استارت کانتینر (Restart)"
        echo "  5) متوقف کردن کانتینر (Stop)"
        echo "  6) مانت خودکار هارد TUF_Data"
        echo "  7) نصب گارد محافظتی Udev (Hardware Safe Guard)"
        echo "  8) حذف گارد محافظتی Udev"
        echo "  9) ذخیره ایمیج فعلی داکر روی هارد (Export Image)"
        echo " 10) بارگذاری ایمیج از هارد (Import Image)"
        echo "  q) خروج"
        echo ""
        read -rp "انتخاب شما [1-10/q]: " OPTION
        case "$OPTION" in
            1) service_start ;;
            2) service_status ;;
            3) check_docker; $DOCKER_CMD compose -f "$COMPOSE_FILE" logs -f ;;
            4) service_restart ;;
            5) service_stop ;;
            6) mount_storage_action ;;
            7) install_guard ;;
            8) uninstall_guard ;;
            9) check_docker; save_offline_image ;;
            10) check_docker; load_offline_image ;;
            q|Q) echo "خداحافظ!"; exit 0 ;;
            *) echo "گزینه نامعتبر است." ;;
        esac
        echo ""
    done
}

show_help() {
    echo -e "${BOLD}${CYAN}راهنمای دستورات Jellyfin Manager (${0##*/}):${RESET}"
    echo ""
    echo -e "  ${GREEN}${0##*/} [دستور]${RESET}"
    echo ""
    echo -e "${BOLD}دستورات اصلی:${RESET}"
    echo "  start | --auto          بررسی پیش‌نیازها و راه‌اندازی کانتینر Jellyfin"
    echo "  stop                    متوقف کردن کانتینر Jellyfin"
    echo "  restart                 راه‌اندازی مجدد کانتینر Jellyfin"
    echo "  status                  نمایش وضعیت کانتینر، مانت هارد و گارد Udev"
    echo "  logs                    مشاهده لاگ‌های زنده کانتینر"
    echo ""
    echo -e "${BOLD}مدیریت دیسک و ایمیج آفلاین:${RESET}"
    echo "  mount                   مانت دستی پارتیشن هارد TUF_Data"
    echo "  save | export           ذخیره ایمیج Docker روی هارد برای استفاده آفلاین"
    echo "  load | import           بارگذاری مجدد ایمیج Docker از هارد"
    echo ""
    echo -e "${BOLD}اتوماسیون سخت‌افزار (Udev Guard):${RESET}"
    echo "  guard-install           نصب گارد خودکار udev (استاپ در خروج، استارت در اتصال)"
    echo "  guard-remove            حذف قوانین و اسکریپت گارد udev"
    echo ""
    echo -e "${BOLD}منوی تعاملی:${RESET}"
    echo "  menu | (بدون آرگومان)   ورود به منوی تعاملی شماره‌دار"
    echo "  help | -h | --help      نمایش همین راهنما"
    echo ""
}

# ------------------------------------------------------------------------------
# نقطه ورود اصلی (Entry Point)
# ------------------------------------------------------------------------------
case "${1:-}" in
    start|--auto)
        service_start
        ;;
    stop)
        service_stop
        ;;
    restart)
        service_restart
        ;;
    status)
        service_status
        ;;
    mount)
        mount_storage_action
        ;;
    guard-install|install-guard)
        install_guard
        ;;
    guard-remove|uninstall-guard)
        uninstall_guard
        ;;
    logs)
        check_docker
        $DOCKER_CMD compose -f "$COMPOSE_FILE" logs -f
        ;;
    export|save)
        check_docker
        save_offline_image
        ;;
    import|load)
        check_docker
        load_offline_image
        ;;
    help|-h|--help)
        show_help
        ;;
    menu|"")
        print_header
        interactive_menu
        ;;
    *)
        echo -e "${RED}دستور نامعتبر: $1${RESET}"
        show_help
        exit 1
        ;;
esac
