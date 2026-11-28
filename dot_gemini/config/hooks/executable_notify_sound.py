#!/usr/bin/env python3
"""Play non-blocking desktop sound alerts for Antigravity lifecycle hooks."""

from __future__ import annotations

import fcntl
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

SOUNDS_DIR = Path(__file__).resolve().parent / "sounds"
SOUND_COMPLETE = SOUNDS_DIR / "done.wav"
SOUND_ERROR = SOUNDS_DIR / "error.wav"
SOUND_QUESTION = SOUNDS_DIR / "question.wav"

COOLDOWN_SECONDS = 4.0
LOCK_FILE = Path("/tmp/agy-notify-sound.lock")

ERROR_REASONS = {
    "ERROR",
    "MAX_INVOCATIONS",
    "MAX_FORCED_INVOCATIONS",
    "MAX_TOKEN_BUDGET_EXCEEDED",
}


def should_play(cooldown: float = COOLDOWN_SECONDS) -> bool:
    """Rate-limit sound playback across concurrent or rapid hook invocations."""
    now = time.monotonic()
    try:
        with LOCK_FILE.open("a+") as fh:
            fcntl.flock(fh, fcntl.LOCK_EX)
            fh.seek(0)
            raw = fh.read().strip()
            last_ts = float(raw) if raw else 0.0
            if last_ts > 0 and (now - last_ts) < cooldown:
                return False
            fh.seek(0)
            fh.truncate()
            fh.write(f"{now:.3f}\n")
            fh.flush()
            return True
    except OSError:
        return True


def play_sound(sound_path: Path) -> None:
    """Spawn pw-play detached in the background so the hook never blocks."""
    player = shutil.which("pw-play") or shutil.which("paplay")
    if not player or not sound_path.is_file():
        return
    if not should_play():
        return
    subprocess.Popen(
        [player, str(sound_path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        payload = {}

    event = payload.get("hookEventName", "")

    if event == "Stop":
        reason = payload.get("terminationReason", "")
        if reason != "USER_CANCELED":
            if reason in ERROR_REASONS or payload.get("error"):
                play_sound(SOUND_ERROR)
            elif payload.get("fullyIdle") is not False:
                play_sound(SOUND_COMPLETE)
        print(json.dumps({"decision": "allow"}))
        return

    if event == "PreToolUse":
        tool_name = payload.get("toolCall", {}).get("name", "")
        if tool_name == "ask_question":
            play_sound(SOUND_QUESTION)
        print(json.dumps({"decision": "allow"}))
        return

    print("{}")


if __name__ == "__main__":
    main()
