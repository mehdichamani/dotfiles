#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

CACHE_FILE = Path.home() / ".cache" / "omarchy" / "antigravity_gemini.json"
CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
CACHE_TTL = 30  # seconds

def get_proxy_env():
    env = os.environ.copy()
    proxy_state = Path.home() / ".config" / "proxy_state"
    target_proxy = ""
    if proxy_state.exists():
        try:
            target_proxy = proxy_state.read_text(encoding="utf-8").strip()
        except Exception:
            pass

    if not target_proxy:
        target_proxy = "http://localhost:10808"

    env["http_proxy"] = target_proxy
    env["https_proxy"] = target_proxy
    env["HTTP_PROXY"] = target_proxy
    env["HTTPS_PROXY"] = target_proxy
    env["all_proxy"] = target_proxy
    env["ALL_PROXY"] = target_proxy
    env["no_proxy"] = "localhost,127.0.0.1,::1,localaddress,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
    env["NO_PROXY"] = env["no_proxy"]
    return env

def read_cache():
    if not CACHE_FILE.exists():
        return None
    try:
        data = json.loads(CACHE_FILE.read_text(encoding="utf-8"))
        if time.time() - data.get("timestamp", 0) < CACHE_TTL:
            return data
    except Exception:
        pass
    return None

def format_relative_reset(reset_str):
    if not reset_str:
        return ""
    s = reset_str.strip()
    dt = None
    try:
        if s.endswith("Z"):
            dt = datetime.fromisoformat(s[:-1] + "+00:00")
        elif "+" in s or "-" in s:
            try:
                dt = datetime.fromisoformat(s)
            except Exception:
                dt = datetime.strptime(s, "%Y-%m-%d %H:%M %z")
    except Exception:
        pass

    if not dt:
        return reset_str

    now = datetime.now(timezone.utc)
    diff = dt - now
    total_seconds = int(diff.total_seconds())

    if total_seconds <= 0:
        return "now"

    days = total_seconds // 86400
    hours = (total_seconds % 86400) // 3600
    minutes = (total_seconds % 3600) // 60

    if days > 1:
        return f"{days} days"
    elif days == 1:
        return "1 day"
    elif hours > 1:
        return f"{hours} hours"
    elif hours == 1:
        return "1 hour"
    elif minutes > 1:
        return f"{minutes} minutes"
    elif minutes == 1:
        return "1 minute"
    else:
        return "less than a minute"

def fetch_usage():
    agy_bin = Path.home() / ".local" / "bin" / "agy"
    cmd = [str(agy_bin), "-p", "/usage"]
    if not agy_bin.exists():
        cmd = ["agy", "-p", "/usage"]

    env = get_proxy_env()

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=25, env=env)
        output = proc.stdout
    except Exception as e:
        return {"ok": False, "error": str(e), "timestamp": time.time()}

    # Parse Gemini lines
    # e.g.:
    # Gemini Models          Weekly Limit Remaining     22%   2026-10-24 08:03 +0330
    # Gemini Models          Five Hour Limit Remaining  98%   2026-10-23 20:23 +0330
    five_hour_pct = None
    five_hour_reset = ""
    weekly_pct = None
    weekly_reset = ""

    for line in output.splitlines():
        line = line.strip()
        if "Gemini Models" not in line:
            continue
        m_5h = re.search(r"Five Hour Limit Remaining\s+(\d+)%\s+(.+)", line)
        if m_5h:
            five_hour_pct = int(m_5h.group(1))
            five_hour_reset = m_5h.group(2).strip()

        m_wk = re.search(r"Weekly Limit Remaining\s+(\d+)%\s+(.+)", line)
        if m_wk:
            weekly_pct = int(m_wk.group(1))
            weekly_reset = m_wk.group(2).strip()

    if five_hour_pct is None and weekly_pct is None:
        err_msg = proc.stderr.strip() or "No Gemini quota found in output"
        return {"ok": False, "error": err_msg, "raw": output, "timestamp": time.time()}

    min_pct = min(
        [p for p in (five_hour_pct, weekly_pct) if p is not None],
        default=0
    )

    data = {
        "ok": True,
        "five_hour_percent": five_hour_pct if five_hour_pct is not None else 0,
        "five_hour_reset": five_hour_reset,
        "five_hour_reset_rel": format_relative_reset(five_hour_reset),
        "weekly_percent": weekly_pct if weekly_pct is not None else 0,
        "weekly_reset": weekly_reset,
        "weekly_reset_rel": format_relative_reset(weekly_reset),
        "min_percent": min_pct,
        "timestamp": time.time(),
        "time_str": time.strftime("%H:%M:%S")
    }

    try:
        CACHE_FILE.write_text(json.dumps(data), encoding="utf-8")
    except Exception:
        pass

    return data

def main():
    force = "--force" in sys.argv
    if not force:
        cached = read_cache()
        if cached:
            print(json.dumps(cached))
            return

    res = fetch_usage()
    print(json.dumps(res))

if __name__ == "__main__":
    main()
