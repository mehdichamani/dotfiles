import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "SyncthingHelper.js" as Helper

Panel {
  id: root
  moduleName: "user.syncthing"
  ipcTarget: "user.syncthing"
  manageIpc: true

  property var stData: ({
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
  })
  property bool isRefreshing: false

  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool isAvailable: stData ? (stData.isAvailable || false) : false
  readonly property int syncingCount: stData ? (stData.syncingFolders || 0) : 0
  readonly property int errorCount: stData ? (stData.errorFolders || 0) : 0
  readonly property int connectedDevices: stData ? (stData.connectedDevices || 0) : 0
  readonly property int totalFolders: stData ? (stData.totalFolders || 0) : 0

  function refresh() {
    if (!stProc.running) {
      root.isRefreshing = true
      stProc.running = true
    }
  }

  function runCmd(cmd) {
    if (root.bar) {
      root.bar.run(cmd)
    } else {
      actionProc.command = ["sh", "-c", cmd]
      actionProc.running = true
    }
    actionRefreshTimer.restart()
  }

  function openWebGui() {
    var url = (stData && stData.guiUrl) ? stData.guiUrl : "http://127.0.0.1:8384";
    runCmd("xdg-open '" + url + "'")
  }

  function openFolderInFileManager(folderPath) {
    var p = folderPath || "$HOME";
    p = p.replace(/^~/, Quickshell.env("HOME"));
    runCmd("xdg-open '" + p + "'")
  }

  function openFolderInTerminal(folderPath) {
    var p = folderPath || "$HOME";
    p = p.replace(/^~/, Quickshell.env("HOME"));
    runCmd("omarchy-launch-floating-terminal-with-presentation \"cd '" + p + "' && exec fish\"")
  }

  function rescanFolder(folderId) {
    if (!folderId) return;
    var cmd = "syncthing cli operations scan " + folderId + " && notify-send -a 'Syncthing' -u low 'Rescan Triggered' 'Scanning folder " + folderId + "'";
    runCmd(cmd)
  }

  // Background Syncthing Status poller
  Process {
    id: stProc
    command: ["python3", Quickshell.env("HOME") + "/.config/omarchy/plugins/user.syncthing/syncthing-collector.py"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var output = String(text || "").trim()
        root.stData = Helper.parseSyncthingOutput(output)
      }
    }
    onExited: function(code) {
      root.isRefreshing = false
    }
  }

  Process {
    id: actionProc
    running: false
  }

  Timer {
    id: actionRefreshTimer
    interval: 1200
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: pollTimer
    interval: root.opened ? 3000 : 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: root.barSize

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: 20
    text: {
      if (!root.isAvailable) return "\uf4ad"
      if (root.errorCount > 0) return "\ue654 " + root.errorCount
      if (root.syncingCount > 0) return "\uea83 \uea77 " + root.syncingCount
      return "\uea83"
    }
    dimmed: !root.isAvailable
    active: root.isAvailable
    activeColor: {
      if (!root.isAvailable) return root.dim
      if (root.errorCount > 0) return root.urgent
      return (root.bar && root.bar.accent) ? root.bar.accent : Color.accent
    }
    tooltipText: {
      if (!root.isAvailable) return "Syncthing: Offline / Unreachable"
      if (root.errorCount > 0) return "Syncthing: " + root.errorCount + " folder error(s)"
      if (root.syncingCount > 0) return "Syncthing: Syncing " + root.syncingCount + " folder(s)"
      return "Syncthing: Up to date (" + root.connectedDevices + " device(s) connected, " + root.totalFolders + " folders)"
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else if (b === Qt.MiddleButton) root.openWebGui()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: panelColumn
          width: panelFlick.width
          spacing: Style.space(12)

          // 1. Header Hero Card
          Item {
            id: headerItem
            width: parent.width
            implicitHeight: headerRow.implicitHeight + Style.space(6)

            RowLayout {
              id: headerRow
              anchors.fill: parent
              spacing: Style.space(8)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                Text {
                  text: "󰛢"
                  color: root.isAvailable ? (root.errorCount > 0 ? root.urgent : (root.syncingCount > 0 ? root.accent : root.foreground)) : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    text: "Syncthing"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  Text {
                    text: {
                      if (!root.isAvailable) return "Service unreachable or stopped"
                      if (root.errorCount > 0) return root.errorCount + " folder error(s)"
                      if (root.syncingCount > 0) return "Syncing " + root.syncingCount + " folder(s)"
                      return "Up to date · " + root.connectedDevices + " Connected · " + root.totalFolders + " Folders"
                    }
                    color: root.isAvailable ? (root.errorCount > 0 ? root.urgent : (root.syncingCount > 0 ? root.accent : root.dim)) : root.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              RowLayout {
                spacing: Style.space(4)
                Layout.alignment: Qt.AlignVCenter

                PanelActionButton {
                  iconText: "󰑐"
                  tooltipText: "Refresh Status"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.refresh()
                }

                PanelActionButton {
                  iconText: "󰖟"
                  tooltipText: "Open Web GUI"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.openWebGui()
                }
              }
            }
          }

          // 2. Connected Devices Section
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.isAvailable && root.stData.devices && root.stData.devices.length > 0

            Text {
              text: "DEVICES"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.small
              font.bold: true
            }

            Repeater {
              model: (root.stData && root.stData.devices) ? root.stData.devices : []

              delegate: Rectangle {
                id: deviceCard
                width: parent.width
                implicitHeight: devRow.implicitHeight + Style.space(12)
                radius: Style.radius(8)
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                border.width: 1
                border.color: modelData.connected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                RowLayout {
                  id: devRow
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(8)

                  Text {
                    text: modelData.connected ? "󰄬" : "󰅖"
                    color: Helper.deviceStatusColor(modelData, root.foreground, root.accent, root.urgent, root.dim)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    Layout.alignment: Qt.AlignVCenter
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                      text: modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      text: Helper.deviceStatusSummary(modelData) + (modelData.clientVersion ? " · " + modelData.clientVersion : "")
                      color: modelData.connected ? root.accent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    text: {
                      if (!modelData.connected) return ""
                      var inB = Helper.formatBytes(modelData.inBytesTotal || 0)
                      var outB = Helper.formatBytes(modelData.outBytesTotal || 0)
                      return "↓" + inB + "  ↑" + outB
                    }
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    Layout.alignment: Qt.AlignVCenter
                  }
                }
              }
            }
          }

          // 3. Folders Section
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.isAvailable && root.stData.folders && root.stData.folders.length > 0

            Text {
              text: "FOLDERS"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.small
              font.bold: true
            }

            Repeater {
              model: (root.stData && root.stData.folders) ? root.stData.folders : []

              delegate: Rectangle {
                id: folderCard
                width: parent.width
                implicitHeight: folderRow.implicitHeight + Style.space(12)
                radius: Style.radius(8)
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                border.width: 1
                border.color: (modelData.errors > 0) ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.4) : ((modelData.state === "syncing") ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08))

                RowLayout {
                  id: folderRow
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(8)

                  Text {
                    text: Helper.folderStatusGlyph(modelData)
                    color: Helper.folderStatusColor(modelData, root.foreground, root.accent, root.urgent, root.dim)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    Layout.alignment: Qt.AlignVCenter
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                      spacing: Style.space(6)
                      Layout.fillWidth: true

                      Text {
                        text: modelData.label
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      Text {
                        text: Helper.formatBytes(modelData.globalBytes || 0)
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      text: {
                        var desc = Helper.folderStatusSummary(modelData);
                        if (modelData.path) desc += " · " + modelData.path;
                        return desc;
                      }
                      color: Helper.folderStatusColor(modelData, root.foreground, root.accent, root.urgent, root.dim)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }
                  }

                  RowLayout {
                    spacing: Style.space(4)
                    Layout.alignment: Qt.AlignVCenter

                    PanelActionButton {
                      iconText: "󰍉"
                      tooltipText: "Rescan Folder"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      onClicked: root.rescanFolder(modelData.id)
                    }

                    PanelActionButton {
                      iconText: "󰉋"
                      tooltipText: "Open in File Manager"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      onClicked: root.openFolderInFileManager(modelData.path)
                    }

                    PanelActionButton {
                      iconText: "󰆍"
                      tooltipText: "Open in Terminal"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      onClicked: root.openFolderInTerminal(modelData.path)
                    }
                  }
                }
              }
            }
          }

          // 4. Offline or Empty State Message
          Rectangle {
            width: parent.width
            implicitHeight: emptyColumn.implicitHeight + Style.space(24)
            radius: Style.radius(8)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
            visible: !root.isAvailable || (!root.stData.folders || root.stData.folders.length === 0)

            ColumnLayout {
              id: emptyColumn
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                text: root.isAvailable ? "󰄬" : "󰛢"
                color: root.isAvailable ? root.accent : root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                Layout.alignment: Qt.AlignHCenter
              }

              Text {
                text: root.isAvailable ? "No folders configured in Syncthing" : (root.stData.error || "Syncthing service is stopped or unreachable")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                Layout.alignment: Qt.AlignHCenter
              }
            }
          }
        }
      }
    }
  }
}
