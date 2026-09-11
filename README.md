<div>
  <a href="#english" style="text-decoration:none;margin-right:8px;padding:8px 14px;border:1px solid #0366d6;border-radius:6px;color:#0366d6;font-weight:600;">English</a>
  <a href="#persian" style="text-decoration:none;padding:8px 14px;border:1px solid #0366d6;border-radius:6px;color:#0366d6;font-weight:600;">فارسی</a>
</div>

---

<a id="english"></a>

# Cross-Platform P2P Dotfiles & System Workspace

A cross-platform configuration ecosystem managed with **[chezmoi](https://www.chezmoi.io/)**, synchronized peer-to-peer (P2P) across Arch/Omarchy Linux, Windows (PowerShell), and Android (Termux).

---

## 🌟 Highlights & Key Custom Tools

This repository goes beyond basic configuration files—it includes an integrated suite of automation scripts and intelligent networking utilities designed for seamless multi-device workflows:

### 1. 🔄 `dotsync` — Intelligent P2P Mesh Sync
A cross-platform synchronization engine implemented in native **Fish shell** (`dot_config/fish/functions/dotsync.fish`) and **PowerShell** (`Documents/PowerShell/Functions/dotsync.ps1`).

- **Decentralized P2P Mesh:** Synchronizes dotfiles directly between active peers (`home`, `work`, `s24`, and newly added devices) without relying on a central git host.
- **Dynamic Peer Discovery:** Reads hosts, repo paths (`# @repo`), and targets dynamically from `~/.ssh/config`—no hardcoded IP addresses or device lists.
- **Ultra-Fast Network Probing:** Tests LAN and WAN connectivity in parallel using high-speed socket probes to select the lowest-latency route.
- **Proxy-Isolated Operations:** Automatically bypasses active system/shell proxies for local subnet operations to ensure ultra-fast peer transfers.
- **Automated Deployment:**
  ```bash
  dotsync              # Sync bidirectionally with all reachable peers
  dotsync work         # Sync specifically with peer 'work'
  dotsync -a           # Sync and automatically run 'chezmoi apply' upon new commits
  ```

### 2. ⚡ `s` — Smart SSH Connection Router & Tunnel Manager
A contextual SSH wrapper and remote execution tool available in **Fish** and **PowerShell**.

- **Dynamic Priority & Fallback:** Evaluates connection routes defined in `~/.ssh/config` (`# @priority`) to seamlessly route traffic via LAN, Tailscale, or WAN/Cloudflare.
- **Remote Desktop Tunneling:**
  ```bash
  s -rdp work          # Creates an encrypted tunnel (3390 -> 3389) and launches FreeRDP
  s -vnc home          # Creates an encrypted tunnel (5901 -> 5900) and launches TigerVNC
  ```
- **Cross-Platform Shell Packaging:** Detects target platform shell metadata (`# @shell fish|pwsh|bash`) and packages commands accordingly:
  ```bash
  s work 'Get-Process'        # Dispatches correctly into PowerShell
  s home 'hyprctl monitors'   # Dispatches correctly into Fish/Linux environment
  ```
- **Interactive Autocompletion:** Autocompletes group and peer names directly in the shell.

### 3. 🌐 `proxy` / `withproxy` / `noproxy` — Unified Proxy Management Suite
A comprehensive proxy controller (`dot_config/scripts/proxy.sh`) supporting CLI, desktop GUI environments, and system services.

- **Multi-Scope Configuration:**
  - **CLI (Shell/NPM/Git):** `proxy 3067` or `proxy http://127.0.0.1:10808`
  - **Desktop GUI (GSettings):** `proxy --gui 3067`
  - **Systemd & Docker Daemon:** `proxy --systemd 3067`
  - **Full System (CLI + GUI + Systemd + APT):** `proxy --all 3067`
- **One-Shot Execution Wrappers:**
  - `withproxy <cmd>`: Runs a single command with proxy environment variables injected (falls back to configured presets without altering your active shell).
  - `noproxy <cmd>`: Executes a command with all proxy environment variables stripped.
- **State Persistence & TUI:**
  - Preserves persistent proxy state in `~/.config/proxy_state`.
  - Running `proxy` without arguments launches an interactive terminal menu.

---

## 💻 Environment & Architecture

| Platform | Role | Key Stack & Configs |
| :--- | :--- | :--- |
| **Linux (`home`)** | Primary Desktop | Omarchy Linux (Arch-based), Hyprland (`dot_config/hypr/`), WezTerm, Fish shell, Starship, `mise` |
| **Windows (`work`)** | Secondary Workstation | PowerShell 7+ (`Documents/PowerShell/`), Windows Terminal, OpenSSH |
| **Android (`s24`)** | Mobile Environment | Termux, Fish shell, customized micro-utilities |

### Additional Projects in Repository
- **[cf-ssh-sync](./projects/cf-ssh-sync/README.md):** Zero-Knowledge AES-256 encrypted SSH key sync service using Cloudflare Workers and a cross-platform client (Linux, Android, Windows, macOS).
- **[Jellyfin Media Server](./projects/jellyfin/README.md):** Dockerized home media server setup with host proxy routing for metadata and posters.
- **[WinApps Docker VM](./projects/winapps/guide.md):** Docker-based Windows VM environment with automated FreeRDP desktop integration.

---

## 🚀 Getting Started

### 1. Installation
Install `chezmoi` on your platform:
```bash
# Arch Linux
sudo pacman -S chezmoi

# Other Linux / macOS
sh -c "$(curl -fsLS get.chezmoi.io)"

# Windows (winget)
winget install chezmoi.chezmoi
```

### 2. Initialization & Application
Clone and apply the configuration to your environment:
```bash
chezmoi init mehdichamani/dotfiles
chezmoi diff
chezmoi apply
```

---

<a id="persian"></a>

# فارسی

<div dir="rtl" align="right">

# دات‌فایل‌ها و محیط کاری توزیع‌شده P2P (Cross-Platform)

یک اکوسیستم جامع و کراس‌پلتفرم برای مدیریت و همگام‌سازی فایل‌های پیکربندی با استفاده از **[chezmoi](https://www.chezmoi.io/)**، به صورت نظیر‌به‌نظیر (P2P) میان سیستم‌های لینوکس (Arch/Omarchy)، ویندوز (PowerShell) و اندروید (Termux).

---

## 🌟 ابزارها و اسکریپت‌های اختصاصی

این مخزن فراتر از فایل‌های متنی ساده است؛ مجموعه‌ای از اسکریپت‌های کاربردی و هوشمند برای مدیریت شبکه، همگام‌سازی خودکار و پروکسی در آن تعبیه شده است:

### ۱. 🔄 اسکریپت `dotsync` — همگام‌سازی نظیر‌به‌نظیر (P2P Mesh)
موتور هوشمند همگام‌سازی مخزن دات‌فایل‌ها که در هر دو شل **Fish** (`dot_config/fish/functions/dotsync.fish`) و **PowerShell** (`Documents/PowerShell/Functions/dotsync.ps1`) پیاده‌سازی شده است.

- **شبکه نامتمرکز (P2P Mesh):** همگام‌سازی مستقیم مخزن Chezmoi بین دستگاه‌ها (`home`, `work`, `s24`) بدون نیاز به سرور مرکزی یا Push به ریپوی عمومی گیت‌هاب در هر تغییر کوچک.
- **کشف پویای دستگاه‌ها (Dynamic Discovery):** استخراج خودکار آدرس‌ها، نام پیرها و مسیر مخزن (`# @repo`) از متادیتای فایل `~/.ssh/config` بدون وابستگی به IPهای ثابت.
- **پروب سریع شبکه:** پایش هم‌زمان وضعیت شبکه LAN و اینترنت از طریق سوکت پروب فوق‌سریع برای انتخاب کم‌تاخیرترین مسیر ارتباطی.
- **ایزولاسیون پروکسی:** دور زدن خودکار پروکسی‌های فعال برای ارتباطات شبکه محلی (LAN) جهت تضمین نهایت سرعت در همگام‌سازی.
- **دستورات کاربردی:**
  ```bash
  dotsync              # همگام‌سازی دوطرفه با تمام دستگاه‌های آنلاین در دسترس
  dotsync work         # همگام‌سازی اختصاصی با دستگاه work
  dotsync -a           # همگام‌سازی و اجرای خودکار 'chezmoi apply' در صورت دریافت کامیت‌های جدید
  ```

### ۲. ⚡ اسکریپت `s` — مسیریاب هوشمند SSH و مدیریت تونل‌ها
ابزار مدیریت اتصال، تونل‌زدن و اجرای فرامین راه دور در **Fish** و **PowerShell**.

- **انتخاب هوشمند مسیر (Fallback):** بررسی اولویت‌های اتصال (`# @priority`) در `~/.ssh/config` و جابه‌جایی خودکار بین شبکه محلی (LAN)، تیل‌اسکیل یا اینترنت.
- **تونل‌سازی و اتصال دسکتاپ از راه دور (RDP & VNC):**
  ```bash
  s -rdp work          # برقراری تونل امن (3390 -> 3389) و باز کردن خودکار کلاینت FreeRDP
  s -vnc home          # برقراری تونل امن (5901 -> 5900) و اتصال TigerVNC
  ```
- **اجرای متناسب فرامین در شل مقصد:** شناسایی شل نیتیو مقصد بر اساس تگ `# @shell` در تنظیمات SSH:
  ```bash
  s work 'Get-Service'        # اجرای خودکار دستور درون PowerShell ویندوز
  s home 'hyprctl monitors'   # اجرای خودکار دستور درون محیط لینوکس/فیش
  ```
- **پشتیبانی کامل از Autocomplete:** تکمیل خودکار نام گروه‌ها و میزبان‌ها در خط فرمان.

### ۳. 🌐 مدیریت جامع پروکسی (`proxy` / `withproxy` / `noproxy`)
مدیریت یکپارچه وضعیت پروکسی در شل، رابط گرافیکی دسکتاپ و سرویس‌های سیستمی (`dot_config/scripts/proxy.sh`).

- **پیکربندی در سطوح مختلف:**
  - **محیط خط فرمان (CLI / Git / NPM):** `proxy 3067` یا `proxy http://127.0.0.1:10808`
  - **محیط گرافیکی (GSettings):** `proxy --gui 3067`
  - **سرویس داکر و سیستم‌دی:** `proxy --systemd 3067`
  - **اعمال سراسری (CLI + GUI + Systemd + APT):** `proxy --all 3067`
- **اجرای موقت و تفکیک‌شده فرامین:**
  - `withproxy <command>`: اجرای یک دستور خاص با اعمال متغیرهای پروکسی (بدون تغییر در محیط فعال ترمینال).
  - `noproxy <command>`: اجرای یک دستور خاص با حذف تمامی متغیرهای پروکسی.
- **منوی تعاملی و ذخیره وضعیت:**
  - ذخیره وضعیت پایدار در `~/.config/proxy_state`.
  - اجرای دستور `proxy` به تنهایی، منوی متنی تعاملی (TUI) را در اختیارتان می‌گذارد.

---

## 💻 مشخصات محیط و معماری

| پلتفرم | نقش در شبکه | پیکربندی و ابزارهای اصلی |
| :--- | :--- | :--- |
| **لینوکس (`home`)** | سیستم دسکتاپ اصلی | Omarchy Linux بر پایه Arch، مدیر پنجره Hyprland (`dot_config/hypr/`)، ترمینال WezTerm، شل Fish، Starship، `mise` |
| **ویندوز (`work`)** | ورک‌استیشن اداری | PowerShell 7+ (`Documents/PowerShell/`)، ویندوز ترمینال، سرویس OpenSSH |
| **اندروید (`s24`)** | پایانه همراه | محیط Termux، شل Fish، اسکریپت‌ها و ابزارهای بهینه‌شده |

### پروژه‌ها و مستندات دیگر در این مخزن
- **[پروژه cf-ssh-sync](./projects/cf-ssh-sync/README.md):** همگام‌سازی امن و سرتاسر رمزنگاری‌شده (Zero-Knowledge AES-256) کلیدهای SSH با استفاده از Cloudflare Workers در لینوکس، ویندوز، مک و اندروید.
- **[سرور چندرسانه‌ای Jellyfin](./projects/jellyfin/README.md):** راه‌اندازی کانتینر Jellyfin به همراه راهنمای هدایت ترافیک متادیتا و پوسترها از پروکسی میزبان.
- **[ماشین مجازی ویندوز WinApps](./projects/winapps/guide.md):** محیط کانتینری ویندوز در داکر به همراه یکپارچگی لانچر ریموت دسکتاپ (FreeRDP) در لینوکس.

---

## 🚀 راه‌اندازی و استفاده

۱. نصب `chezmoi` بر روی سیستم مورد نظر:
```bash
# آرچ لینوکس
sudo pacman -S chezmoi

# سایر توزیع‌های لینوکس
sh -c "$(curl -fsLS get.chezmoi.io)"

# ویندوز
winget install chezmoi.chezmoi
```

۲. دریافت و پیاده‌سازی پیکربندی:
```bash
chezmoi init mehdichamani/dotfiles
chezmoi diff
chezmoi apply
```

</div>

