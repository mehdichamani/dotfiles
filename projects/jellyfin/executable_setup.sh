#!/usr/bin/env bash
# ==============================================================================
# Jellyfin Quick-Setup Wizard for Fresh Linux Installations
# ==============================================================================
# اسکریپت جامع و تعاملی راه‌اندازی و مدیریت کانتینر Jellyfin
# تمامی بررسی‌ها خودکار انجام شده و قبل از هر تغییر تاییدیه‌ دریافت می‌شود.
# ==============================================================================

# رنگ‌ها و استایل‌ها برای خروجی زیباتر
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
BACKUP_IMAGE_BASE="/run/media/unreal/TUF_NTFS"
BACKUP_IMAGE_DIR="${BACKUP_IMAGE_BASE}/programs/docker-images"
BACKUP_IMAGE_FILE="${BACKUP_IMAGE_DIR}/jellyfin-latest.tar"
MEDIA_MOUNT="/mnt/ssd"
SSD_UUID="46052E2B1E110A06"
PROXY_PORT=10808

log_info()    { echo -e "${BLUE}[*]${RESET} $1"; }
log_success() { echo -e "${GREEN}[✓]${RESET} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${RESET} $1"; }
log_error()   { echo -e "${RED}[-]${RESET} $1"; }

ask_confirm() {
    local prompt_msg="$1"
    local default_ans="${2:-y}" # y or n
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
    clear
    echo -e "${BOLD}${CYAN}======================================================${RESET}"
    echo -e "${BOLD}${CYAN}          🎬 Jellyfin Automated Setup Wizard          ${RESET}"
    echo -e "${BOLD}${CYAN}======================================================${RESET}"
    echo ""
}

