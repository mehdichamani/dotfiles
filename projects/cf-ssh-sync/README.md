# Cloudflare Worker Vault & SSH Sync (`cf-ssh-sync`)

یک ورکر Cloudflare و ابزار تک‌خطی فوق‌العاده سبک، امن و چندسکویی برای انتقال و همگام‌سازی رمزنگاری‌شده کلیدهای SSH (`~/.ssh/`) و پوشه سکرت‌ها (`~/.config/secrets/`) شامل کلیدهای متقارن `chezmoi-git-crypt.key` و فایل‌های محیطی `.env`.

---

## ⚡ خلاصه سریع (TL;DR)

- **هدف:** پشتیبان‌گیری موقت و انتقال امن محتویات `~/.ssh/` و `~/.config/secrets/` به سیستم‌های جدید بدون افشای داده‌ها یا نیاز به انتقال دستی.
- **معماری:** 
  - **Backend:** یک Cloudflare Worker + KV Storage (`SSH_KV`).
  - **Security (Zero-Knowledge):** رمزنگاری سمت کلاینت با الگوریتم **AES-256-CBC** + **PBKDF2 SHA-256** (کلادفلر فقط دیتای باینری رمزنگاری‌شده را ذخیره می‌کند).
  - **حفاظت از آپلود (Anti-Tampering):** عملیات آپلود (`send.sh`, `send.ps1`, `POST /data`) با توکن اختصاصی (`SYNC_TOKEN`) محافظت می‌شود تا افراد ناشناس نتوانند دیتای KV را بازنویسی یا تخریب کنند.
  - **دانلود عمومی و آزاد:** دریافت پی‌لود (`get.sh`, `get.ps1`) عمومی است و به دلیل رمزنگاری سرتاسری فقط با پس‌فریز کاربر رمزگشایی می‌شود.
  - **آنلاک خودکار Git-Crypt:** در صورت حضور کلید `chezmoi-git-crypt.key` و مخزن Chezmoi، دستور `git-crypt unlock` خودکار اجرا می‌شود.
- **پلتفرم‌های تحت پشتیبانی:**
  - 🐧 **Linux** (Arch/Omarchy, Debian/Ubuntu, Fedora/RHEL)
  - 📱 **Android** (Termux)
  - 🍏 **macOS**
  - 🪟 **Windows** (PowerShell 7+ / 5.1)

---

## 💻 دستورات تک‌خطی استفاده (One-Liners)

> **توجه:** آدرس ورکر پیش‌فرض: `https://ssh.ajbv.ir`

### ۱. آپلود و رمزنگاری سکرت‌ها و کلیدها (Upload / Backup)

> در دستورات زیر، `MY_TOKEN` همان توکن امنیتی تعریف‌شده در ورکر است.

- **لینوکس / اندروید Termux / مک:**
  ```bash
  curl -fsSL "https://ssh.ajbv.ir/send.sh?token=MY_TOKEN" | bash
  ```
- **ویندوز (PowerShell):**
  ```powershell
  irm "https://ssh.ajbv.ir/send.ps1?token=MY_TOKEN" | iex
  ```

---

### ۲. دریافت، رمزگشایی و آنلاک خودکار (Download / Restore)

> دانلود و بازیابی به صورت آزاد و بدون نیاز به توکن انجام می‌شود (تنها با وارد کردن پس‌فریز رمزنگاری).

- **لینوکس / اندروید Termux / مک:**
  ```bash
  curl -fsSL https://ssh.ajbv.ir/get.sh | bash
  ```
- **ویندوز (PowerShell):**
  ```powershell
  irm https://ssh.ajbv.ir/get.ps1 | iex
  ```

---

## 🔒 مدیریت دسترسی‌ها و امنیت (Permissions & Git-Crypt)

اسکریپت بازیابی (`get.sh` / `get.ps1`) پس از استخراج فایل‌ها، اقدامات زیر را به صورت خودکار انجام می‌دهد:
1. **تنظیم پرمیژن‌های استاندارد:**
   - `chmod 700 ~/.ssh` و `chmod 700 ~/.config/secrets`
   - `chmod 600 ~/.ssh/id_*` (کلیدهای خصوصی)
   - `chmod 644 ~/.ssh/*.pub` (کلیدهای عمومی)
   - `chmod 600 ~/.ssh/config` و `~/.ssh/authorized_keys`
   - `chmod 600 ~/.config/secrets/*` (تمامی فایل‌های محیطی و کلیدها)
2. **آنلاک خودکار Chezmoi Git-Crypt:**
   - اگر کلید `~/.config/secrets/chezmoi-git-crypt.key` استخراج شود و مخزن `~/.local/share/chezmoi` در سیستم وجود داشته باشد، دستور `git-crypt unlock` بلافاصله اجرا می‌شود.

---

## 🛠️ ساختار Endpoints ورکر

| متد | مسیر (Route) | نیازمند توکن؟ | عملکرد |
| :--- | :--- | :---: | :--- |
| `GET` | `/` | ❌ | نمایش پنل تحت وب واکنش‌گرا و راهنما |
| `GET` | `/send.sh?token=...` | ✅ | دانلود اسکریپت Bash برای آرشیو، رمزنگاری و ارسال |
| `GET` | `/get.sh` | ❌ | دانلود اسکریپت Bash برای دریافت، رمزگشایی و تنظیم پرمیژن‌ها |
| `GET` | `/send.ps1?token=...` | ✅ | اسکریپت PowerShell آپلود برای ویندوز |
| `GET` | `/get.ps1` | ❌ | اسکریپت PowerShell دریافت و اکسترکت برای ویندوز |
| `POST` | `/data?token=...` | ✅ | ذخیره پی‌لود باینری رمزنگاری‌شده در Cloudflare KV |
| `GET` | `/data` | ❌ | دریافت پی‌لود باینری رمزنگاری‌شده از Cloudflare KV |

---

## 🚀 دیپلوی و تنظیم سکرت در Cloudflare Workers

### ۱. تنظیم توکن امنیتی (Wrangler Secret):
```bash
cd ~/.local/share/chezmoi/projects/cf-ssh-sync
npx wrangler secret put SYNC_TOKEN
# توکن امنیتی دلخواه خود را وارد کنید (مثال: secret_token_xyz)
```

### ۲. دیپلوی ورکر:
```bash
npx wrangler deploy
```

---

## 🔮 جریان راه‌اندازی دستگاه جدید (Bootstrap Flow)

پس از اجرای `get.sh` یا `get.ps1` و بازیابی کلیدها:
```bash
# نصب Chezmoi و اعمال دات‌فایل‌ها
chezmoi init --apply git@github.com:mehdichamani/dotfiles.git
```
مخزن دات‌فایلز با دسترسی SSH کلون شده و به واسطه استخراج خودکار کلید `chezmoi-git-crypt.key`، تمامی فایل‌های محرمانه سیستم به طور شفاف در دسترس قرار می‌گیرند.
