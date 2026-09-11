from pathlib import Path
import os
import shutil
import re
import requests

NEW_FOLDER = "/mnt/ssd/media/new"
MOVIES_FOLDER = "/mnt/ssd/media/Movies"
TV_FOLDER = "/mnt/ssd/media/Series"

CONFIG_FILE = Path.home() / ".config" / "secrets" / "jellyfin.env"
EXAMPLE_FILE = Path.home() / ".config" / "secrets" / "jellyfin.env.example"

def load_config():
    if not CONFIG_FILE.is_file():
        print(f"\n❌ Error: Configuration file not found at:\n   {CONFIG_FILE}")
        print("\nPlease create this file with your Jellyfin credentials:")
        if EXAMPLE_FILE.is_file():
            print(f"   cp {EXAMPLE_FILE} {CONFIG_FILE}")
        else:
            print("   JELLYFIN_URL=http://localhost:8096")
            print("   JELLYFIN_API_KEY=your_api_key_here\n")
        exit(1)

    url = "http://localhost:8096"
    api_key = ""

    try:
        for line in CONFIG_FILE.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                k, v = k.strip(), v.strip().strip("'\"")
                if k == "JELLYFIN_URL":
                    url = v
                elif k == "JELLYFIN_API_KEY":
                    api_key = v
    except Exception as e:
        print(f"\n❌ Error reading configuration file ({CONFIG_FILE}): {e}")
        exit(1)

    if not api_key:
        print(f"\n❌ Error: JELLYFIN_API_KEY is missing or empty in:\n   {CONFIG_FILE}")
        exit(1)

    return url, api_key

JELLYFIN_URL, API_KEY = load_config()

def is_tv_show(filename):
    return bool(re.search(r'[ ._-]S\d{2}E\d{2}', filename, re.IGNORECASE))

def get_target_path(filename):
    if is_tv_show(filename):
        show_name_match = re.match(r"([A-Za-z0-9 ._-]+)[ ._-]S\d{2}E\d{2}", filename, re.IGNORECASE)
        if show_name_match:
            show_name = show_name_match.group(1).replace('.', ' ').replace('_', ' ').strip()
            show_folder = os.path.join(TV_FOLDER, show_name)
            target_path = os.path.join(show_folder, filename)
            return target_path
    else:
        year_match = re.search(r"(\d{4})", filename)
        if year_match:
            year = year_match.group(1)
            year_start = year_match.start()
            movie_name_part = filename[:year_start].rstrip('. _-')
            movie_name = movie_name_part.replace('.', ' ').replace('_', ' ').strip()
            movie_folder_name = f"{movie_name} {year}"
            movie_folder = os.path.join(MOVIES_FOLDER, movie_folder_name)
            target_path = os.path.join(movie_folder, filename)
            return target_path
    return None

def process_file(filename):
    source_path = os.path.join(NEW_FOLDER, filename)
    target_path = get_target_path(filename)
    if target_path:
        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        shutil.move(source_path, target_path)
        print(f"✅ Moved: {filename} → {target_path}")
    else:
        print(f"⚠️ Couldn't determine target for: {filename}")

def trigger_jellyfin_scan():
    url = f"{JELLYFIN_URL}/Library/Refresh"
    headers = {
        "X-Emby-Token": API_KEY
    }

    try:
        response = requests.post(url, headers=headers)
        print(f"🔄 Triggered Jellyfin library scan: {response.status_code}")
    except Exception as e:
        print(f"❌ Error triggering Jellyfin scan: {e}")

# اجرای اصلی
media_files = []

for filename in os.listdir(NEW_FOLDER):
    if filename.lower().endswith((".mkv", ".mp4")):
        target = get_target_path(filename)
        if target:
            media_files.append((filename, target))

if not media_files:
    print("📁 No media files (.mkv/.mp4) found for processing.")
    input("🔚 Press Enter to exit...")
    exit()

# پیش‌نمایش تغییرات
print("\n📋 Files to be moved:")
for original, target in media_files:
    print(f"  • {original} → {target}")

# دریافت تائید کاربر
try:
    input("\n❓ Press Enter to proceed or Ctrl+C to cancel...")
except KeyboardInterrupt:
    print("\n❌ Operation cancelled.")
    exit()

# انجام جابه‌جایی
for original, _ in media_files:
    process_file(original)

trigger_jellyfin_scan()