# ------------------------------------------------------------------------------
# 1. بررسی داکر و دسترسی‌ها
# ------------------------------------------------------------------------------
check_docker() {
    log_info "بررسی وضعیت داکر..."

    if ! command -v docker &> /dev/null; then
        log_error "دستور docker یافت نشد! ابتدا Docker را روی توزیع خود نصب کنید."
        exit 1
    fi

    # بررسی فعال بودن سرویس داکر
    if ! docker info &> /dev/null; then
        log_warn "دسترسی مستقیم به داکر برقرار نیست یا دیمن داکر متوقف است."
        if ask_confirm "آیا مایلید سرویس داکر را راه‌اندازی (systemctl start docker) کنید؟" "y"; then
            sudo systemctl start docker
        fi

        if ! docker info &> /dev/null; then
            log_error "همچنان امکان ارتباط با داکر بدون sudo وجود ندارد."
            echo -e "    برای رفع دائمی: ${BOLD}sudo usermod -aG docker \$USER${RESET} و سپس یکبار خروج و ورود (Relogin)."
            if ask_confirm "آیا مایلید با sudo ادامه دهید؟" "y"; then
                DOCKER_CMD="sudo docker"
            else
                exit 1
            fi
        else
            DOCKER_CMD="docker"
            log_success "داکر با موفقیت متصل شد."
        fi
    else
        DOCKER_CMD="docker"
        log_success "داکر فعال و آماده است."
    fi

    if ! $DOCKER_CMD compose version &> /dev/null; then
        log_error "پلاگین docker compose یافت نشد. لطفاً docker-compose-plugin را نصب کنید."
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# مانت و تنظیم fstab برای دیسک مدیا
# ------------------------------------------------------------------------------
mount_storage_action() {
    # بررسی نصب بودن درایور ntfs-3g
    if ! command -v ntfs-3g &> /dev/null; then
        log_warn "درایور ntfs-3g روی سیستم شما نصب نیست!"
        if ask_confirm "آیا مایلید پکیج ntfs-3g به صورت خودکار نصب شود؟" "y"; then
            if command -v pacman &> /dev/null; then
                sudo pacman -S --needed ntfs-3g
            elif command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y ntfs-3g
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y ntfs-3g
            else
                log_error "مدیر بسته سازگار یافت نشد. لطفاً ntfs-3g را دستی نصب کنید."
            fi
        else
            log_warn "بدون درایور ntfs-3g ممکن است مانت پارتیشن‌های NTFS ناموفق باشد."
        fi
    fi

    local CURRENT_UID=${SUDO_UID:-$(id -u)}
    local CURRENT_GID=${SUDO_GID:-$(id -g)}
    local MOUNT_OPTS="defaults,nofail,uid=${CURRENT_UID},gid=${CURRENT_GID},umask=022,x-systemd.device-timeout=5s"
    local FSTAB_COMMENT="# Jellyfin Media SSD (NTFS)"
    local FSTAB_ENTRY="UUID=${SSD_UUID}\t${MEDIA_MOUNT}\tntfs-3g\t${MOUNT_OPTS}\t0 0"

    log_info "آماده‌سازی نقطه مانت: ${MEDIA_MOUNT}"
    sudo mkdir -p "${MEDIA_MOUNT}"

    if grep -q "${SSD_UUID}" /etc/fstab; then
        log_info "دیسک با شناسه UUID=${SSD_UUID} از قبل در /etc/fstab ثبت شده است."
    else
        local BACKUP_FILE="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
        sudo cp /etc/fstab "${BACKUP_FILE}"
        log_info "نسخه پشتیبان از /etc/fstab تهیه شد: ${BACKUP_FILE}"

        printf "\n%s\n%b\n" "${FSTAB_COMMENT}" "${FSTAB_ENTRY}" | sudo tee -a /etc/fstab > /dev/null
        log_success "رکورد مانت به همراه توضیحات به /etc/fstab اضافه شد."
    fi

    log_info "در حال اجرای mount -a ..."
    sudo mount -a

    if mountpoint -q "${MEDIA_MOUNT}"; then
        log_success "دیسک با موفقیت روی ${MEDIA_MOUNT} مانت شد."
    else
        log_error "دیسک در ${MEDIA_MOUNT} مانت نشد. لطفاً اتصال فیزیکی دیسک یا نصب ntfs-3g را بررسی کنید."
    fi
}

# ------------------------------------------------------------------------------
# 2. بررسی مانت هارد اینترنال (داده‌ها و مدیا)
# ------------------------------------------------------------------------------
check_storage_and_media() {
    log_info "بررسی اتصال و مانت هارد مدیا (${MEDIA_MOUNT})..."

    if ! mountpoint -q "${MEDIA_MOUNT}"; then
        log_warn "دیسک در مسیر ${MEDIA_MOUNT} مانت نشده است!"
        if ask_confirm "آیا مایلید دیسک با UUID=${SSD_UUID} به ${MEDIA_MOUNT} مانت و در fstab ثبت شود؟" "y"; then
            mount_storage_action
        fi

        if ! mountpoint -q "${MEDIA_MOUNT}"; then
            log_error "دیسک مانت نیست. اجرای Jellyfin بدون دسترسی به مدیا و کانفیگ قبلی ممکن نیست."
            if ! ask_confirm "آیا تمایل دارید بدون دیسک ادامه دهید (توصیه نمی‌شود)؟" "n"; then
                exit 1
            fi
        fi
    else
        log_success "هارد در ${MEDIA_MOUNT} مانت است."
    fi

    # بررسی وجود فولدرهای دیتای اصلی
    for dir in "${MEDIA_MOUNT}/jellyfin_data/config" "${MEDIA_MOUNT}/jellyfin_data/cache" "${MEDIA_MOUNT}/media"; do
        if [ ! -d "$dir" ]; then
            log_warn "پوشه $dir یافت نشد."
            if ask_confirm "آیا مایلید پوشه $dir ایجاد شود؟" "y"; then
                mkdir -p "$dir"
                log_success "پوشه $dir ایجاد شد."
            fi
        fi
    done
}

# ------------------------------------------------------------------------------
# 3. بررسی و تنظیم شناسه گروه‌های سخت‌افزاری GPU (Render / Video)
# ------------------------------------------------------------------------------
configure_gpu_groups() {
    log_info "تشخیص خودکار GID کارت گرافیک (VA-API / Render)..."

    RENDER_GID=$(getent group render | cut -d: -f3 || true)
    VIDEO_GID=$(getent group video | cut -d: -f3 || true)

    RENDER_GID=${RENDER_GID:-987}
    VIDEO_GID=${VIDEO_GID:-983}

    log_info "شناسه گروه‌های سیستم شما: render=${RENDER_GID}, video=${VIDEO_GID}"

    ENV_FILE=".env"
    ENV_CONTENT="RENDER_GID=${RENDER_GID}\nVIDEO_GID=${VIDEO_GID}"

    if [ ! -f "$ENV_FILE" ] || ! grep -q "RENDER_GID=${RENDER_GID}" "$ENV_FILE" 2>/dev/null; then
        if ask_confirm "آیا تنظیمات GID در فایل .env ذخیره شود؟" "y"; then
            echo -e "${ENV_CONTENT}" > "$ENV_FILE"
            log_success "فایل .env با مقادیر بهینه توزیع شما به‌روز شد."
        fi
    else
        log_success "تنظیمات GPU در .env هماهنگ است."
    fi
}

# ------------------------------------------------------------------------------
# بارگذاری / ذخیره آفلاین ایمیج
# ------------------------------------------------------------------------------
load_offline_image() {
    if [ ! -d "${BACKUP_IMAGE_BASE}" ]; then
        log_error "هارد اکسترنال در مسیر ${BACKUP_IMAGE_BASE} متصل/مانت نیست."
        return 1
    fi

    if [ ! -f "${BACKUP_IMAGE_FILE}" ]; then
        log_error "فایل ایمیج در مسیر ${BACKUP_IMAGE_FILE} یافت نشد."
        return 1
    fi

    # بررسی و پیشنهاد نصب pv برای نمایش نوار پیشرفت زنده
    if ! command -v pv &> /dev/null; then
        if ask_confirm "ابزار pv (نوار پیشرفت لود ایمیج) نصب نیست. آیا مایلید نصب شود؟" "y"; then
            if command -v pacman &> /dev/null; then
                sudo pacman -S --needed pv
            elif command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y pv
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y pv
            fi
        fi
    fi

    log_info "در حال بارگذاری ایمیج از فایل بکاپ: ${BACKUP_IMAGE_FILE}"
    if command -v pv &> /dev/null; then
        pv -N "Load Image" "${BACKUP_IMAGE_FILE}" | $DOCKER_CMD load
    else
        $DOCKER_CMD load -i "${BACKUP_IMAGE_FILE}"
    fi
    log_success "ایمیج با موفقیت بارگذاری شد."
}

save_offline_image() {
    if [ ! -d "${BACKUP_IMAGE_BASE}" ]; then
        log_error "هارد اکسترنال در مسیر ${BACKUP_IMAGE_BASE} متصل/مانت نیست."
        return 1
    fi

    mkdir -p "${BACKUP_IMAGE_DIR}"

    if ! $DOCKER_CMD image inspect "${IMAGE_NAME}" &> /dev/null; then
        log_error "ایمیج ${IMAGE_NAME} در داکر محلی یافت نشد."
        return 1
    fi

    log_info "در حال ذخیره‌سازی ایمیج ${IMAGE_NAME} به ${BACKUP_IMAGE_FILE} ..."
    if command -v pv &> /dev/null; then
        $DOCKER_CMD save "${IMAGE_NAME}" | pv -N "Save Image" > "${BACKUP_IMAGE_FILE}"
    else
        $DOCKER_CMD save -o "${BACKUP_IMAGE_FILE}" "${IMAGE_NAME}"
    fi
    log_success "ذخیره‌سازی با موفقیت انجام شد."
    ls -lh "${BACKUP_IMAGE_FILE}"
}

# ------------------------------------------------------------------------------
# 4. بررسی ایمیج داکر و لود آفلاین در صورت نیاز
# ------------------------------------------------------------------------------
check_docker_image() {
    log_info "بررسی وجود ایمیج ${IMAGE_NAME} در داکر..."

    if ! $DOCKER_CMD image inspect "${IMAGE_NAME}" &> /dev/null; then
        log_warn "ایمیج ${IMAGE_NAME} در داکر محلی یافت نشد."
        
        if [ -f "${BACKUP_IMAGE_FILE}" ]; then
            log_info "فایل بکاپ آفلاین در هارد اکسترنال شناسایی شد:"
            echo -e "    ${CYAN}${BACKUP_IMAGE_FILE}${RESET}"
            if ask_confirm "آیا مایلید ایمیج از این فایل بارگذاری (docker load) شود؟" "y"; then
                load_offline_image
            fi
        else
            log_warn "فایل آفلاین در ${BACKUP_IMAGE_FILE} یافت نشد (هارد اکسترنال متصل نیست یا مسیر تغییر کرده)."
            if ask_confirm "آیا مایلید ایمیج از اینترنت (Docker Hub) پول (Pull) شود؟" "y"; then
                $DOCKER_CMD pull "${IMAGE_NAME}"
                log_success "ایمیج با موفقیت دانلود شد."
            else
                log_error "ایمیج در دسترس نیست. نمی‌توان کانتینر را اجرا کرد."
                exit 1
            fi
        fi
    else
        log_success "ایمیج ${IMAGE_NAME} در داکر محلی موجود است."
    fi
}

# ------------------------------------------------------------------------------
# 5. بررسی پراکسی هاست (اختیاری)
# ------------------------------------------------------------------------------
check_proxy() {
    log_info "بررسی وضعیت پراکسی میزبان (پورت ${PROXY_PORT})..."
    if ss -tulpn 2>/dev/null | grep -q ":${PROXY_PORT}"; then
        log_success "پراکسی روی پورت ${PROXY_PORT} فعال و در حال شنود است."
    else
        log_warn "روی پورت ${PROXY_PORT} پراکسی فعال شناسایی نشد."
        echo -e "    (اگر برای اسکرپرها و پوسترها از پراکسی استفاده می‌کنید، بعداً نرم‌افزار پراکسی خود را با Allow LAN فعال کنید)"
    fi
}

# ------------------------------------------------------------------------------
# 6. اجرای کانتینر با Docker Compose
# ------------------------------------------------------------------------------
start_service() {
    echo ""
    log_info "همه پیش‌نیازها بررسی شدند."
    if ask_confirm "آیا مایلید کانتینر Jellyfin روشن / راه‌اندازی (docker compose up -d) شود؟" "y"; then
        $DOCKER_CMD compose up -d
        echo ""
        log_success "کانتینر Jellyfin راه‌اندازی شد!"
        
        local local_ip
        local_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || echo "localhost")

        echo -e "\n${BOLD}${GREEN}======================================================${RESET}"
        echo -e "${BOLD} 🎉 Jellyfin با موفقیت در دسترس است:${RESET}"
        echo -e " 🌐 مرورگر سیستم فعلی:  ${CYAN}http://localhost:8096${RESET}"
        echo -e " 📱 دستگاه‌های دیگر شبکه: ${CYAN}http://${local_ip}:8096${RESET}"
        echo -e "${BOLD}${GREEN}======================================================${RESET}\n"
    fi
}

