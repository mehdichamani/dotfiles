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
