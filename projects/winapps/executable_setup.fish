#!/usr/bin/env fish
# ==============================================================================
# WinApps Controller & Hyprland Socket2 Integration for Omarchy Linux
# ==============================================================================

set SCRIPT_DIR (path resolve (dirname (status filename)))
set SECRETS_FILE "$HOME/.ssh/secrets/winapps.env"
set ENV_FILE "$SCRIPT_DIR/.env"
set DAEMON_SCRIPT "$SCRIPT_DIR/winapps_daemon.py"
set STATE_FILE "/tmp/winapps_state.json"
set CMD_SOCK "/tmp/winapps_daemon.sock"
set ICON_FILE "$SCRIPT_DIR/winapps.png"

# تابع بارگذاری و اعتبارسنجی فایل .env محلی
function load_local_env
    if test -f "$ENV_FILE"
        for line in (cat "$ENV_FILE")
            set -l trimmed (string trim "$line")
            if test -n "$trimmed"; and not string match -q '#*' "$trimmed"
                set -l kv (string split -m 1 = "$trimmed")
                if test (count $kv) -eq 2
                    set -gx $kv[1] (string trim -c '"\' ' "$kv[2]")
                end
            end
        end
    end
    set -g ISO_PATH "$WINAPPS_ISO_PATH"
    set -g PROGRAMS_DIR "$WINAPPS_PROGRAMS_DIR"
end

load_local_env

function _log_info
    echo (set_color cyan)"[INFO] "(set_color normal)$argv
end

function _log_success
    echo (set_color green)"[SUCCESS] "(set_color normal)$argv
end

function _log_warn
    echo (set_color yellow)"[WARN] "(set_color normal)$argv
end

function _log_error
    echo (set_color red)"[ERROR] "(set_color normal)$argv
end

# 1. نصب پیش‌نیازها و تنظیم گروه‌ها
function install_deps
    _log_info "در حال بررسی و نصب بسته‌های پیش‌نیاز روی Omarchy/Arch..."
    sudo pacman -S --needed --noconfirm docker freerdp libnotify jq python

    _log_info "تنظیم دسترسی کاربر به گروه‌های docker و kvm..."
    sudo usermod -aG docker,kvm $USER
    sudo systemctl enable --now docker

    _log_success "پیش‌نیازها با موفقیت نصب و فعال شدند."
    _log_warn "اگر به تازگی به گروه‌ها اضافه شده‌اید، یک‌بار لاگ‌اوت و لاگین کنید."
end

# 2. بررسی و ایجاد سکرت‌ها
function check_secrets
    if not test -f "$SECRETS_FILE"
        _log_warn "فایل سکرت $SECRETS_FILE یافت نشد. در حال ساخت خودکار..."
        mkdir -p "$HOME/.ssh/secrets"
        set -l generated_pwd (python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(8)))")
        printf "USERNAME=unreal\nPASSWORD=%s\n" $generated_pwd > "$SECRETS_FILE"
        chmod 600 "$SECRETS_FILE"
        _log_success "فایل سکرت با رمز ۸ رقمی تصادفی ساخته شد."
    end
end

function get_secret
    set -l key $argv[1]
    grep "^$key=" "$SECRETS_FILE" | cut -d'=' -f2-
end

