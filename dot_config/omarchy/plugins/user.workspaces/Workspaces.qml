import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "user.workspaces"

  readonly property color fgColor: (root.bar && root.bar.barForeground) ? root.bar.barForeground : Color.foreground
  readonly property color accentColor: Color.accent
  readonly property color activeColor: (root.bar && root.bar.urgent) ? root.bar.urgent : Color.bar.active

  // Reusable click target component that registers with Omarchy Bar click router
  component WorkspaceClickTarget: Item {
    id: clickRoot
    property var bar: root.bar
    property bool interactive: true
    property bool pressable: true
    property bool concealed: false
    property var registeredBar: null
    property string tooltipText: ""
    readonly property bool hovered: mouseArea.containsMouse

    signal clicked(int button)

    function triggerPress(button) {
      if (root.bar) root.bar.hideTooltip(clickRoot)
      clickRoot.clicked(button)
    }

    function syncClickRegistration() {
      if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(clickRoot)
      registeredBar = root.bar
      if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(clickRoot)
    }

    onBarChanged: syncClickRegistration()
    Component.onCompleted: syncClickRegistration()
    Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(clickRoot)

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: clickRoot.pressable ? Qt.PointingHandCursor : Qt.ArrowCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      onEntered: if (root.bar && clickRoot.tooltipText !== "") root.bar.showTooltip(clickRoot, clickRoot.tooltipText)
      onExited: if (root.bar) root.bar.hideTooltip(clickRoot)
      onClicked: function(mouse) { clickRoot.triggerPress(mouse.button) }
    }
  }

  // Detect which screen/monitor this widget instance belongs to
  readonly property string screenName: {
    var win = QsWindow.window
    if (win && win.screen && win.screen.name) {
      return String(win.screen.name)
    }
    if (root.bar && typeof root.bar.slotScreenName === "function") {
      try {
        var name = root.bar.slotScreenName(root)
        if (name) return name
      } catch (e) {}
    }
    return ""
  }

  // Workspaces configured per monitor:
  // Dual-monitor mode: DP-1 (1, 2, 3), HDMI-A-1 (4, 5, 6)
  // Single-monitor mode: All 1-6 displayed on the active monitor
  function monitorWorkspaceIds() {
    var name = root.screenName
    var monitors = Hyprland.monitors ? Hyprland.monitors.values : []

    // If only one monitor is active in Hyprland, display all workspaces (1..6)
    if (monitors.length <= 1) {
      return [1, 2, 3, 4, 5, 6]
    }

    var baseIds = []
    if (name === "DP-1") {
      baseIds = [1, 2, 3]
    } else if (name === "HDMI-A-1") {
      baseIds = [4, 5, 6]
    } else {
      baseIds = [1, 2, 3, 4, 5, 6]
    }

    // Dynamic fallback: check Hyprland workspace-monitor mapping
    var values = Hyprland.workspaces ? Hyprland.workspaces.values : []
    var ids = baseIds.slice()
    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      if (ws && ws.id > 0 && ws.monitor && ws.monitor.name === name) {
        if (ids.indexOf(ws.id) === -1) {
          ids.push(ws.id)
        }
      }
    }

    ids.sort(function(a, b) { return a - b })
    return ids
  }

  // Reactive workspace IDs list per monitor
  readonly property var activeWorkspaceIds: {
    var _w = Hyprland.workspaces ? Hyprland.workspaces.values : []
    var _m = Hyprland.monitors ? Hyprland.monitors.values : []
    var _s = root.screenName
    return root.monitorWorkspaceIds()
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces ? Hyprland.workspaces.values : []
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function formatTitle(raw) {
    var str = String(raw || "").trim()
    if (!str) return ""
    if (str.length > 52) {
      return str.substring(0, 51) + "…"
    }
    return str
  }

  function cleanAppName(str) {
    if (!str) return ""
    var s = String(str).trim()
    // If reverse domain name format like org.wezfurlong.wezterm or com.google.Chrome
    if (s.indexOf(".") !== -1) {
      var parts = s.split(".")
      s = parts[parts.length - 1]
    }
    // Capitalize first letter if lowercase
    if (s.length > 0) {
      return s.charAt(0).toUpperCase() + s.slice(1)
    }
    return s
  }

  function getToplevelTitle(toplevel) {
    if (!toplevel) return ""
    // Check Hyprland IPC object (class / initialClass / initialTitle)
    var ipc = toplevel.lastIpcObject
    var app = ""
    if (ipc) {
      app = ipc["class"] || ipc["initialClass"] || ipc["initialTitle"] || ""
    }
    // Check Wayland toplevel appId
    if (!app && toplevel.wayland) {
      app = toplevel.wayland.appId || ""
    }
    // Direct properties fallback
    if (!app) {
      app = toplevel.appId || toplevel.initialClass || toplevel.clazz || toplevel.initialTitle || ""
    }

    var appClean = cleanAppName(app)
    var rawTitle = String(toplevel.title || "").trim()

    if (appClean && rawTitle) {
      // Avoid redundancy if title already starts with or is identical to app name
      if (rawTitle.toLowerCase() === appClean.toLowerCase()) {
        return formatTitle(appClean)
      }
      return formatTitle(appClean + " 🔸 " + rawTitle)
    }

    if (appClean) {
      return formatTitle(appClean)
    }

    return formatTitle(rawTitle || "Window")
  }

  function getWorkspaceTooltip(id, ws) {
    var base = "Workspace " + id
    if (!ws || !ws.toplevels || !ws.toplevels.values || ws.toplevels.values.length === 0) {
      return base + " (Empty)"
    }
    var list = ws.toplevels.values
    var countStr = list.length === 1 ? "1 window" : (list.length + " windows")
    var lines = [base + " (" + countStr + ")"]
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      var tName = String(t.title || t.appId || "Window").trim()
      lines.push("  • " + tName)
    }
    return lines.join("\n")
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: layout.implicitWidth + trailingGap
  implicitHeight: root.barSize

  Row {
    id: layout
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    spacing: Style.space(2)

    Repeater {
      model: root.activeWorkspaceIds

      Item {
        id: wsDelegate
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property var toplevels: workspace ? (workspace.toplevels ? workspace.toplevels.values : []) : []
        readonly property int winCount: toplevels.length
        readonly property bool occupied: winCount > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        implicitHeight: Math.max(34, root.barSize - Style.space(3))
        implicitWidth: root.vertical
          ? root.barSize
          : (occupied
              ? Math.max(Style.space(56), occupiedRow.implicitWidth + Style.space(12))
              : Style.space(26))
        width: implicitWidth
        height: implicitHeight

        // Outer background container
        Rectangle {
          id: bg
          anchors.fill: parent
          anchors.margins: 1
          radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, 6) : 6
          color: wsDelegate.focused
            ? Util.alpha(root.accentColor, 0.14)
            : (wsDelegate.occupied ? Util.alpha(root.fgColor, 0.04) : "transparent")
          border.width: wsDelegate.focused ? 1 : (wsDelegate.occupied ? 1 : 0)
          border.color: wsDelegate.focused
            ? root.accentColor
            : Util.alpha(root.fgColor, 0.1)
        }

        // --- CASE 1: EMPTY WORKSPACE ---
        WorkspaceClickTarget {
          id: emptyTarget
          visible: !wsDelegate.occupied
          anchors.fill: parent
          tooltipText: "Workspace " + wsDelegate.modelData + " (Empty)"
          onClicked: function(button) {
            root.focusWorkspace(wsDelegate.modelData)
          }

          Text {
            anchors.centerIn: parent
            text: String(wsDelegate.modelData)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            color: wsDelegate.focused
              ? root.accentColor
              : (emptyTarget.hovered ? root.fgColor : Util.alpha(root.fgColor, 0.45))
          }
        }

        // --- CASE 2: OCCUPIED WORKSPACE ---
        Row {
          id: occupiedRow
          visible: wsDelegate.occupied
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(6)
          spacing: Style.space(4)

          // 1. Left Section: Workspace Number
          WorkspaceClickTarget {
            id: wsNumTarget
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(18)
            height: wsDelegate.height
            tooltipText: "Workspace " + wsDelegate.modelData + " (Click to switch)"
            onClicked: function(button) {
              root.focusWorkspace(wsDelegate.modelData)
            }

            Text {
              anchors.centerIn: parent
              text: String(wsDelegate.modelData)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              color: wsDelegate.focused
                ? root.accentColor
                : (wsNumTarget.hovered ? root.accentColor : root.fgColor)
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }
          }

          // 2. Subtle Divider
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: Style.space(22)
            color: wsDelegate.focused ? Util.alpha(root.accentColor, 0.35) : Util.alpha(root.fgColor, 0.15)
          }

          // 3. Right Section: Windows Column (Up to 2 stacked rows)
          Column {
            id: winCol
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            // Row 1: First Open Window
            WorkspaceClickTarget {
              id: win1Target
              visible: wsDelegate.winCount >= 1
              readonly property var top1: wsDelegate.winCount >= 1 ? wsDelegate.toplevels[0] : null
              readonly property bool isWinActive: top1 !== null && top1.activated

              height: wsDelegate.winCount > 1 ? Style.space(16) : Style.space(22)
              width: row1Rect.implicitWidth

              tooltipText: top1 ? (String(top1.title || top1.appId || "Window") + "\n(Click to activate)") : ""
              onClicked: function(button) {
                if (!top1) return
                if (button === Qt.MiddleButton) {
                  top1.close()
                } else {
                  root.focusWorkspace(wsDelegate.modelData)
                  top1.activate()
                }
              }

              Rectangle {
                id: row1Rect
                anchors.fill: parent
                implicitWidth: Math.min(Style.space(240), text1.implicitWidth + Style.space(8))
                radius: 4
                color: win1Target.isWinActive
                  ? Util.alpha(root.accentColor, 0.24)
                  : (win1Target.hovered ? Util.alpha(root.fgColor, 0.12) : "transparent")
                border.width: win1Target.isWinActive ? 1 : (win1Target.hovered ? 1 : 0)
                border.color: win1Target.isWinActive ? root.accentColor : Util.alpha(root.fgColor, 0.25)

                Text {
                  id: text1
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(4)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  text: root.getToplevelTitle(win1Target.top1)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: wsDelegate.winCount > 1 ? Style.font.caption : Style.font.bodySmall
                  font.bold: win1Target.isWinActive
                  color: win1Target.isWinActive
                    ? root.accentColor
                    : (wsDelegate.focused ? root.fgColor : Util.alpha(root.fgColor, 0.85))
                  elide: Text.ElideRight
                  maximumLineCount: 1
                  verticalAlignment: Text.AlignVCenter
                }
              }
            }

            // Row 2: Second Open Window (if present)
            WorkspaceClickTarget {
              id: win2Target
              visible: wsDelegate.winCount >= 2
              readonly property var top2: wsDelegate.winCount >= 2 ? wsDelegate.toplevels[1] : null
              readonly property bool isWinActive: top2 !== null && top2.activated

              height: Style.space(16)
              width: row2Rect.implicitWidth

              tooltipText: top2 ? (String(top2.title || top2.appId || "Window") + "\n(Click to activate)") : ""
              onClicked: function(button) {
                if (!top2) return
                if (button === Qt.MiddleButton) {
                  top2.close()
                } else {
                  root.focusWorkspace(wsDelegate.modelData)
                  top2.activate()
                }
              }

              Rectangle {
                id: row2Rect
                anchors.fill: parent
                implicitWidth: Math.min(Style.space(240), row2Inner.implicitWidth + Style.space(8))
                radius: 4
                color: win2Target.isWinActive
                  ? Util.alpha(root.accentColor, 0.24)
                  : (win2Target.hovered ? Util.alpha(root.fgColor, 0.12) : "transparent")
                border.width: win2Target.isWinActive ? 1 : (win2Target.hovered ? 1 : 0)
                border.color: win2Target.isWinActive ? root.accentColor : Util.alpha(root.fgColor, 0.25)

                Row {
                  id: row2Inner
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(4)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  spacing: 2

                  Text {
                    id: text2
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.getToplevelTitle(win2Target.top2)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: win2Target.isWinActive
                    color: win2Target.isWinActive
                      ? root.accentColor
                      : (wsDelegate.focused ? root.fgColor : Util.alpha(root.fgColor, 0.85))
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    verticalAlignment: Text.AlignVCenter
                  }

                  Text {
                    id: countBadge
                    anchors.verticalCenter: parent.verticalCenter
                    visible: wsDelegate.winCount > 2
                    text: "+" + (wsDelegate.winCount - 2)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption - 1
                    color: root.accentColor
                    font.bold: true
                    verticalAlignment: Text.AlignVCenter
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
