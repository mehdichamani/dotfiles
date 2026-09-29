#!/usr/bin/env python3
"""
Agy / Antigravity Remote Live Chat Sync (Standalone)
---------------------------------------------------
اسکریپت مستقل پایش و همگام‌سازی زنده چت‌های Antigravity با ابسیدین
بدون وابستگی به هیچ فایلی از پروژه، قابل جابه‌جایی و اجرا در هر مکان.
"""

import json
import re
import time
import os
import subprocess
import base64
import shutil
import sys
import argparse

# تنظیمات پیش‌فرض اتصال ریموت (در صورت عدم وجود در ssh config، از این پیش‌فرض‌ها استفاده می‌شود)
DEFAULT_HOST = "work"
FALLBACK_IP = "217.219.149.57"
FALLBACK_PORT = "22456"
FALLBACK_USER = "mehdi"

# مسیر ذخیره لاگ زنده در ابسیدین
DEFAULT_OUTPUT = os.path.expanduser("~/Notes/live_chat.md")


def get_ssh_cmd_prefix(host_alias=DEFAULT_HOST):
    """
    بررسی اینکه آیا هاست در ~/.ssh/config تعریف شده است یا خیر؛
    در غیر این صورت از مشخصات مستقیم SSH استفاده می‌کند.
    """
    check = subprocess.run(
        ["ssh", "-G", host_alias],
        capture_output=True,
        text=True
    )
    if check.returncode == 0:
        return ["ssh", host_alias]
    return ["ssh", "-p", FALLBACK_PORT, f"{FALLBACK_USER}@{FALLBACK_IP}"]


def run_remote_ps(ps_code: str, ssh_prefix: list) -> str:
    """اجرای اسکریپت پاورشل روی سیستم ریموت با خروجی تضمین‌شده UTF-8"""
    encoded = base64.b64encode(ps_code.encode("utf-16le")).decode()
    cmd = ssh_prefix + [f"powershell -NoProfile -EncodedCommand {encoded}"]
    res = subprocess.run(cmd, capture_output=True)
    return res.stdout.decode("utf-8", errors="ignore").strip()


def get_recent_sessions(ssh_prefix: list, limit=5):
    """دریافت لیست جلسات چت اخیر از ریموت به همراه زمان و خلاصه اولین پیام"""
    print(f"🔍 در حال دریافت {limit} چت اخیر از سرور ریموت...")
    ps_code = f"""
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    Get-ChildItem -Path C:\\Users\\Mehdi\\.gemini\\antigravity-ide\\brain\\*\\.system_generated\\logs\\transcript_full.jsonl |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First {limit} |
        ForEach-Object {{
            $p = $_.FullName
            $time = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
            $firstLine = (Get-Content -Path $p -Head 15 -Encoding UTF8 | Where-Object {{ $_ -match '"type":"USER_INPUT"' }} | Select-Object -First 1)
            $p + "`t" + $time + "`t" + ($firstLine -replace "`r|`n", "")
        }}
    """
    raw = run_remote_ps(ps_code, ssh_prefix)
    sessions = []
    for line in raw.split("\n"):
        line = line.strip()
        if not line or "\t" not in line:
            continue
        parts = line.split("\t")
        path = parts[0]
        time_str = parts[1] if len(parts) > 1 else ""
        raw_snippet = parts[2] if len(parts) > 2 else ""

        snippet = "(شروع نشده یا خالی)"
        if raw_snippet:
            try:
                data = json.loads(raw_snippet)
                c = data.get("content", "")
                c = re.sub(r"<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>", "", c, flags=re.DOTALL)
                c = re.sub(r"<USER_SETTINGS_CHANGE>.*?</USER_SETTINGS_CHANGE>", "", c, flags=re.DOTALL)
                c = re.sub(r"</?USER_REQUEST>", "", c).strip()
                if c:
                    snippet = c.replace("\n", " ")[:65]
            except Exception:
                snippet = raw_snippet[:65]

        sessions.append({
            "path": path,
            "time": time_str,
            "snippet": snippet
        })
    return sessions


