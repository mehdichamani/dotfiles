#!/usr/bin/env python3
"""
Safe Eject Engine for external drives.
Flushes buffers (sync), cleanly unmounts all partitions, and powers off the drive.
Sends native desktop notifications in English.
"""

import os
from pathlib import Path
import subprocess
import sys
import time


def notify(title: str, body: str, urgency: str = "normal", icon: str = "media-removable"):
    try:
        subprocess.run(
            ["notify-send", "-a", "Drive Eject", "-u", urgency, "-i", icon, title, body],
            check=False,
        )
    except Exception:
        pass


def stop_jellyfin_if_needed(target: str, tag: str = ""):
    """Pre-unmount hook: If ejecting TUF_Data or TUF drive, gracefully stop Jellyfin container first."""
    tag_upper = (tag or "").upper()
    is_tuf = "TUF" in tag_upper or "TUF_DATA" in tag_upper
    if not is_tuf and target.startswith("/dev/"):
        # Check if the block device hosts TUF_Data label
        try:
            lbl_proc = subprocess.run(
                ["lsblk", "-nlo", "LABEL", target],
                capture_output=True,
                text=True,
                timeout=3,
            )
            if "TUF_Data" in lbl_proc.stdout:
                is_tuf = True
        except Exception:
            pass

    if is_tuf:
        setup_script = Path.home() / "projects" / "jellyfin" / "jellyfin-setup.sh"
        if not setup_script.exists():
            setup_script = Path.home() / "projects" / "jellyfin" / "setup.sh"
        if setup_script.exists():
            notify("Stopping Jellyfin...", "Gracefully stopping media server before drive ejection...", urgency="low", icon="media-playback-stop")
            try:
                subprocess.run([str(setup_script), "stop"], capture_output=True, timeout=5)
            except Exception:
                pass


def safe_eject(device_path: str, model: str = "External Drive") -> bool:
    if not device_path or not device_path.startswith("/dev/"):
        notify("Eject Error", f"Invalid device path: {device_path}", urgency="critical", icon="dialog-error")
        return False

    stop_jellyfin_if_needed(device_path, model)
    notify("Ejecting Drive...", f"Syncing file buffers for {model}...", urgency="low", icon="drive-harddisk")

    # 1. Flush memory caches to disk
    try:
        subprocess.run(["sync"], check=False)
    except Exception:
        pass

    # 2. Try udiskie-umount -f -d (force recursive unmount + poweroff drive)
    success = False
    try:
        res = subprocess.run(
            ["udiskie-umount", "-f", "-d", device_path],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if res.returncode == 0:
            success = True
    except Exception:
        pass

    # 3. Fallback: unmount all partitions via udisksctl then power off
    if not success:
        # Try unmounting partitions first
        try:
            lsblk_proc = subprocess.run(
                ["lsblk", "-nlo", "PATH", device_path],
                capture_output=True,
                text=True,
                timeout=5,
            )
            for part in lsblk_proc.stdout.splitlines():
                part = part.strip()
                if part and part != device_path:
                    subprocess.run(["udisksctl", "unmount", "-b", part, "-f"], capture_output=True, timeout=5)
        except Exception:
            pass

        # Also try unmounting the main device
        subprocess.run(["udisksctl", "unmount", "-b", device_path, "-f"], capture_output=True, timeout=5)

        # Sync and wait for udev events to settle
        subprocess.run(["sync"], check=False)
        try:
            subprocess.run(["udevadm", "settle", "--timeout=3"], check=False, timeout=4)
        except Exception:
            pass

        # Power off drive hardware with smart retries (handles transient udev/fsync locks)
        for attempt in range(4):
            po_res = subprocess.run(
                ["udisksctl", "power-off", "-b", device_path],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if po_res.returncode == 0:
                success = True
                break
            # Wait briefly before retrying if drive was momentarily busy
            time.sleep(1.2)

    if success:
        notify(
            "Safe to Unplug",
            f"{model} has been safely stopped and powered down.",
            urgency="normal",
            icon="drive-removable-media",
        )
        return True
    else:
        notify(
            "Eject Failed",
            f"Could not safely unmount or power down {model}. Check if files are open.",
            urgency="critical",
            icon="dialog-error",
        )
        return False


def unmount_partition(part_path: str, label: str = "Partition") -> bool:
    if not part_path or not part_path.startswith("/dev/"):
        return False
    stop_jellyfin_if_needed(part_path, label)
    subprocess.run(["sync"], check=False)
    res = subprocess.run(["udisksctl", "unmount", "-b", part_path], capture_output=True, text=True, timeout=10)
    if res.returncode == 0:
        notify("Partition Unmounted", f"{label} unmounted safely.", urgency="normal", icon="drive-harddisk")
        return True
    else:
        notify("Unmount Failed", f"Failed to unmount {label}: {res.stderr.strip()}", urgency="critical", icon="dialog-error")
        return False


def mount_partition(part_path: str, label: str = "Partition") -> bool:
    if not part_path or not part_path.startswith("/dev/"):
        return False
    res = subprocess.run(["udisksctl", "mount", "-b", part_path], capture_output=True, text=True, timeout=10)
    if res.returncode == 0:
        notify("Partition Mounted", f"{label} is now mounted and ready.", urgency="normal", icon="drive-harddisk")
        return True
    else:
        notify("Mount Failed", f"Failed to mount {label}: {res.stderr.strip()}", urgency="critical", icon="dialog-error")
        return False


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: eject.py <eject-drive|unmount-part|mount-part> <device_path> [label_or_model]")
        sys.exit(1)

    action = sys.argv[1]
    target = sys.argv[2]
    tag = sys.argv[3] if len(sys.argv) > 3 else "Device"

    if action == "eject-drive":
        ok = safe_eject(target, tag)
        sys.exit(0 if ok else 1)
    elif action == "unmount-part":
        ok = unmount_partition(target, tag)
        sys.exit(0 if ok else 1)
    elif action == "mount-part":
        ok = mount_partition(target, tag)
        sys.exit(0 if ok else 1)
    else:
        print(f"Unknown action: {action}")
        sys.exit(1)
