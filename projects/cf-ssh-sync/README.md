# Cloudflare Worker Vault & SSH Sync (`cf-ssh-sync`)

همگام‌سازی و انتقال امن و رمزنگاری‌شده (Zero-Knowledge AES-256) کلیه دارایی‌های حساس، کلیدها، کانفیگ شبکه و سکرت‌ها در پوشه `~/.ssh/` و `~/.ssh/secrets/` روی ورکر کلودفلر (`https://ssh.ajbv.ir`).

---

## ⚡ دستورات سریع (Quick Start)

### ۱. آپلود و پشتیبان‌گیری (نیازمند `MY_TOKEN`):
- **لینوکس / اندروید Termux:**
  ```bash
  curl -fsSL "https://ssh.ajbv.ir/send.sh?token=MY_TOKEN" | bash
  ```
- **ویندوز (PowerShell):**
  ```powershell
  irm "https://ssh.ajbv.ir/send.ps1?token=MY_TOKEN" | iex
  ```

### ۲. دریافت و بازیابی (بدون نیاز به توکن):
- **لینوکس / اندروید Termux:**
  ```bash
  curl -fsSL https://ssh.ajbv.ir/get.sh | bash
  ```
- **ویندوز (PowerShell):**
  ```powershell
  irm https://ssh.ajbv.ir/get.ps1 | iex
  ```

> اسکریپت `get` به صورت خودکار پوشه `~/.ssh` و زیرپوشه `secrets/` را با پرمیژن‌های امنیتی (`chmod 700 / 600`) بازگردانی و پیکربندی می‌کند.

---

## 🔮 راه‌اندازی پس از بازیابی (Bootstrap)

### 👑 Omarchy Linux
```bash
# ۱. بوت‌استرپ دات‌فایلز
sudo pacman -S --needed chezmoi fish && chezmoi init mehdichamani && chezmoi apply

# ۲. نصب تمام پکیج‌ها و منو (در fish)
dotsync install && omarchy plugin add https://github.com/filip-spaldon/omarchy-menu.git --enable

# ۳. دریافت نوت‌ها از گوشی
sftp s24-home # (داخل کنسول: get -r /sdcard/Notes/ و get -r /sdcard/insync/)

# ۴. پروکسی و ابزارها
pinstall https://github.com/patterniha/PattN/ && proxy 10808 && mise install

# ۵. هوش مصنوعی
yay -S antigravity-ide && curl -fsSL https://raw.githubusercontent.com/mehdichamani/PersianAntigravityIDE/main/setup.sh | bash

# ۶. سرویس‌ها و تنظیم SSH سرور (پورت ۲۲۴۵۶ و فایروال)
systemctl --user enable --now syncthing.service && sudo systemctl enable --now docker.service && sudo usermod -aG docker $USER
echo "Port 22456" | sudo tee /etc/ssh/sshd_config.d/port.conf && sudo ufw allow 22456/tcp && sudo systemctl enable --now sshd && sudo systemctl restart sshd
```

### 🐧 سایر سیستم‌ها (Ubuntu, Termux, Windows)
> ⏳ *راهنمای تفصیلی به‌زودی اضافه می‌شود...*

---

## 🚀 دیپلوی (Deployment)

```bash
cd ~/.local/share/chezmoi/projects/cf-ssh-sync
npx wrangler secret put SYNC_TOKEN
npx wrangler deploy
```