def select_session(sessions):
    """انتخاب تعاملی چت از طریق fzf (در صورت وجود) یا منوی شماره‌دار"""
    if not sessions:
        print("❌ هیچ چت لاگی در سیستم ریموت یافت نشد.")
        sys.exit(1)

    has_fzf = shutil.which("fzf") is not None

    if has_fzf:
        fzf_input = "\n".join(
            f"[{s['time']}] {s['snippet']}  ::  {s['path']}" for s in sessions
        )
        try:
            p = subprocess.run(
                [
                    "fzf",
                    "--prompt=انتخاب چت برای پایش > ",
                    "--height=40%",
                    "--reverse",
                    "--header=یکی از چت‌های اخیر را انتخاب کنید (Enter برای تایید):"
                ],
                input=fzf_input,
                text=True,
                capture_output=True
            )
            selected = p.stdout.strip()
            if selected and "::" in selected:
                chosen_path = selected.split("::")[-1].strip()
                for s in sessions:
                    if s["path"] == chosen_path:
                        return s
        except Exception:
            pass

    # منوی شماره‌دار ترمینال (فال‌بک)
    print("\n📋 لیست چت‌های اخیر:")
    for idx, s in enumerate(sessions, 1):
        print(f"  {idx}) [{s['time']}] {s['snippet']}")
    print(f"\nانتخاب پیش‌فرض: 1 (آخرین چت)")

    try:
        choice = input(f"شماره چت را وارد کنید [1-{len(sessions)}] (Enter=1): ").strip()
        if not choice:
            return sessions[0]
        choice_idx = int(choice) - 1
        if 0 <= choice_idx < len(sessions):
            return sessions[choice_idx]
    except (ValueError, KeyboardInterrupt):
        pass

    return sessions[0]


def main():
    parser = argparse.ArgumentParser(description="همگام‌ساز زنده چت ریموت Antigravity با ابسیدین")
    parser.add_argument("--host", default=DEFAULT_HOST, help="نام هاست SSH (پیش‌فرض: work)")
    parser.add_argument("--out", default=DEFAULT_OUTPUT, help=f"مسیر فایل خروجی مارک‌داون (پیش‌فرض: {DEFAULT_OUTPUT})")
    parser.add_argument("--count", type=int, default=5, help="تعداد چت‌های اخیر برای نمایش در منو (پیش‌فرض: 5)")
    args = parser.parse_args()

    local_out = os.path.expanduser(args.out)
    os.makedirs(os.path.dirname(local_out), exist_ok=True)

    ssh_prefix = get_ssh_cmd_prefix(args.host)

    sessions = get_recent_sessions(ssh_prefix, limit=args.count)
    selected = select_session(sessions)

    escaped_path = selected["path"].replace("'", "''")
    print(f"\n🎯 چت انتخاب‌شده: [{selected['time']}] {selected['snippet']}")
    print(f"📂 فایل در سرور: {selected['path']}")
    print(f"📝 مسیر فایل خروجی محلی: {local_out}")
    print(f"👀 در حال پایش زنده چت (خروج با Ctrl+C)...\n")

    ps_read = f"""
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    if (Test-Path '{escaped_path}') {{
        [System.IO.File]::ReadAllText('{escaped_path}', [System.Text.Encoding]::UTF8)
    }}
    """
    encoded_ps = base64.b64encode(ps_read.encode("utf-16le")).decode()

    last_content_len = 0

    while True:
        try:
            res = subprocess.run(
                ssh_prefix + [f"powershell -NoProfile -EncodedCommand {encoded_ps}"],
                capture_output=True
            )
            raw_data = res.stdout.decode("utf-8", errors="ignore").strip()

            if raw_data and len(raw_data) != last_content_len:
                last_content_len = len(raw_data)
                lines = raw_data.split("\n")

                with open(local_out, "w", encoding="utf-8") as out:
                    out.write(f"# 🤖 لاگ زنده چت ریموت (Agy / Antigravity)\n")
                    out.write(f"> **زمان جلسه:** {selected['time']}  \n")
                    out.write(f"> **موضوع:** {selected['snippet']}\n\n---\n\n")

                    for line in lines:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            data = json.loads(line)
                            step_type = data.get("type")
                            content = data.get("content", "")

                            if step_type == "USER_INPUT":
                                clean = re.sub(r"<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>", "", content, flags=re.DOTALL)
                                clean = re.sub(r"<USER_SETTINGS_CHANGE>.*?</USER_SETTINGS_CHANGE>", "", clean, flags=re.DOTALL)
                                clean = re.sub(r"</?USER_REQUEST>", "", clean).strip()
                                if clean:
                                    out.write(f"## 🧑‍💻 کاربر:\n\n{clean}\n\n---\n\n")
                            elif step_type == "PLANNER_RESPONSE":
                                if content:
                                    out.write(f"### 🤖 ایجنت:\n\n{content}\n\n---\n\n")
                        except Exception:
                            pass
                print(f"✅ فایل ابسیدین با موفقیت بروز شد ({time.strftime('%H:%M:%S')})")
        except Exception as e:
            print(f"⚠️ خطای موقت: {e}")

        time.sleep(3)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n👋 اسکریپت متوقف شد.")
