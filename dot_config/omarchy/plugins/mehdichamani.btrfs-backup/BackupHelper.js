// BackupHelper.js - Helper functions for Btrfs Backup Omarchy Shell Plugin
// Fully Nerd Font compliant, zero emojis, rich countdown, and status logic

function parseStatusOutput(rawJson) {
  var defaultData = {
    status: "idle",
    message: "No active backup state",
    last_backup_type: "none",
    cycle_day: 0,
    cycle_id: "none",
    total_snapshots: 0,
    backup_disk_uuid: "33a3cf69-9264-4d71-8d96-16dc1a72b39a",
    backup_disk_connected: false,
    backup_disk_mounted: false,
    mount_point: "",
    storage_used_bytes: 0,
    storage_avail_bytes: 0,
    storage_used_human: "0B",
    storage_avail_human: "0B",
    last_success_timestamp: null,
    next_backup_timestamp: null,
    timer_schedule: "Unknown",
    timer_active: false,
    updated_at: ""
  };

  if (!rawJson || typeof rawJson !== "string") return defaultData;

  try {
    var parsed = JSON.parse(rawJson);
    if (parsed.cycle_day === undefined && parsed.cycle_count !== undefined) {
      parsed.cycle_day = parsed.cycle_count;
    }
    if (parsed.cycle_id === undefined && parsed.current_cycle_id !== undefined) {
      parsed.cycle_id = parsed.current_cycle_id;
    }
    if (parsed.backup_disk_mounted === undefined && parsed.current_cycle_id !== undefined) {
      parsed.backup_disk_mounted = true;
    }
    return Object.assign({}, defaultData, parsed);
  } catch (e) {
    return defaultData;
  }
}

function isConnected(data) {
  if (!data) return false;
  return data.backup_disk_connected === true || data.backup_disk_mounted === true;
}

function isMounted(data) {
  if (!data) return false;
  return data.backup_disk_mounted === true;
}

function isEjected(data) {
  if (!data) return false;
  return data.status === "ejected";
}

function isRunning(data) {
  if (!data) return false;
  return data.status === "running";
}

function isError(data) {
  if (!data) return false;
  return data.status === "error";
}

function canBackup(data) {
  if (!data) return false;
  return isConnected(data) && !isRunning(data);
}

function formatRelativeTime(timestamp) {
  if (!timestamp || timestamp <= 0) return "Never";
  var now = Math.floor(Date.now() / 1000);
  var diff = now - timestamp;

  if (diff < 60) return "Just now";
  if (diff < 3600) return Math.floor(diff / 60) + "m ago";
  if (diff < 86400) return Math.floor(diff / 3600) + "h " + Math.floor((diff % 3600) / 60) + "m ago";
  return Math.floor(diff / 86400) + "d ago";
}

function formatDateTime(timestamp) {
  if (!timestamp || timestamp <= 0) return "No backup yet";
  var d = new Date(timestamp * 1000);
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric" }) + " " +
         d.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: false });
}

// Countdown to next scheduled / cooldown backup
function formatCountdown(targetTs) {
  if (!targetTs || targetTs <= 0) return "Not Scheduled";
  var now = Math.floor(Date.now() / 1000);
  var diff = targetTs - now;

  if (diff <= 0) return "Ready / Due Now";
  var hours = Math.floor(diff / 3600);
  var mins = Math.floor((diff % 3600) / 60);
  var secs = diff % 60;

  if (hours > 24) {
    var days = Math.floor(hours / 24);
    var remHours = hours % 24;
    return "in " + days + "d " + remHours + "h";
  }
  if (hours > 0) {
    return "in " + hours + "h " + mins + "m";
  }
  return "in " + mins + "m " + secs + "s";
}

function getStoragePercent(usedBytes, availBytes) {
  var total = (usedBytes || 0) + (availBytes || 0);
  if (total <= 0) return 0;
  return Math.min(100, Math.max(0, Math.round((usedBytes / total) * 100)));
}

// TopBar Badge Icon & Text (Nerd Font strictly)
function getStatusBadge(data) {
  if (!data) return "󰁯";
  if (isRunning(data)) return "󰑐 Run";
  if (isEjected(data)) return "󰚃 Eject";
  if (!isConnected(data)) return "󰁯 Off";
  if (!isMounted(data)) return "󱊞 Unmount";
  if (data.cycle_day > 0) return "󰁯 D" + data.cycle_day;
  return "󰁯 Ready";
}

function getStatusTooltip(data) {
  if (!data) return "Btrfs Backup";
  if (isRunning(data)) return "Btrfs Backup: Snapshot transfer active";
  if (isError(data)) return "Btrfs Backup: Error - " + (data.message || "");
  if (isEjected(data)) return "Btrfs Backup: Drive safely unmounted and ready to unplug";
  if (!isConnected(data)) return "Btrfs Backup: External backup SSD disconnected";
  if (!isMounted(data)) return "Btrfs Backup: Drive connected but unmounted";
  return "Btrfs Backup: Day " + (data.cycle_day || 0) + "/15 · " + (data.storage_avail_human || "0B") + " Free";
}

function formatSchedule(data) {
  if (!data || !data.timer_schedule || data.timer_schedule === "Unknown") {
    if (data && data.timer_active === true) {
      return "Daily at 22:00 (Active)";
    }
    return "Timer Inactive";
  }
  var sched = data.timer_schedule;
  var statusSuffix = (data.timer_active === false) ? " (Inactive)" : " (Active)";

  if (sched.indexOf("*-*-* ") === 0) {
    var timePart = sched.substring(6);
    return "Daily at " + timePart + statusSuffix;
  }
  return sched + statusSuffix;
}