# بررسی جامع سلامت سیستم و پیش‌نیازها (Health Check)
function check_environment
    echo (set_color cyan)"===================================================="(set_color normal)
    echo (set_color cyan)"       بررسی وضعیت و سلامت محیط WinApps             "(set_color normal)
    echo (set_color cyan)"===================================================="(set_color normal)
    set -l has_error 0

    # 1. بررسی پکیج‌های سیستمی
    echo ""
    echo (set_color yellow)"[۱/۷] بررسی پکیج‌ها و دستورات مورد نیاز:"(set_color normal)
    set -l required_cmds docker jq python3 notify-send
    for cmd in $required_cmds
        if type -q $cmd
            echo "  ✔ $cmd: "(set_color green)"یافت شد"(set_color normal)
        else
            echo "  ✘ $cmd: "(set_color red)"یافت نشد! لطفا ./setup.fish deps را اجرا کنید."(set_color normal)
            set has_error 1
        end
    end

    if type -q xfreerdp3
        echo "  ✔ FreeRDP (xfreerdp3): "(set_color green)"یافت شد"(set_color normal)
    else if type -q xfreerdp
        echo "  ✔ FreeRDP (xfreerdp): "(set_color green)"یافت شد"(set_color normal)
    else
        echo "  ✘ FreeRDP (xfreerdp/xfreerdp3): "(set_color red)"یافت نشد! لطفا ./setup.fish deps را اجرا کنید."(set_color normal)
        set has_error 1
    end

    # 2. بررسی دسترسی KVM
    echo ""
    echo (set_color yellow)"[۲/۷] بررسی شتاب‌دهنده سخت‌افزاری KVM:"(set_color normal)
    if test -c /dev/kvm
        if test -r /dev/kvm -a -w /dev/kvm
            echo "  ✔ /dev/kvm: "(set_color green)"موجود و قابل خواندن/نوشتن است"(set_color normal)
        else
            echo "  ⚠ /dev/kvm: "(set_color yellow)"موجود است اما دسترسی مستقیم کاربر وجود ندارد (عضویت در گروه kvm را چک کنید)"(set_color normal)
        end
    else
        echo "  ✘ /dev/kvm: "(set_color red)"یافت نشد! مجازی‌سازی در بایوس یا ماژول kvm فعال نیست."(set_color normal)
        set has_error 1
    end

    # 3. بررسی سرویس و دسترسی داکر
    echo ""
    echo (set_color yellow)"[۳/۷] بررسی سرویس داکر:"(set_color normal)
    if docker info &>/dev/null
        echo "  ✔ داکر: "(set_color green)"سرویس در حال اجراست و دسترسی مجاز است"(set_color normal)
    else
        echo "  ✘ داکر: "(set_color red)"امکان اتصال به daemon داکر نیست! (آیا سرویس فعال است و کاربر عضو گروه docker است؟)"(set_color normal)
        set has_error 1
    end

    # 4. بررسی ایمیج داکر
    echo ""
    echo (set_color yellow)"[۴/۷] بررسی ایمیج داکر (dockur/windows):"(set_color normal)
    if docker image inspect ghcr.io/dockur/windows:latest &>/dev/null
        echo "  ✔ ایمیج ghcr.io/dockur/windows:latest: "(set_color green)"موجود و آماده در Docker cache"(set_color normal)
    else
        echo "  ⚠ ایمیج داکر در کش یافت نشد. بررسی فایل پشتیبان آفلاین..."
        set -l tar_path "/run/media/unreal/TUF_Data/programs/docker-images/dockurr_windows_latest.tar"
        if test -f "$tar_path"
            echo "  ✔ فایل ایمیج آفلاین در هارد اکسترنال یافت شد: "(set_color green)"$tar_path"(set_color normal)
        else
            echo "  ✘ فایل ایمیج آفلاین در هارد اکسترنال نیز یافت نشد!"(set_color red)" ($tar_path)"(set_color normal)
            set has_error 1
        end
    end

    # 5. بررسی فایل .env محلی و متغیرهای مسیر
    echo ""
    echo (set_color yellow)"[۵/۷] بررسی فایل کانفیگ محیطی (.env):"(set_color normal)
    if test -f "$ENV_FILE"
        echo "  ✔ فایل .env: "(set_color green)"یافت شد ($ENV_FILE)"(set_color normal)
        load_local_env

        # بررسی وجود دو ردیف الزامی در .env
        if test -z "$WINAPPS_ISO_PATH"
            echo "  ✘ ردیف WINAPPS_ISO_PATH: "(set_color red)"در فایل .env تعریف نشده است!"(set_color normal)
            set has_error 1
        else
            echo "  ✔ WINAPPS_ISO_PATH: "(set_color green)"$WINAPPS_ISO_PATH"(set_color normal)
        end

        if test -z "$WINAPPS_PROGRAMS_DIR"
            echo "  ✘ ردیف WINAPPS_PROGRAMS_DIR: "(set_color red)"در فایل .env تعریف نشده است!"(set_color normal)
            set has_error 1
        else
            echo "  ✔ WINAPPS_PROGRAMS_DIR: "(set_color green)"$WINAPPS_PROGRAMS_DIR"(set_color normal)
        end
    else
        echo "  ✘ فایل .env: "(set_color red)"یافت نشد! ($ENV_FILE)"(set_color normal)
        echo "     لطفاً یک فایل .env در این مسیر بسازید و دو متغیر زیر را در آن مقداردهی کنید:"
        echo "     WINAPPS_ISO_PATH=/path/to/windows.iso"
        echo "     WINAPPS_PROGRAMS_DIR=/path/to/programs"
        set has_error 1
    end

    # 6. بررسی درستی مسیر فایل ISO و پوشه برنامه‌ها
    echo ""
    echo (set_color yellow)"[۶/۷] بررسی صحت مسیرهای فایل ISO و پوشه برنامه‌ها:"(set_color normal)
    if test -n "$ISO_PATH" -a -f "$ISO_PATH"
        set -l iso_size (numfmt --to=iec (stat -c %s "$ISO_PATH" 2>/dev/null) 2>/dev/null)
        test -z "$iso_size"; and set iso_size "موجود"
        echo "  ✔ فایل ISO: "(set_color green)"یافت شد ($iso_size) -> $ISO_PATH"(set_color normal)
    else
        echo "  ✘ فایل ISO: "(set_color red)"در مسیر $ISO_PATH یافت نشد!"(set_color normal)
        set has_error 1
    end

    if test -n "$PROGRAMS_DIR" -a -d "$PROGRAMS_DIR"
        echo "  ✔ پوشه برنامه‌ها: "(set_color green)"یافت شد -> $PROGRAMS_DIR"(set_color normal)
    else
        echo "  ✘ پوشه برنامه‌ها: "(set_color red)"در مسیر $PROGRAMS_DIR یافت نشد!"(set_color normal)
        set has_error 1
    end

    # 7. بررسی سکرت‌ها
    echo ""
    echo (set_color yellow)"[۷/۷] بررسی فایل سکرت و متغیرهای محلی:"(set_color normal)
    if test -f "$SECRETS_FILE"
        echo "  ✔ فایل سکرت: "(set_color green)"یافت شد ($SECRETS_FILE)"(set_color normal)
        set -l u (get_secret USERNAME)
        if test -n "$u"
            echo "     کاربر تعریف‌شده: "(set_color cyan)"$u"(set_color normal)
        end
    else
        echo "  ⚠ فایل سکرت وجود ندارد؛ هنگام اولین اجرای ./setup.fish up یا check خودکار ساخته می‌شود."
        check_secrets
    end

    echo ""
    echo (set_color cyan)"===================================================="(set_color normal)
    if test $has_error -eq 0
        _log_success "همه پیش‌نیازها و فایل‌ها با موفقیت تأیید شدند. سیستم آماده راه‌اندازی است!"
        return 0
    else
        _log_warn "برخی موارد نیاز به بررسی یا برطرف‌سازی دارند."
        return 1
    end