# ------------------------------------------------------------------------------
# منوی مدیریت و کارهای سریع
# ------------------------------------------------------------------------------
interactive_menu() {
    while true; do
        echo -e "${BOLD}منوی مدیریت Jellyfin:${RESET}"
        echo "  1) بررسی کامل پیش‌نیازها و راه‌اندازی (Run Setup Wizard)"
        echo "  2) مشاهده لاگ‌های زنده Jellyfin (Logs)"
        echo "  3) ری‌استارت کانتینر (Restart)"
        echo "  4) متوقف کردن کانتینر (Stop)"
        echo "  5) ذخیره و بکاپ ایمیج فعلی روی هارد اکسترنال (Export Image)"
        echo "  6) بارگذاری مجدد ایمیج از هارد اکسترنال (Import Image)"
        echo "  7) مانت دستی هارد SSD و ثبت در fstab"
        echo "  q) خروج"
        echo ""
        read -rp "انتخاب شما [1-7/q]: " OPTION
        case "$OPTION" in
            1)
                check_docker
                check_storage_and_media
                configure_gpu_groups
                check_docker_image
                check_proxy
                start_service
                ;;
            2)
                $DOCKER_CMD compose logs -f
                ;;
            3)
                if ask_confirm "آیا از ری‌استارت مطمئن هستید؟" "y"; then
                    $DOCKER_CMD compose restart
                    log_success "کانتینر ری‌استارت شد."
                fi
                ;;
            4)
                if ask_confirm "آیا از توقف کانتینر مطمئن هستید؟" "y"; then
                    $DOCKER_CMD compose down
                    log_success "کانتینر متوقف شد."
                fi
                ;;
            5)
                save_offline_image
                ;;
            6)
                load_offline_image
                ;;
            7)
                mount_storage_action
                ;;
            q|Q)
                echo "خداحافظ!"
                exit 0
                ;;
            *)
                echo "گزینه نامعتبر است."
                ;;
        esac
        echo ""
    done
}

# نقطه شروع
print_header

if [ "$1" = "--auto" ] || [ "$1" = "start" ]; then
    check_docker
    check_storage_and_media
    configure_gpu_groups
    check_docker_image
    check_proxy
    start_service
elif [ "$1" = "save" ] || [ "$1" = "export" ]; then
    check_docker
    save_offline_image
elif [ "$1" = "load" ] || [ "$1" = "import" ]; then
    check_docker
    load_offline_image
elif [ "$1" = "mount" ]; then
    mount_storage_action
elif [ "$1" = "logs" ]; then
    check_docker
    $DOCKER_CMD compose logs -f
else
    # اجرای پیش‌فرض جادوگر راه‌اندازی
    check_docker
    check_storage_and_media
    configure_gpu_groups
    check_docker_image
    check_proxy
    start_service
    interactive_menu
fi
