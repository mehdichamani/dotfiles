#!/usr/bin/env python3
"""
Collector for external drives and partitions.
Identifies removable/USB/hotplug disks, partitions, mount status, and usage.
Always outputs a clean JSON payload.
"""

import json
import os
import shutil
import subprocess
import sys


def format_bytes(size_bytes: int | float) -> str:
    if size_bytes <= 0:
        return "0 B"
    units = ["B", "KB", "MB", "GB", "TB", "PB"]
    val = float(size_bytes)
    idx = 0
    while val >= 1024.0 and idx < len(units) - 1:
        val /= 1024.0
        idx += 1
    return f"{val:.1f} {units[idx]}" if idx > 0 else f"{int(val)} B"


def get_critical_disks(blockdevices: list) -> set[str]:
    """Finds parent disk names hosting critical OS mounts (root, boot, home, var, swap)."""
    critical = set()
    critical_mount_prefixes = ("/", "/boot", "/home", "/var", "[SWAP]")

    def check(node: dict, current_disk: str | None = None):
        disk_name = current_disk
        if node.get("type") == "disk":
            disk_name = node.get("name")

        mounts = node.get("mountpoints") or []
        for m in mounts:
            if not m:
                continue
            if m in ("/", "/boot", "/home", "[SWAP]") or m.startswith("/var/") or m.startswith("/home/"):
                if disk_name:
                    critical.add(disk_name)

        for child in node.get("children") or []:
            check(child, disk_name)

    for dev in blockdevices:
        check(dev)

    return critical


def is_external_drive(dev: dict, critical_disks: set[str]) -> bool:
    name = dev.get("name") or ""
    if name in critical_disks:
        return False

    # Block zram, loop, and dm devices from top-level
    if name.startswith(("loop", "zram", "dm-")):
        return False

    tran = str(dev.get("tran") or "").lower()
    rm = bool(dev.get("rm"))
    hotplug = bool(dev.get("hotplug"))

    if tran in ("usb", "ieee1394"):
        return True
    if rm or hotplug:
        return True

    # Check /sys/block path for usb
    if name:
        try:
            sys_path = os.path.realpath(f"/sys/block/{name}")
            if "/usb" in sys_path:
                return True
        except Exception:
            pass

    return False


def get_mount_usage(mountpoint: str) -> dict:
    try:
        usage = shutil.disk_usage(mountpoint)
        total = usage.total
        free = usage.free
        used = usage.used
        pct = int(round((used / total) * 100)) if total > 0 else 0
        return {
            "total_bytes": total,
            "free_bytes": free,
            "used_bytes": used,
            "total_str": format_bytes(total),
            "free_str": format_bytes(free),
            "used_str": format_bytes(used),
            "percent_used": pct,
        }
    except Exception:
        return {
            "total_bytes": 0,
            "free_bytes": 0,
            "used_bytes": 0,
            "total_str": "Unknown",
            "free_str": "Unknown",
            "used_str": "Unknown",
            "percent_used": 0,
        }


def collect():
    cmd = [
        "lsblk",
        "-J",
        "-b",
        "-o",
        "NAME,PATH,MODEL,SIZE,TYPE,TRAN,FSTYPE,LABEL,MOUNTPOINTS,RM,HOTPLUG,ROTA,UUID",
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=True)
        raw_data = json.loads(proc.stdout)
    except Exception as e:
        return {
            "ok": False,
            "error": str(e),
            "drives": [],
            "drive_count": 0,
            "mounted_partition_count": 0,
        }

    blockdevices = raw_data.get("blockdevices") or []
    critical_disks = get_critical_disks(blockdevices)

    drives = []
    total_mounted_parts = 0

    for dev in blockdevices:
        if dev.get("type") != "disk":
            continue
        if not is_external_drive(dev, critical_disks):
            continue

        raw_size = dev.get("size") or 0
        drive_model = (dev.get("model") or "External Drive").strip()
        drive_path = dev.get("path") or f"/dev/{dev.get('name')}"
        drive_name = dev.get("name") or ""
        tran = (dev.get("tran") or "usb").upper()

        partitions = []
        drive_is_mounted = False

        children = dev.get("children") or []
        if not children:
            # Whole disk filesystem (e.g. unpartitioned USB flash drive)
            fstype = dev.get("fstype")
            mountpoints = [m for m in (dev.get("mountpoints") or []) if m]
            is_mounted = len(mountpoints) > 0
            if is_mounted:
                drive_is_mounted = True
                total_mounted_parts += 1

            primary_mount = mountpoints[0] if is_mounted else ""
            usage = get_mount_usage(primary_mount) if is_mounted else None

            partitions.append(
                {
                    "name": drive_name,
                    "path": drive_path,
                    "label": (dev.get("label") or drive_model).strip(),
                    "fstype": (fstype or "raw").upper(),
                    "size_bytes": raw_size,
                    "size_str": format_bytes(raw_size),
                    "is_mounted": is_mounted,
                    "mountpoints": mountpoints,
                    "primary_mount": primary_mount,
                    "uuid": dev.get("uuid") or "",
                    "usage": usage,
                }
            )
        else:
            for child in children:
                c_mountpoints = [m for m in (child.get("mountpoints") or []) if m]
                c_mounted = len(c_mountpoints) > 0
                if c_mounted:
                    drive_is_mounted = True
                    total_mounted_parts += 1

                c_primary_mount = c_mountpoints[0] if c_mounted else ""
                c_usage = get_mount_usage(c_primary_mount) if c_mounted else None
                c_size = child.get("size") or 0

                partitions.append(
                    {
                        "name": child.get("name") or "",
                        "path": child.get("path") or f"/dev/{child.get('name')}",
                        "label": (child.get("label") or child.get("name") or "Partition").strip(),
                        "fstype": (child.get("fstype") or "unknown").upper(),
                        "size_bytes": c_size,
                        "size_str": format_bytes(c_size),
                        "is_mounted": c_mounted,
                        "mountpoints": c_mountpoints,
                        "primary_mount": c_primary_mount,
                        "uuid": child.get("uuid") or "",
                        "usage": c_usage,
                    }
                )

        drives.append(
            {
                "name": drive_name,
                "path": drive_path,
                "model": drive_model,
                "tran": tran,
                "size_bytes": raw_size,
                "size_str": format_bytes(raw_size),
                "is_mounted": drive_is_mounted,
                "partitions": partitions,
            }
        )

    return {
        "ok": True,
        "drives": drives,
        "drive_count": len(drives),
        "mounted_partition_count": total_mounted_parts,
    }


if __name__ == "__main__":
    data = collect()
    print(json.dumps(data, indent=2))