end

# بررسی و لود خودکار ایمیج آفلاین از هارد اکسترنال
function ensure_offline_image
    if not docker image inspect ghcr.io/dockur/windows:latest &>/dev/null
        set -l tar_path "/run/media/unreal/TUF_Data/programs/docker-images/dockurr_windows_latest.tar"
        if test -f "$tar_path"
            _log_info "ایمیج محلی در داکر یافت نشد. در حال بارگذاری سریع از هارد اکسترنال..."
            set -l loaded_out (docker load -i "$tar_path")
            set -l img_id (echo $loaded_out | grep -o 'sha256:[a-f0-9]*' | head -n 1)
            if test -n "$img_id"
                docker tag "$img_id" ghcr.io/dockur/windows:latest
                docker tag "$img_id" dockur/windows:latest
                _log_success "ایمیج آفلاین با موفقیت لود و برچسب‌گذاری شد."
            end
        end
    end
end

# مدیریت دیمن پایتونی مانیتورینگ
function ensure_daemon
    if not pgrep -f "$DAEMON_SCRIPT" &>/dev/null
        _log_info "در حال اجرای دیمن مانیتورینگ رویدادمحور Hyprland..."
        nohup python3 "$DAEMON_SCRIPT" </dev/null &>/dev/null &
        disown
    end
end

function stop_daemon
    set -l pid (pgrep -f "$DAEMON_SCRIPT")
    if test -n "$pid"
        kill -TERM $pid &>/dev/null
    end
end

# 3. دستورات کانتینر
function vm_up
    check_secrets
    check_environment
    ensure_offline_image
    _log_info "در حال راه‌اندازی کانتینر Windows VM..."
    docker compose -f "$SCRIPT_DIR/compose.yml" up -d
    ensure_daemon
    _log_success "کانتینر فعال شد."
    echo ""
    echo "🌐 کنسول وب VNC جهت مشاهده و تکمیل نصب:"
    echo "   http://127.0.0.1:8006"
    echo ""
    echo "🔑 مشخصات لاگین خودکار:"
    echo "   کاربر: "(get_secret USERNAME)
    echo "   رمز:   "(get_secret PASSWORD)
end

