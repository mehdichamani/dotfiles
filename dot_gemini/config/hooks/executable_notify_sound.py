#!/usr/bin/env python3
"""Play non-blocking desktop sound alerts for Antigravity lifecycle hooks."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

SOUNDS_DIR = Path(__file__).resolve().parent / "sounds"
SOUND_COMPLETE = SOUNDS_DIR / "done.wav"
SOUND_ERROR = SOUNDS_DIR / "error.wav"
SOUND_QUESTION = SOUNDS_DIR / "question.wav"

ERROR_REASONS = {
    "ERROR",
    "MAX_INVOCATIONS",
    "MAX_FORCED_INVOCATIONS",
    "MAX_TOKEN_BUDGET_EXCEEDED",
}


def play_sound(sound_path: Path) -> None:
    """Spawn pw-play detached in the background so the hook never blocks."""
    player = shutil.which("pw-play") or shutil.which("paplay")
    if not player or not sound_path.is_file():
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
            else:
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
