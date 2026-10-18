.pragma library

// Parse collector JSON output safely
function parseSyncthingOutput(stdoutText) {
  var emptyState = {
    isAvailable: false,
    overallStatus: "attention",
    error: "",
    myID: "",
    uptime: 0,
    guiUrl: "http://127.0.0.1:8384",
    totalInBytes: 0,
    totalOutBytes: 0,
    folders: [],
    devices: [],
    totalFolders: 0,
    syncingFolders: 0,
    idleFolders: 0,
    errorFolders: 0,
    totalDevices: 0,
    connectedDevices: 0
  };

  if (!stdoutText || !stdoutText.trim()) return emptyState;

  try {
    var data = JSON.parse(stdoutText.trim());
    return {
      isAvailable: !!data.isAvailable,
      overallStatus: data.overallStatus || (data.isAvailable ? "ok" : "attention"),
      error: data.error || "",
      myID: data.myID || "",
      uptime: data.uptime || 0,
      guiUrl: data.guiUrl || "http://127.0.0.1:8384",
      totalInBytes: data.totalInBytes || 0,
      totalOutBytes: data.totalOutBytes || 0,
      folders: data.folders || [],
      devices: data.devices || [],
      totalFolders: data.totalFolders || 0,
      syncingFolders: data.syncingFolders || 0,
      idleFolders: data.idleFolders || 0,
      errorFolders: data.errorFolders || 0,
      totalDevices: data.totalDevices || 0,
      connectedDevices: data.connectedDevices || 0
    };
  } catch (e) {
    return emptyState;
  }
}

// Device status glyph
function deviceStatusGlyph(dev) {
  if (!dev) return "󰅖";
  if (dev.paused) return "󰏤";
  if (!dev.connected) return "󰅖";
  if (dev.completion !== undefined && dev.completion < 100) return "󰑐";
  return "󰄬";
}

// Glyph icon for folder status
function folderStatusGlyph(folder) {
  if (!folder) return "󰅖";
  if (folder.errors > 0 || folder.state === "error") return "󰅖";
  if (folder.paused) return "󰏤";
  if (folder.state === "syncing" || folder.state === "sync-preparing") return "󰑐";
  if (folder.state === "scanning") return "󰍉";
  return "󰄬";
}

// Status text summary for folder
function folderStatusSummary(folder) {
  if (!folder) return "Unknown";
  if (folder.errors > 0) return "Error (" + folder.errors + ")";
  if (folder.paused) return "Paused";
  if (folder.state === "syncing") {
    return "Syncing (" + (folder.syncPercentage !== undefined ? folder.syncPercentage + "%" : "") + ")";
  }
  if (folder.state === "scanning") return "Scanning";
  if (folder.state === "sync-preparing") return "Preparing";
  if (folder.state === "idle") return "Up to Date";
  return folder.state || "Idle";
}

// Device status summary
function deviceStatusSummary(dev) {
  if (!dev) return "Disconnected";
  if (dev.statusText) return dev.statusText;
  if (dev.paused) return "Paused";
  if (!dev.connected) return "Disconnected";
  if (dev.completion !== undefined && dev.completion < 100) {
    return "Syncing (" + Math.round(dev.completion) + "%)";
  }
  return "Up to Date";
}

// Human readable bytes format
function formatBytes(bytes) {
  if (!bytes || bytes <= 0) return "0 B";
  var k = 1024;
  var sizes = ["B", "KB", "MB", "GB", "TB"];
  var i = Math.floor(Math.log(bytes) / Math.log(k));
  if (i >= sizes.length) i = sizes.length - 1;
  return (bytes / Math.pow(k, i)).toFixed(i === 0 ? 0 : 1) + " " + sizes[i];
}