function vm_down
    _log_info "در حال توقف کانتینر Windows VM..."
    docker compose -f "$SCRIPT_DIR/compose.yml" down
    stop_daemon
    _log_success "کانتینر و دیمن متوقف شدند."
end

function vm_status
    docker ps -a --filter "name=WinApps"
    if test -f "$STATE_FILE"
        echo ""
        echo (set_color cyan)"وضعیت سیستم Idle:"(set_color normal)
        cat "$STATE_FILE"
        echo ""
    end
end

function vm_logs
    docker compose -f "$SCRIPT_DIR/compose.yml" logs -f
end

function vm_web
    _log_info "در حال باز کردن کنسول وب VNC..."
    xdg-open "http://127.0.0.1:8006" &>/dev/null &
end

function vm_rdp
    check_secrets
    set -l user (get_secret USERNAME)
    set -l pass (get_secret PASSWORD)

    # اگر کانتینر روشن نیست ابتدا آن را استارت کنیم
    if not docker inspect -f '{{.State.Running}}' WinApps 2>/dev/null | grep -q "true"
        _log_info "کانتینر خاموش است، ابتدا در حال روشن کردن..."
        vm_up
    end

    _log_info "در حال انتظار برای آماده شدن سرویس RDP ویندوز..."
    notify-send -a "WinApps" -i "$ICON_FILE" "Windows Starting" "Waiting for RDP service to become ready..."

    set -l rdp_ready 0
    for i in (seq 1 60)
        # بررسی پاسخ واقعی پروتکل RDP (هندشیک TPKT + X.224)
        if python3 -c "
import socket
s = socket.socket()
s.settimeout(1.5)
try:
    s.connect(('127.0.0.1', 3389))
    s.send(bytes.fromhex('030000130ee000000000000100080003000000'))
    resp = s.recv(1024)
    if len(resp) >= 4 and resp[0] == 3:
        exit(0)
    exit(1)
except Exception:
    exit(1)
finally:
    s.close()
" &>/dev/null
            set rdp_ready 1
            break
        end
        sleep 2
    end

    if test $rdp_ready -eq 0
        _log_error "مهلت انتظار برای آماده‌سازی RDP به پایان رسید."
        notify-send -a "WinApps" -u critical -i "$ICON_FILE" "Connection Failed" "Windows RDP service did not respond in time."
        return 1
    end

    # وقفه کوتاه ۱ ثانیه‌ای جهت تثبیت نشست
    sleep 1

    _log_info "در حال اتصال RDP با FreeRDP..."
    if command -v xfreerdp3 &>/dev/null
        nohup xfreerdp3 /v:127.0.0.1:3389 /u:"$user" /p:"$pass" /sec:nla /cert:ignore /dynamic-resolution /sound /microphone +clipboard &>/dev/null &
    else if command -v xfreerdp &>/dev/null
        nohup xfreerdp /v:127.0.0.1:3389 /u:"$user" /p:"$pass" /sec:nla /cert:ignore /dynamic-resolution /sound /microphone +clipboard &>/dev/null &
    else
        _log_error "نرم‌افزار freerdp پیدا نشد!"
    end
    ensure_daemon
end

# دستورات کنترلی Idle
function idle_cmd
    set -l cmd $argv[1]
    if not test -S "$CMD_SOCK"
        _log_warn "دیمن فعال نیست. در حال اجرای مجدد..."
        ensure_daemon
        sleep 1
    end

    if test -S "$CMD_SOCK"
        python3 -c "
import socket, sys
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2.0)
    s.connect('$CMD_SOCK')
    s.sendall(b'$cmd\n')
    s.close()
    sys.exit(0)
except Exception:
    sys.exit(1)
" &>/dev/null
        if test $status -eq 0
            _log_success "دستور '$cmd' به دیمن ارسال شد."
        else
            _log_error "خطا در ارسال دستور به دیمن."
        end
    else
        _log_error "امکان برقراری ارتباط با دیمن وجود ندارد."
    end
end

function idle_status
    if test -f "$STATE_FILE"
        python3 -c "
import json
with open('$STATE_FILE') as f:
    d = json.load(f)
state = d.get('state', 'unknown')
rem = d.get('remaining', 0)
win = d.get('active_windows', 0)
m, s = divmod(rem, 60)
print(f'وضعیت فعلی: {state}')
print(f'پنجره‌های باز: {win}')
print(f'زمان باقیمانده تا خاموشی: {m} دقیقه و {s} ثانیه')
"
    else
        _log_warn "فایل وضعیتی یافت نشد (کانتینر خاموش است)."
    end
