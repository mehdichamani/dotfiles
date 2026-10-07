import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var settings: ({})

  property bool installed: true
  property bool running: false
  property bool busy: statusProcess.running || actionProcess.running

  // Optimistic toggling like Tailscale
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)

  property var connections: []
  property var activeConnection: null
  property string activeName: ""
  property string activeIp: ""
  property string activeEndpoint: ""
  property string lastError: ""
  property string actionStatus: ""

  readonly property int refreshIntervalSec: {
    var v = settings ? settings.refreshIntervalSec : 15
    return Math.max(5, Math.min(3600, parseInt(v, 10) || 15))
  }

  function refresh() {
    if (!statusProcess.running) {
      statusProcess.running = true
    }
  }

  function copyToClipboard(text, label) {
    var str = String(text || "").trim()
    if (!str) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(str) + " | wl-copy"])
  }

  function toggleConnection(name) {
    if (!name || actionProcess.running) return
    var target = null
    for (var i = 0; i < connections.length; i++) {
      if (connections[i].name === name) {
        target = connections[i]
        break
      }
    }
    var isUp = target ? target.active : false
    _desired = isUp ? 0 : 1
    actionStatus = (isUp ? "Disconnecting " : "Connecting ") + name + "…"
    lastError = ""
    actionProcess.command = ["bash", "-c", isUp ? ("nmcli connection down " + Util.shellQuote(name)) : ("nmcli connection up " + Util.shellQuote(name))]
    actionProcess.running = true
  }

  function togglePrimary() {
    if (activeConnection) {
      toggleConnection(activeConnection.name)
    } else if (connections.length > 0) {
      toggleConnection(connections[0].name)
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // Poll nmcli for WireGuard profiles and status
  Process {
    id: statusProcess
    command: ["python3", "-c", "import subprocess, json\nconns = []\ntry:\n    out = subprocess.run(['nmcli', '-t', '-f', 'NAME,TYPE,STATE,DEVICE', 'connection', 'show'], capture_output=True, text=True).stdout\n    for line in out.strip().splitlines():\n        parts = line.split(':')\n        if len(parts) >= 2 and parts[1] == 'wireguard':\n            name = parts[0]\n            st = parts[2] if len(parts) > 2 else ''\n            dev = parts[3] if len(parts) > 3 else ''\n            det = subprocess.run(['nmcli', '-s', '-g', 'wireguard.peers,ipv4.addresses,connection.interface-name', 'connection', 'show', name], capture_output=True, text=True).stdout.splitlines()\n            peers = det[0] if len(det) > 0 else ''\n            ip = det[1] if len(det) > 1 else ''\n            iface = det[2] if len(det) > 2 else dev\n            ep = ''\n            aips = ''\n            if 'endpoint=' in peers:\n                ep = peers.split('endpoint=')[1].split()[0].replace(r'\\:', ':').replace('\\:', ':')\n            if 'allowed-ips=' in peers:\n                aips = peers.split('allowed-ips=')[1].split()[0]\n            conns.append({'name': name, 'active': (st == 'activated'), 'device': iface or name, 'ip': ip, 'endpoint': ep, 'allowedIps': aips})\n    print(json.dumps(conns))\nexcept Exception as e:\n    print(json.dumps([]))\n"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var str = String(text || "").trim()
        if (!str) return
        try {
          var parsed = JSON.parse(str)
          root.connections = parsed
          var anyActive = false
          var activeItem = null
          for (var i = 0; i < parsed.length; i++) {
            if (parsed[i].active) {
              anyActive = true
              activeItem = parsed[i]
              break
            }
          }
          root.running = anyActive
          root.activeConnection = activeItem
          root.activeName = activeItem ? activeItem.name : (parsed.length > 0 ? parsed[0].name : "")
          root.activeIp = activeItem ? activeItem.ip : ""
          root.activeEndpoint = activeItem ? activeItem.endpoint : ""
          root._desired = -1
        } catch (e) {
          // ignore parse errors
        }
      }
    }
    onExited: function(code) {
      if (code !== 0 && root.connections.length === 0) {
        root.installed = false
      } else {
        root.installed = true
      }
    }
  }

  Process {
    id: actionProcess
    onExited: function(code) {
      root.actionStatus = ""
      if (code !== 0) {
        root.lastError = "Failed to switch connection"
        root._desired = -1
      }
      root.refresh()
    }
  }

  Component.onCompleted: refresh()
}
