.pragma library

function getStatusBadge(driveData) {
  var count = (driveData && driveData.drive_count !== undefined) ? driveData.drive_count : 0;
  if (count > 0) {
    return "󰋊 " + count;
  }
  return "󰋊";
}

function getStatusTooltip(driveData) {
  var count = (driveData && driveData.drive_count !== undefined) ? driveData.drive_count : 0;
  if (count === 0) {
    return "External Drives (None Connected)";
  }
  var mounted = (driveData && driveData.mounted_partition_count !== undefined) ? driveData.mounted_partition_count : 0;
  return count + (count === 1 ? " External Drive" : " External Drives") +
         " (" + mounted + " mounted partition" + (mounted === 1 ? "" : "s") + ")";
}

function getUsagePercent(partition) {
  if (partition && partition.usage && partition.usage.percent_used !== undefined) {
    return partition.usage.percent_used;
  }
  return 0;
}

function getFsBadgeColor(fstype) {
  var fs = String(fstype || "").toUpperCase();
  if (fs === "NTFS") return "#268bd2";
  if (fs === "BTRFS") return "#2aa198";
  if (fs === "EXT4") return "#859900";
  if (fs === "EXFAT" || fs === "VFAT" || fs === "FAT32") return "#b58900";
  return "#6c71c4";
}