end

# ساخت لانچرهای دسکتاپ (RDP و Web) و نصب آیکون‌ها
function install_launcher
    set -l apps_dir "$HOME/.local/share/applications"
    set -l icons_dir "$HOME/.local/share/icons/hicolor"
    mkdir -p "$apps_dir"

    # نصب آیکون‌ها در تم سیستم (PNG و SVG)
    if test -f "$ICON_FILE"
        mkdir -p "$icons_dir/48x48/apps" "$icons_dir/scalable/apps"
        cp -f "$ICON_FILE" "$icons_dir/48x48/apps/winapps.png"
        if test -f "$SCRIPT_DIR/winapps.svg"
            cp -f "$SCRIPT_DIR/winapps.svg" "$icons_dir/scalable/apps/winapps.svg"
        end
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null
    end

    # انتخاب دقیق‌ترین مسیر یا نام آیکون
    set -l icon_target "winapps"
    if test -f "$ICON_FILE"
        set icon_target "$ICON_FILE"
    end

    # لانچر ۱: اتصال مستقیم RDP
    set -l rdp_file "$apps_dir/winapps-rdp.desktop"
    printf "[Desktop Entry]\nName=Windows Desktop (RDP)\nComment=Connect to full Windows VM desktop session via FreeRDP\nExec=fish -c \"%s/setup.fish rdp\"\nType=Application\nCategories=System;RemoteAccess;Network;\nIcon=%s\nStartupNotify=true\n" "$SCRIPT_DIR" "$icon_target" > "$rdp_file"
    _log_success "لانچر Windows Desktop (RDP) در $rdp_file ایجاد شد."

    # لانچر ۲: کنسول وب (XDG / Web VNC)
    set -l web_file "$apps_dir/winapps-web.desktop"
    printf "[Desktop Entry]\nName=Windows Console (Web)\nComment=Open Windows Web VNC console in default browser\nExec=fish -c \"%s/setup.fish web\"\nType=Application\nCategories=System;RemoteAccess;Network;\nIcon=%s\nStartupNotify=true\n" "$SCRIPT_DIR" "$icon_target" > "$web_file"
    _log_success "لانچر Windows Console (Web) در $web_file ایجاد شد."

    update-desktop-database "$apps_dir" 2>/dev/null
end

# منوی کاربری
set -l action $argv[1]

switch "$action"
    case "deps"
        install_deps
    case "check"
        check_environment
    case "up" "start"
        vm_up
    case "down" "stop"
        vm_down
    case "status"
        vm_status
    case "logs"
        vm_logs
    case "web"
        vm_web
    case "rdp"
        vm_rdp
    case "idle-status"
        idle_status
    case "idle-reset"
        idle_cmd "reset"
    case "idle-cancel"
        idle_cmd "cancel"
    case "daemon"
        ensure_daemon
    case "stop-daemon"
        stop_daemon
    case "install-launcher" "install-launchers"
        install_launcher
    case "*"
        echo (set_color green)"===================================================="(set_color normal)
        echo (set_color cyan)"       مدیریت اتصال Windows VM (FreeRDP) در Omarchy"(set_color normal)
        echo (set_color green)"===================================================="(set_color normal)
        echo "فرامین اجرایی:"
        echo "  ./setup.fish deps               نصب پیش‌نیازها و تنظیم دسترسی گروه‌ها"
        echo "  ./setup.fish check              بررسی جامع سلامت محیط (ایمیج داکر، ISO، KVM، سکرت‌ها)"
        echo "  ./setup.fish up                 روشن کردن کانتینر و فعال‌سازی مانیتورینگ"
        echo "  ./setup.fish down               خاموش کردن کانتینر و متوقف کردن دیمن"
        echo "  ./setup.fish web                باز کردن کنسول تحت وب در مرورگر (http://localhost:8006)"
        echo "  ./setup.fish rdp                اتصال مستقیم به محیط کامل دسکتاپ با FreeRDP"
        echo "  ./setup.fish idle-status        مشاهده وضعیت زنده زمان و تایمر خاموشی"
        echo "  ./setup.fish idle-reset         ریست کردن تایمر خاموشی (تمدید ۳۰ دقیقه)"
        echo "  ./setup.fish idle-cancel        لغو خاموشی خودکار (روشن ماندن دائم)"
        echo "  ./setup.fish install-launcher   ایجاد شرت‌کات دسکتاپ اتصال به ویندوز"
        echo ""
end
