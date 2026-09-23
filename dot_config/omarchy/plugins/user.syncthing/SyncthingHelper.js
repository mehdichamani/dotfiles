.pragma library

// Parse collector JSON output safely
function parseSyncthingOutput(stdoutText) {
  var emptyState = {
    isAvailable: false,
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

// Color mapping for folder badges and status
function folderStatusColor(folder, foreground, accent, urgent, dim) {
  if (!folder) return dim;
  if (folder.errors > 0 || folder.state === "error") return urgent;
  if (folder.paused) return "#EBCB8B"; // Amber
  if (folder.state === "syncing" || folder.state === "sync-preparing" || folder.state === "scanning") return accent;
  return dim; // Up to date / idle
}

// Color mapping for devices
function deviceStatusColor(dev, foreground, accent, urgent, dim) {
  if (!dev) return dim;
  if (dev.paused) return "#EBCB8B";
  if (dev.connected) return accent;
  return dim;
}

// Status text summary for folder
function folderStatusSummary(folder) {
  if (!folder) return "Unknown";
  if (folder.errors > 0) return "Error (" + folder.errors + ")";
  if (folder.paused) return "Paused";
  if (folder.state === "syncing") {
    return "Syncing " + (folder.syncPercentage !== undefined ? folder.syncPercentage + "%" : "");
  }
  if (folder.state === "scanning") return "Scanning...";
  if (folder.state === "sync-preparing") return "Preparing...";
  if (folder.state === "idle") return "Up to date";
  return folder.state || "Idle";
}

// Glyph icon for folder status
function folderStatusGlyph(folder) {
  if (!folder) return "󰅖";
  if (folder.errors > 0 || folder.state === "error") return "󰅖";
  if (folder.paused) return "󰏤";
  if (folder.state === "syncing") return "󰑐";
  if (folder.state === "scanning") return "󰍉";
  return "󰄬";
}

// Device status summary
function deviceStatusSummary(dev) {
  if (!dev) return "Offline";
  if (dev.paused) return "Paused";
  if (dev.connected) {
    if (dev.address) return "Connected (" + dev.address.split(":")[0] + ")";
    return "Connected";
  }
  return "Disconnected";
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
