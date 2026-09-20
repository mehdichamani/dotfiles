import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "BackupHelper.js" as Helper

Panel {
  id: root
  moduleName: "user.btrfs-backup"
  ipcTarget: "user.btrfs-backup"
  manageIpc: true

  property var backupData: Helper.parseStatusOutput("")
  property bool isRefreshing: false
  property string actionStatusMsg: ""

  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool isMounted: backupData ? (backupData.backup_disk_mounted === true) : false
  readonly property bool isEjected: Helper.isEjected(backupData)
  readonly property bool isRunning: backupData ? (backupData.status === "running") : false
  readonly property bool isError: backupData ? (backupData.status === "error") : false
  readonly property int cycleDay: backupData ? (backupData.cycle_day || 0) : 0
  readonly property int totalSnaps: backupData ? (backupData.total_snapshots || 0) : 0

  readonly property bool isConnected: backupData ? (backupData.backup_disk_connected === true || backupData.backup_disk_mounted === true) : false

  function refresh() {
    if (!statusProc.running) {
      root.isRefreshing = true
      statusProc.running = true
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

  function triggerBackupNow() {
    if (!root.isConnected) {
      runCmd("notify-send -a 'Btrfs Backup' -u normal -i drive-harddisk 'Backup Cancelled' 'External backup SSD is absent or disconnected.'")
      return
    }
    runCmd("omarchy-launch-floating-terminal-with-presentation \"sudo $HOME/.config/scripts/btrfs-backup.sh --force\"")
  }

  function triggerProbeNow() {
    if (!root.isConnected) {
      runCmd("notify-send -a 'Btrfs Backup' -u normal -i drive-harddisk 'Probe Skipped' 'External backup SSD is absent or disconnected.'")
      return
    }
    runCmd("omarchy-launch-floating-terminal-with-presentation \"sudo $HOME/.config/scripts/btrfs-backup.sh --probe\"")
  }

  function triggerSafeEject() {
    if (!root.isConnected) {
      runCmd("notify-send -a 'Btrfs Backup' -u low -i drive-harddisk 'Drive Absent' 'External backup drive is already disconnected.'")
      return
    }
    runCmd("omarchy-launch-floating-terminal-with-presentation \"sudo $HOME/.config/scripts/btrfs-backup.sh --eject\"")
  }

  function triggerRemount() {
    runCmd("sh -c 'DEV=$(blkid -U 33a3cf69-9264-4d71-8d96-16dc1a72b39a 2>/dev/null); if [ -n \"$DEV\" ]; then sudo mount -a 2>/dev/null || udisksctl mount -b \"$DEV\" 2>/dev/null; notify-send -a \"Btrfs Backup\" -u normal -i drive-harddisk \"Drive Remounted\" \"Backup SSD partition re-attached.\"; else notify-send -a \"Btrfs Backup\" -u normal -i dialog-warning \"Drive Not Found\" \"External backup SSD is not plugged in.\"; fi'")
  }

  function openLogs() {
    runCmd("omarchy-launch-floating-terminal-with-presentation \"tail -n 100 -f /var/log/btrfs-backup.log\"")
  }

  function triggerEditSchedule() {
    runCmd("omarchy-launch-floating-terminal-with-presentation \"sudo $HOME/.config/scripts/btrfs-backup.sh --edit-schedule\"")
  }

  function openRepositoryFolder() {
    runCmd("sh -c 'DEV=$(blkid -U 33a3cf69-9264-4d71-8d96-16dc1a72b39a 2>/dev/null); if [ -n \"$DEV\" ]; then TARGET=$(findmnt -rn -t btrfs -S \"$DEV\" -o TARGET 2>/dev/null | head -n 1); if [ -z \"$TARGET\" ]; then udisksctl mount -b \"$DEV\" >/dev/null 2>&1; TARGET=$(findmnt -rn -t btrfs -S \"$DEV\" -o TARGET 2>/dev/null | head -n 1); fi; if [ -n \"$TARGET\" ]; then xdg-open \"$TARGET\"; fi; fi'")
  }

  // Background status poller (reads persistent cache without waking or mounting the disk)
  Process {
    id: statusProc
    command: ["sh", "-c", "$HOME/.config/scripts/btrfs-backup.sh --status 2>/dev/null || cat ~/.local/state/btrfs-backup/status.json 2>/dev/null || true"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var output = String(text || "").trim()
        if (output.length > 0) {
          root.backupData = Helper.parseStatusOutput(output)
        }
      }
    }
    onExited: function(code) {
      root.isRefreshing = false
    }
  }

  // Action process fallback
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
    interval: root.opened ? 3000 : (root.isRunning ? 2000 : 10000)
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: root.barSize

  // ---------------------------------------------------------------------------
  // TopBar Button
  // ---------------------------------------------------------------------------
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: 18
    text: Helper.getStatusBadge(root.backupData)
    dimmed: !root.isRunning && root.cycleDay === 0 && !root.isMounted
    active: (root.cycleDay > 0 || root.isMounted) && !root.isError && !root.isEjected
    activeColor: root.isRunning ? root.urgent : ((root.bar && root.bar.accent) ? root.bar.accent : Color.accent)
    tooltipText: Helper.getStatusTooltip(root.backupData)

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else if (b === Qt.MiddleButton) root.openLogs()
      else root.toggle()
    }
  }

  // ---------------------------------------------------------------------------
  // Popup Drawer Panel
  // ---------------------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

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

              // Icon & Title Info
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                Text {
                  text: root.isRunning ? "󰑐" : "󰁯"
                  color: root.isRunning ? root.urgent : (root.isConnected ? root.accent : root.dim)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    text: "Btrfs Live Backup"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  Text {
                    text: {
                      if (root.isRunning) return "Transferring snapshots..."
                      if (root.isError) return "Backup error: " + (root.backupData ? root.backupData.message : "")
                      if (root.isEjected) return "Drive safely ejected (Unmounted)"
                      if (!root.isConnected) return "External SSD absent / disconnected"
                      if (!root.isMounted) return "Cycle Day " + root.cycleDay + "/15 · Standby (Unmounted)"
                      return "Cycle Day " + root.cycleDay + "/15 · " + (root.backupData ? root.backupData.storage_avail_human : "0B") + " Free"
                    }
                    color: root.isRunning ? root.urgent : (root.isEjected ? root.dim : (root.isConnected ? root.accent : root.dim))
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              // Action Buttons on Header
              RowLayout {
                spacing: Style.space(4)
                Layout.alignment: Qt.AlignVCenter

                PanelActionButton {
                  iconText: "󰑐"
                  tooltipText: "Probe Disk & Refresh Stats"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.triggerProbeNow()
                }

                PanelActionButton {
                  iconText: "󰈙"
                  tooltipText: "View Live Logs"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.openLogs()
                }
              }
            }
          }

          // 2. Storage Progress Card
          Rectangle {
            width: parent.width
            implicitHeight: storageCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.foreground, root.accent)
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            border.width: 1

            ColumnLayout {
              id: storageCol
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(6)

              RowLayout {
                Layout.fillWidth: true
                Text {
                  text: "TUF_Backup Repository"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.backupData.storage_used_human + " / " + (Helper.getStoragePercent(root.backupData.storage_used_bytes, root.backupData.storage_avail_bytes)) + "%"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // Storage Bar
              Rectangle {
                Layout.fillWidth: true
                implicitHeight: Style.space(8)
                radius: Style.space(4)
                color: Qt.darker(root.foreground, 3.5)

                Rectangle {
                  height: parent.height
                  width: Math.max(parent.radius * 2, parent.width * (Helper.getStoragePercent(root.backupData.storage_used_bytes, root.backupData.storage_avail_bytes) / 100))
                  radius: Style.space(4)
                  color: root.accent
                }
              }

              RowLayout {
                Layout.fillWidth: true
                Text {
                  text: root.totalSnaps + " Snapshots stored"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.backupData.storage_avail_human + " available"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          // 3. 15-Day Cycle Visualizer Card
          Rectangle {
            width: parent.width
            implicitHeight: cycleCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.foreground, root.accent)
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            border.width: 1

            ColumnLayout {
              id: cycleCol
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              RowLayout {
                Layout.fillWidth: true
                Text {
                  text: "15-Day Retention Cycle"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: "Day " + root.cycleDay + " of 15"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              // Step blocks 1..15
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(3)

                Repeater {
                  model: 15
                  Rectangle {
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: Style.space(14)
                    radius: Style.space(2)
                    color: {
                      var day = index + 1
                      if (day === 1 && root.cycleDay >= 1) return root.accent
                      if (day <= root.cycleDay) return Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
                      return Qt.darker(root.foreground, 3.2)
                    }

                    Text {
                      anchors.centerIn: parent
                      text: (index + 1) === 1 ? "F" : (index + 1)
                      color: (index + 1) <= root.cycleDay ? "#ffffff" : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: 8
                      font.bold: (index + 1) === 1 || (index + 1) === root.cycleDay
                    }
                  }
                }
              }

              Text {
                text: "F = Full Base Backup · Days 2-15 = Fast Incremental Diffs"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // 4. Details / Metadata Card
          Rectangle {
            width: parent.width
            implicitHeight: metaCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.foreground, root.accent)
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            border.width: 1

            ColumnLayout {
              id: metaCol
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(6)

              // Last Backup
              RowLayout {
                Layout.fillWidth: true
                Text {
                  text: "󱑊 Last Backup"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: Helper.formatDateTime(root.backupData.last_success_timestamp) + " (" + Helper.formatRelativeTime(root.backupData.last_success_timestamp) + ")"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // Timer Schedule
              RowLayout {
                Layout.fillWidth: true
                Text {
                  text: "󰔛 Timer Schedule"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: Helper.formatSchedule(root.backupData)
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // Compression & Protection
              RowLayout {
                Layout.fillWidth: true
                Text {
                  text: "󰗊 Target Subvols"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: "/ (@), /home (@home), /boot"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          // 5. Interactive Action Buttons
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            // Instant Backup Button
            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(36)
              text: "󰁯  Backup Now"
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              enabled: (root.isMounted || root.isConnected) && !root.isRunning
              onClicked: root.triggerBackupNow()
            }

            // Safe Eject / Mount Button
            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(36)
              text: root.isMounted ? "⏏  Safe Eject" : "󰑐  Mount Drive"
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              enabled: (root.isConnected || root.isMounted) && !root.isRunning
              onClicked: root.isMounted ? root.triggerSafeEject() : root.triggerRemount()
            }

            // Open Folder Button
            PanelActionButton {
              iconText: "󰝰"
              tooltipText: "Open Backup Folder"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.isMounted || root.isConnected
              onClicked: root.openRepositoryFolder()
            }
          }
        }
      }
    }
  }
}
