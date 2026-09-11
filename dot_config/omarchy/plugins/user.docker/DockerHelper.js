.pragma library

// Parse single line of docker ps JSON
function parseContainer(line) {
  if (!line || !line.trim()) return null;
  try {
    var raw = JSON.parse(line.trim());
    var labels = parseLabels(raw.Labels || "");
    var composeProject = labels["com.docker.compose.project"] || "";
    var composeService = labels["com.docker.compose.service"] || "";
    var composeWorkingDir = labels["com.docker.compose.project.working_dir"] || "";
    var composeConfigFile = labels["com.docker.compose.project.config_files"] || "";

    var state = (raw.State || "").toLowerCase();
    var isRunning = state === "running";

    // Clean image name for display (strip sha256 or registry if long)
    var image = raw.Image || "";
    var cleanImage = image;
    if (cleanImage.indexOf("/") !== -1) {
      var segs = cleanImage.split("/");
      cleanImage = segs[segs.length - 1];
    }
    if (cleanImage.indexOf("sha256:") === 0) {
      cleanImage = cleanImage.substring(7, 19);
    }

    var name = (raw.Names || "").replace(/^\//, "");

    return {
      id: raw.ID || "",
      name: name,
      image: image,
      shortImage: cleanImage,
      state: state,
      status: raw.Status || "",
      ports: formatPorts(raw.Ports || ""),
      isRunning: isRunning,
      isPaused: state === "paused",
      isRestarting: state === "restarting",
      isExited: state === "exited" || state === "dead",
      composeProject: composeProject,
      composeService: composeService,
      composeWorkingDir: composeWorkingDir,
      composeConfigFile: composeConfigFile
    };
  } catch (e) {
    return null;
  }
}

// Parse labels string formatted as "key=val,key2=val2"
function parseLabels(labelStr) {
  var labels = {};
  if (!labelStr || typeof labelStr !== "string") return labels;
  var parts = labelStr.split(",");
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i];
    var eqIdx = p.indexOf("=");
    if (eqIdx !== -1) {
      var k = p.substring(0, eqIdx).trim();
      var v = p.substring(eqIdx + 1).trim();
      labels[k] = v;
    }
  }
  return labels;
}

// Simplify port mappings for display (e.g., "8096->8096/tcp")
function formatPorts(portsStr) {
  if (!portsStr) return "";
  var list = portsStr.split(",");
  var simplified = [];
  for (var i = 0; i < list.length; i++) {
    var item = list[i].trim();
    item = item.replace(/^(?:0\.0\.0\.0|\[::\]):/, "");
    if (item && simplified.indexOf(item) === -1) {
      simplified.push(item);
    }
  }
  return simplified.slice(0, 2).join(", ");
}

// Parse entire stdout from docker ps -a
function parseDockerOutput(stdoutText) {
  var lines = (stdoutText || "").split("\n");
  var allContainers = [];
  var projectMap = {};
  var standalone = [];
  var totalRunning = 0;

  for (var i = 0; i < lines.length; i++) {
    var c = parseContainer(lines[i]);
    if (!c) continue;

    allContainers.push(c);
    if (c.isRunning) totalRunning++;

    if (c.composeProject) {
      var projName = c.composeProject;
      if (!projectMap[projName]) {
        projectMap[projName] = {
          name: projName,
          workingDir: c.composeWorkingDir,
          configFile: c.composeConfigFile,
          containers: [],
          runningCount: 0,
          totalCount: 0
        };
      }
      projectMap[projName].containers.push(c);
      projectMap[projName].totalCount++;
      if (c.isRunning) {
        projectMap[projName].runningCount++;
      }
    } else {
      standalone.push(c);
    }
  }

  // Convert projectMap to array
  var projects = [];
  for (var p in projectMap) {
    if (projectMap.hasOwnProperty(p)) {
      var proj = projectMap[p];
      proj.allRunning = proj.runningCount === proj.totalCount && proj.totalCount > 0;
      proj.anyRunning = proj.runningCount > 0;
      // Sort containers in project
      proj.containers.sort(function(a, b) {
        if (a.isRunning && !b.isRunning) return -1;
        if (!a.isRunning && b.isRunning) return 1;
        return a.name.localeCompare(b.name);
      });
      projects.push(proj);
    }
  }

  // Sort projects alphabetically
  projects.sort(function(a, b) {
    return a.name.localeCompare(b.name);
  });

  // Sort standalone containers: running first, then name
  standalone.sort(function(a, b) {
    if (a.isRunning && !b.isRunning) return -1;
    if (!a.isRunning && b.isRunning) return 1;
    return a.name.localeCompare(b.name);
  });

  return {
    containers: allContainers,
    projects: projects,
    standalone: standalone,
    totalRunning: totalRunning,
    totalCount: allContainers.length
  };
}

// State color indicator mapping
function statusColor(state, foreground, accent, urgent, dim) {
  var s = (state || "").toLowerCase();
  if (s === "running") return accent;
  if (s === "paused" || s === "restarting") return "#EBCB8B"; // Warm amber
  if (s === "dead" || s === "error") return urgent;
  return dim; // Exited / stopped
}

function statusGlyph(state) {
  var s = (state || "").toLowerCase();
  if (s === "running") return "󰐊";
  if (s === "paused") return "󰏤";
  if (s === "restarting") return "󰑐";
  return "󰓛";
}

function statusDescription(state, status) {
  var s = (state || "").toLowerCase();
  if (s === "running") return status || "Running";
  if (s === "paused") return "Paused";
  if (s === "restarting") return "Restarting...";
  if (s === "exited") return status || "Exited";
  return status || state;
}
