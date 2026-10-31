#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Todoist backend script for Omarchy status bar widget and notifications.
Handles listing (with subtasks), adding (with natural language due parsing),
completing, deleting, and desktop alerts via Omarchy notification system.
"""
from datetime import datetime, timezone
from pathlib import Path
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API_BASE_URL = "https://api.todoist.com/api/v1"
SECRETS_DIR = Path.home() / ".ssh" / "secrets"
ENV_FILE = SECRETS_DIR / "todoist.env"

CACHE_FILE = Path.home() / ".cache" / "omarchy" / "todoist_tasks.json"
CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
CACHE_TTL = 20  # seconds

ALERT_STATE_FILE = Path.home() / ".cache" / "omarchy" / "todoist_alerted.json"


def get_token():
    """Retrieve Todoist Personal API Token from ~/.ssh/secrets/todoist.env."""
    if not ENV_FILE.exists():
        sys.stderr.write(
            "\033[91mError: ~/.ssh/secrets/todoist.env file not found.\033[0m\n"
        )
        return ""

    try:
        content = ENV_FILE.read_text(encoding="utf-8")
        for line in content.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                if k.strip() == "TODOIST_API_TOKEN":
                    return v.strip().strip('"').strip("'")
    except Exception as e:
        sys.stderr.write(f"\033[91mError reading todoist.env: {e}\033[0m\n")
    return ""


def get_opener():
    """Build urllib opener with proxy support if configured."""
    proxy_url = ""
    proxy_state = Path.home() / ".config" / "proxy_state"
    if proxy_state.exists():
        try:
            proxy_url = proxy_state.read_text(encoding="utf-8").strip()
        except Exception:
            pass

    if not proxy_url:
        proxy_url = os.environ.get("https_proxy") or os.environ.get("http_proxy") or ""

    if proxy_url:
        proxy_handler = urllib.request.ProxyHandler({
            "http": proxy_url,
            "https": proxy_url,
        })
        return urllib.request.build_opener(proxy_handler)
    return urllib.request.build_opener()


def api_request(method, endpoint, data=None):
    """Execute authenticated HTTP request to Todoist API v1."""
    token = get_token()
    if not token:
        raise RuntimeError("TODOIST_API_TOKEN is not set in ~/.ssh/secrets/todoist.env")

    url = f"{API_BASE_URL}{endpoint}"
    req_body = None
    headers = {
        "Authorization": f"Bearer {token}",
        "User-Agent": "Omarchy-Tasks-Plugin/2.0",
        "Accept": "application/json",
    }

    if data is not None:
        req_body = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, data=req_body, headers=headers, method=method)
    opener = get_opener()

    try:
        with opener.open(req, timeout=12) as resp:
            resp_body = resp.read()
            if not resp_body:
                return {}
            return json.loads(resp_body.decode("utf-8"))
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode("utf-8", errors="replace")
        if e.code == 401:
            raise RuntimeError("Todoist token is invalid or expired (401 Unauthorized)")
        elif e.code == 404:
            raise RuntimeError(f"Item not found (404 Not Found): {endpoint}")
        raise RuntimeError(f"Todoist API error ({e.code}): {err_msg}")
    except urllib.error.URLError as e:
        raise RuntimeError(f"Failed to connect to Todoist server (check network/proxy): {e.reason}")


def read_cache():
    if not CACHE_FILE.exists():
        return None
    try:
        data = json.loads(CACHE_FILE.read_text(encoding="utf-8"))
        cached_time = data.get("cached_at", 0)
        if (time.time() - cached_time) < CACHE_TTL:
            return data
    except Exception:
        pass
    return None


def write_cache(data):
    try:
        data["cached_at"] = time.time()
        CACHE_FILE.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    except Exception:
        pass


def invalidate_cache():
    try:
        if CACHE_FILE.exists():
            CACHE_FILE.unlink()
    except Exception:
        pass


def parse_due_info(due_obj):
    """Normalize due information from Todoist API v1."""
    if not due_obj or not isinstance(due_obj, dict):
        return {
            "due_date": "",
            "due_time": "",
            "due_datetime": "",
            "due_string": "",
            "is_recurring": False,
            "badge": "",
            "is_overdue": False,
        }

    raw = due_obj.get("date") or ""
    raw_string = due_obj.get("string") or ""
    is_recurring = bool(due_obj.get("is_recurring", False))

    raw_date = ""
    raw_datetime = ""
    due_time = ""
    is_overdue = False
    badge = ""

    now = datetime.now().astimezone()

    if "T" in raw:
        raw_datetime = raw
        raw_date = raw.split("T")[0]
        try:
            clean_str = raw_datetime.replace("Z", "+00:00")
            dt = datetime.fromisoformat(clean_str)
            if dt.tzinfo is None:
                dt = dt.astimezone()
            else:
                dt = dt.astimezone()

            due_time = dt.strftime("%H:%M")
            if dt < now:
                is_overdue = True

            if dt.date() == now.date():
                badge = f"󰥔 {due_time}"
            else:
                badge = f"󰥔 {dt.strftime('%b %d')} {due_time}"
        except Exception:
            badge = f"󰥔 {raw_string}"
    elif raw:
        raw_date = raw
        try:
            task_date = datetime.strptime(raw_date, "%Y-%m-%d").date()
            if task_date < now.date():
                is_overdue = True

            if task_date == now.date():
                badge = "󰸗 Today"
            else:
                badge = f"󰸗 {task_date.strftime('%b %d')}"
        except Exception:
            badge = f"󰸗 {raw_date}"

    return {
        "due_date": raw_date,
        "due_time": due_time,
        "due_datetime": raw_datetime,
        "due_string": raw_string,
        "is_recurring": is_recurring,
        "badge": badge,
        "is_overdue": is_overdue,
    }


def clean_markdown_title(text):
    """Remove markdown link formatting for clean display in title."""
    return re.sub(r"\[(.*?)\]\(.*?\)", r"\1", text)


def cmd_list(force=False):
    """Fetch and organize active tasks into a hierarchical tree with subtasks."""
    if not force:
        cached = read_cache()
        if cached:
            return cached

    raw_resp = api_request("GET", "/tasks")
    if isinstance(raw_resp, dict):
        raw_items = raw_resp.get("results", [])
    elif isinstance(raw_resp, list):
        raw_items = raw_resp
    else:
        raw_items = []

    now = datetime.now().astimezone()
    today_str = now.strftime("%Y-%m-%d")

    # First pass: map and normalize every item
    tasks_by_id = {}
    for item in raw_items:
        t_id = str(item.get("id"))
        content = (item.get("content") or "").strip()
        description = (item.get("description") or "").strip()
        due_info = parse_due_info(item.get("due"))

        tasks_by_id[t_id] = {
            "id": t_id,
            "title": clean_markdown_title(content),
            "content": content,
            "notes": description,
            "description": description,
            "priority": item.get("priority", 1),
            "order": item.get("child_order") or item.get("order") or 0,
            "parent_id": str(item.get("parent_id")) if item.get("parent_id") else None,
            "url": item.get("url") or f"https://app.todoist.com/app/task/{t_id}",
            "due_date": due_info["due_date"],
            "due_time": due_info["due_time"],
            "due_datetime": due_info["due_datetime"],
            "due_string": due_info["due_string"],
            "due_badge": due_info["badge"],
            "is_overdue": due_info["is_overdue"],
            "subtasks": [],
        }

    # Second pass: assemble hierarchy
    root_tasks = []
    for t_id, task in tasks_by_id.items():
        p_id = task["parent_id"]
        if p_id and p_id in tasks_by_id:
            tasks_by_id[p_id]["subtasks"].append(task)
        else:
            root_tasks.append(task)

    # Sort key: Overdue first (0), Today next (1), Future due next (2), No due date last (3)
    def task_sort_key(t):
        if t["is_overdue"]:
            due_rank = 0
        elif t["due_date"] == today_str:
            due_rank = 1
        elif t["due_date"]:
            due_rank = 2
        else:
            due_rank = 3
        return (
            due_rank,
            t["due_date"] or "9999",
            t["due_time"] or "99:99",
            -t["priority"],
            t["order"],
        )

    root_tasks.sort(key=task_sort_key)
    for r in root_tasks:
        r["subtasks"].sort(key=task_sort_key)

    now_str = datetime.now().strftime("%H:%M")
    result = {
        "ok": True,
        "count": len(raw_items),
        "root_count": len(root_tasks),
        "tasks": root_tasks,
        "updated_at": now_str,
        "error": "",
    }
    write_cache(result)
    return result


def cmd_add(title, notes="", parent_id=""):
    """
    Create a new task.
    Supports '@ <due_string>' syntax in title for setting due dates,
    e.g. 'Team meeting @ 18:30' or 'Call Bob @ tomorrow 5pm'.
    """
    title = title.strip()
    if not title:
        return {"ok": False, "error": "Title cannot be empty"}

    due_string = ""
    if "@" in title:
        content_part, due_part = title.split("@", 1)
        title = content_part.strip()
        due_string = due_part.strip()

    payload = {"content": title}
    if due_string:
        payload["due_string"] = due_string
    if notes:
        payload["description"] = notes
    if parent_id:
        payload["parent_id"] = parent_id

    res = api_request("POST", "/tasks", payload)
    invalidate_cache()
    task_id = str(res.get("id", ""))
    return {"ok": True, "task": {"id": task_id, "title": res.get("content", title)}}


def cmd_complete(task_id):
    """Close (complete) a task in Todoist."""
    if not task_id:
        return {"ok": False, "error": "Task ID required"}

    api_request("POST", f"/tasks/{task_id}/close")
    invalidate_cache()
    return {"ok": True, "completed_id": task_id}


def cmd_delete(task_id):
    """Delete a task permanently from Todoist."""
    if not task_id:
        return {"ok": False, "error": "Task ID required"}

    api_request("DELETE", f"/tasks/{task_id}")
    invalidate_cache()
    return {"ok": True, "deleted_id": task_id}


def cmd_prompt():
    """Display an interactive Omarchy menu popup to enter and create a task."""
    input_bin = "/usr/share/omarchy/bin/omarchy-menu-input"
    if not Path(input_bin).exists():
        input_bin = "omarchy-menu-input"

    try:
        import subprocess
        proc = subprocess.run(
            [input_bin, "New task (e.g. Meeting @ tomorrow 18:30)", "--width", "500"],
            capture_output=True,
            text=True,
            check=False,
        )
    except Exception as e:
        send_omarchy_notification("Todoist Error", f"Failed to open menu: {e}", urgency="critical")
        return {"ok": False, "error": str(e)}

    if proc.returncode != 0:
        return {"ok": False, "cancelled": True}

    task_text = (proc.stdout or "").strip()
    if not task_text:
        return {"ok": False, "cancelled": True}

    res = cmd_add(task_text)
    if res.get("ok"):
        added_title = res.get("task", {}).get("title", task_text)
        send_omarchy_notification(
            headline="Task Added",
            description=added_title,
            urgency="normal",
            sound=True,
        )
        try:
            import subprocess
            subprocess.run(
                ["omarchy-shell", "-q", "mehdichamani.tasks", "refresh"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        except Exception:
            pass
        return res
    else:
        err = res.get("error", "Failed to add task")
        send_omarchy_notification(
            headline="Failed to Add Task",
            description=err,
            urgency="critical",
            sound=True,
        )
        return res


def play_notification_sound():
    """Play notification chime using pw-play, paplay, or canberra."""
    sound_file = "/usr/share/sounds/freedesktop/stereo/message.oga"
    if Path(sound_file).exists():
        for player in ["pw-play", "paplay"]:
            try:
                import subprocess
                subprocess.Popen([player, sound_file], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return
            except Exception:
                continue
    try:
        import subprocess
        subprocess.run(["canberra-gtk-play", "-i", "message"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    except Exception:
        pass


def send_omarchy_notification(headline, description, urgency="normal", sound=True):
    """Send desktop notification using omarchy-notification-send or notify-send fallback."""
    notifier = "/usr/share/omarchy/bin/omarchy-notification-send"
    if Path(notifier).exists():
        cmd = [
            notifier,
            "-g", "󰥔",
            "-u", urgency,
            "--app-name", "Todoist",
            headline,
            description,
        ]
    else:
        cmd = [
            "notify-send",
            "-a", "Todoist",
            "-u", urgency,
            headline,
            description,
        ]

    try:
        import subprocess
        subprocess.run(cmd, check=False)
    except Exception as e:
        sys.stderr.write(f"Failed to send notification: {e}\n")

    if sound:
        play_notification_sound()


def cmd_check_alerts():
    """
    Check due tasks and fire Omarchy notifications.
    Intended to be invoked periodically by omarchy-tasks-notifier.timer.
    """
    token = get_token()
    if not token:
        return {"ok": False, "error": "Token not set"}

    try:
        raw_resp = api_request("GET", "/tasks")
        if isinstance(raw_resp, dict):
            raw_items = raw_resp.get("results", [])
        elif isinstance(raw_resp, list):
            raw_items = raw_resp
        else:
            raw_items = []
    except Exception as e:
        return {"ok": False, "error": str(e)}

    # Read alert state
    alerted = {}
    if ALERT_STATE_FILE.exists():
        try:
            alerted = json.loads(ALERT_STATE_FILE.read_text(encoding="utf-8"))
        except Exception:
            alerted = {}

    now = datetime.now().astimezone()
    fired_count = 0
    active_ids = set()

    for item in raw_items:
        t_id = str(item.get("id"))
        active_ids.add(t_id)
        content = (item.get("content") or "").strip()
        due = item.get("due") or {}
        raw = due.get("date") or ""

        if not raw:
            continue

        alert_key = f"{t_id}:{raw}"

        if "T" in raw:
            try:
                clean_str = raw.replace("Z", "+00:00")
                dt = datetime.fromisoformat(clean_str)
                if dt.tzinfo is None:
                    dt = dt.astimezone()
                else:
                    dt = dt.astimezone()

                diff_seconds = (dt - now).total_seconds()
                # Due window: trigger when due (up to 10 minutes past due), without 5-minute advance alert
                if -600 <= diff_seconds <= 0:
                    if alert_key not in alerted:
                        due_time_str = dt.strftime("%H:%M")
                        send_omarchy_notification(
                            headline=f"Reminder: {content}",
                            description=f"Due at {due_time_str}",
                            urgency="critical",
                            sound=True,
                        )
                        alerted[alert_key] = time.time()
                        fired_count += 1
            except Exception:
                pass
        else:
            try:
                task_date = datetime.strptime(raw, "%Y-%m-%d").date()
                if task_date == now.date() and 9 <= now.hour < 10:
                    if alert_key not in alerted:
                        send_omarchy_notification(
                            headline=f"Today's Task: {content}",
                            description="Due today",
                            urgency="low",
                            sound=True,
                        )
                        alerted[alert_key] = time.time()
                        fired_count += 1
            except Exception:
                pass

    current_time = time.time()
    cleaned_alerted = {}
    for k, v in alerted.items():
        item_id = k.split(":", 1)[0]
        if item_id in active_ids or (current_time - v) < 86400:
            cleaned_alerted[k] = v

    try:
        ALERT_STATE_FILE.write_text(json.dumps(cleaned_alerted), encoding="utf-8")
    except Exception:
        pass

    return {"ok": True, "alerts_fired": fired_count}


def main():
    args = sys.argv[1:]
    command = args[0] if args else "list"

    try:
        if command == "list":
            force = "--force" in args or "-f" in args
            data = cmd_list(force=force)
            print(json.dumps(data, ensure_ascii=False))

        elif command == "add":
            if len(args) < 2:
                print(json.dumps({"ok": False, "error": "Missing task title"}))
                sys.exit(1)
            title = args[1]
            notes = args[2] if len(args) > 2 else ""
            parent_id = args[3] if len(args) > 3 else ""
            res = cmd_add(title, notes, parent_id)
            print(json.dumps(res, ensure_ascii=False))

        elif command == "complete":
            if len(args) < 2:
                print(json.dumps({"ok": False, "error": "Missing task ID"}))
                sys.exit(1)
            task_id = args[1]
            res = cmd_complete(task_id)
            print(json.dumps(res, ensure_ascii=False))

        elif command == "delete":
            if len(args) < 2:
                print(json.dumps({"ok": False, "error": "Missing task ID"}))
                sys.exit(1)
            task_id = args[1]
            res = cmd_delete(task_id)
            print(json.dumps(res, ensure_ascii=False))

        elif command == "check-alerts":
            res = cmd_check_alerts()
            print(json.dumps(res, ensure_ascii=False))

        elif command == "prompt":
            res = cmd_prompt()
            print(json.dumps(res, ensure_ascii=False))

        else:
            print(json.dumps({"ok": False, "error": f"Unknown command: {command}"}))
            sys.exit(1)

    except Exception as e:
        err_res = {
            "ok": False,
            "count": 0,
            "tasks": [],
            "error": str(e),
        }
        print(json.dumps(err_res, ensure_ascii=False))
        sys.exit(1)


if __name__ == "__main__":
    main()
