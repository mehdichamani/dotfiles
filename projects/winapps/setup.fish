#!/usr/bin/env fish
# ==============================================================================
# WinApps Controller & Hyprland Socket2 Integration for Omarchy Linux
# ==============================================================================

set SCRIPT_DIR (path resolve (dirname (status filename)))
set SECRETS_FILE "$HOME/.ssh/secrets/winapps.env"
set ISO_PATH "/run/media/unreal/TUF_Data/OS/tiny11core_25H2_Nov25.iso"
set DAEMON_SCRIPT "$SCRIPT_DIR/winapps_daemon.py"
set STATE_FILE "/tmp/winapps_state.json"
set CMD_PIPE "/tmp/winapps_daemon.cmd"

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

# 2. بررسی سکرت‌ها
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

function check_requirements
    if not test -c /dev/kvm
        _log_error "شتاب‌دهنده KVM در /dev/kvm در دسترس نیست!"
        return 1
    end

    if not test -f "$ISO_PATH"
        _log_warn "فایل ISO در مسیر زیر یافت نشد (آیا هارد اکسترنال مانت است؟):"
        echo "       $ISO_PATH"
    end
    return 0
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
        nohup python3 "$DAEMON_SCRIPT" &>/dev/null &
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
    check_requirements
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

    _log_info "در حال اتصال RDP با FreeRDP..."
    if command -v xfreerdp3 &>/dev/null
        xfreerdp3 /v:127.0.0.1:3389 /u:"$user" /p:"$pass" /cert:tofu /dynamic-resolution /sound /microphone +clipboard &
    else if command -v xfreerdp &>/dev/null
        xfreerdp /v:127.0.0.1:3389 /u:"$user" /p:"$pass" /cert:tofu /dynamic-resolution /sound /microphone +clipboard &
    else
        _log_error "نرم‌افزار freerdp پیدا نشد!"
    end
    ensure_daemon
end

# دستورات کنترلی Idle
function idle_cmd
    set -l cmd $argv[1]
    if test -p "$CMD_PIPE"
        echo "$cmd" > "$CMD_PIPE"
        _log_success "دستور '$cmd' به دیمن ارسال شد."
    else
        _log_warn "دیمن فعال نیست. در حال اجرای مجدد..."
        ensure_daemon
        sleep 1
        echo "$cmd" > "$CMD_PIPE"
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

# ساخت لانچرهای RemoteApp با خواندن خودکار از فایل ساختاریافته apps.yaml
function install_launchers
    check_secrets
    set -l apps_manifest "$SCRIPT_DIR/apps.yaml"
    set -l apps_dir "$HOME/.local/share/applications"
    mkdir -p "$apps_dir"

    if not test -f "$apps_manifest"
        _log_error "فایل تنظیمات برنامه‌ها ($apps_manifest) یافت نشد!"
        return 1
    end

    _log_info "در حال استخراج لانچرها از $apps_manifest..."
    python3 -c "
import os, sys
try:
    import yaml
except ImportError:
    # فال‌بک ساده در صورت عدم وجود pyyaml
    yaml = None

manifest_path = '$apps_manifest'
apps_dir = '$apps_dir'
script_dir = '$SCRIPT_DIR'

apps = []
if yaml:
    with open(manifest_path, 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f)
        apps = data.get('apps', [])
else:
    # پارسر سبک بدون نیاز به پکیج خارجی
    current_app = {}
    with open(manifest_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line.startswith('- id:'):
                if current_app:
                    apps.append(current_app)
                current_app = {'id': line.split(':', 1)[1].strip().strip('\"\'')}
            elif ':' in line and current_app:
                k, v = line.split(':', 1)
                current_app[k.strip()] = v.strip().strip('\"\'')
        if current_app:
            apps.append(current_app)

for app in apps:
    app_id = app.get('id')
    name = app.get('name')
    target = app.get('target')
    cat = app.get('categories', 'Utility;')
    icon = app.get('icon', 'application-x-executable')
    
    if not app_id or not name or not target:
        continue

    # Escape single quotes and backslashes for bash/fish exec
    escaped_target = target.replace(\"'\", \"'\\\\''\")
    desktop_content = f'''[Desktop Entry]
Name={name}
Exec=fish -c \"{script_dir}/setup.fish run '{escaped_target}'\"
Type=Application
Categories={cat}
Icon={icon}
StartupNotify=true
'''
    desktop_file = os.path.join(apps_dir, f'{app_id}.desktop')
    with open(desktop_file, 'w', encoding='utf-8') as df:
        df.write(desktop_content)
    print(f'   [+] لانچر ساخته شد: {name} -> {desktop_file}')
"
    _log_success "کلیه لانچرهای تعریف‌شده در apps.yaml با موفقیت روی دسکتاپ ثبت شدند."
end

# اجرای هوشمند یک نرم‌افزار خاص
function run_app
    set -l app_target $argv[1]
    check_secrets
    set -l user (get_secret USERNAME)
    set -l pass (get_secret PASSWORD)

    # اگر کانتینر روشن نیست روشن کن
    if not docker inspect -f '{{.State.Running}}' WinApps 2>/dev/null | grep -q "true"
        _log_info "روشن کردن خودکار کانتینر ویندوز..."
        vm_up
        # مهلت کوتاه برای آماده‌سازی پورت RDP
        sleep 3
    end

    ensure_daemon
    _log_info "در حال باز کردن نرم‌افزار: $app_target"
    if command -v xfreerdp3 &>/dev/null
        xfreerdp3 /v:127.0.0.1:3389 /u:"$user" /p:"$pass" /cert:tofu +clipboard /app:"$app_target" &
    else
        xfreerdp /v:127.0.0.1:3389 /u:"$user" /p:"$pass" /cert:tofu +clipboard /app:"$app_target" &
    end
end

# منوی کاربری
set -l action $argv[1]

switch "$action"
    case "deps"
        install_deps
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
    case "run"
        run_app $argv[2]
    case "idle-status"
        idle_status
    case "idle-reset"
        idle_cmd "reset"
    case "idle-cancel"
        idle_cmd "cancel"
    case "install-launchers"
        install_launchers
    case "*"
        echo (set_color green)"===================================================="(set_color normal)
        echo (set_color cyan)"      مدیریت هوشمند WinApps در Omarchy (Socket2)"(set_color normal)
        echo (set_color green)"===================================================="(set_color normal)
        echo "فرامین اجرایی:"
        echo "  ./setup.fish deps               نصب پیش‌نیازها و تنظیم دسترسی گروه‌ها"
        echo "  ./setup.fish up                 روشن کردن کانتینر و فعال‌سازی مانیتورینگ"
        echo "  ./setup.fish down               خاموش کردن کانتینر و متوقف کردن دیمن"
        echo "  ./setup.fish web                باز کردن کنسول تحت وب در مرورگر (http://localhost:8006)"
        echo "  ./setup.fish rdp                اتصال مستقیم به محیط کامل دسکتاپ با FreeRDP"
        echo "  ./setup.fish idle-status        مشاهده وضعیت زنده زمان و تایمر خاموشی"
        echo "  ./setup.fish idle-reset         ریست کردن تایمر خاموشی (تمدید ۳۰ دقیقه)"
        echo "  ./setup.fish idle-cancel        لغو خاموشی خودکار (روشن ماندن دائم)"
        echo "  ./setup.fish install-launchers  ایجاد شرت‌کات‌های دسکتاپ (Word, Excel, iVMS-4200)"
        echo ""
end
