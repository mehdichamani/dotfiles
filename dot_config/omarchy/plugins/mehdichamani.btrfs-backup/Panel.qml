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
  moduleName: "mehdichamani.btrfs-backup"
  ipcTarget: "mehdichamani.btrfs-backup"
  manageIpc: true

  property var backupData: Helper.parseStatusOutput("")
  property bool isRefreshing: false
  property string actionStatusMsg: ""
  property int currentTimeSeconds: Math.floor(Date.now() / 1000)

  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool isMounted: backupData ? (backupData.backup_disk_mounted === true) : false
  readonly property bool isConnected: backupData ? (backupData.backup_disk_connected === true || backupData.backup_disk_mounted === true) : false
  readonly property bool isEjected: Helper.isEjected(backupData)
  readonly property bool isRunning: backupData ? (backupData.status === "running") : false
  readonly property bool isError: backupData ? (backupData.status === "error") : false
  readonly property int cycleDay: backupData ? (backupData.cycle_day || 0) : 0
  readonly property int totalSnaps: backupData ? (backupData.total_snapshots || 0) : 0

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
    var uuid = (root.backupData && root.backupData.backup_disk_uuid) ? root.backupData.backup_disk_uuid : "33a3cf69-9264-4d71-8d96-16dc1a72b39a"
    runCmd("sh -c 'DEV=$(blkid -U \"" + uuid + "\" 2>/dev/null); if [ -n \"$DEV\" ]; then sudo mount -a 2>/dev/null || udisksctl mount -b \"$DEV\" 2>/dev/null; notify-send -a \"Btrfs Backup\" -u normal -i drive-harddisk \"Drive Remounted\" \"Backup SSD partition re-attached.\"; else notify-send -a \"Btrfs Backup\" -u normal -i dialog-warning \"Drive Not Found\" \"External backup SSD is not plugged in.\"; fi'")
  }

  function openLogs() {
    runCmd("omarchy-launch-floating-terminal-with-presentation \"tail -n 100 -f /var/log/btrfs-backup.log\"")
  }

  function triggerEditSchedule() {
    runCmd("omarchy-launch-floating-terminal-with-presentation \"sudo $HOME/.config/scripts/btrfs-backup.sh --edit-schedule\"")
  }

  function triggerToggleTimer() {
    if (root.backupData && root.backupData.timer_active) {
      runCmd("sudo systemctl stop btrfs-backup.timer && sudo systemctl disable btrfs-backup.timer && notify-send -a 'Btrfs Backup' -u normal -i time-symbolic 'Timer Disabled' 'Daily backup timer paused.'")
    } else {
      runCmd("sudo systemctl enable --now btrfs-backup.timer 2>/dev/null || omarchy-launch-floating-terminal-with-presentation \"sudo $HOME/.config/scripts/btrfs-backup.sh --install-systemd\"")
    }
  }

  function openRepositoryFolder() {
    var uuid = (root.backupData && root.backupData.backup_disk_uuid) ? root.backupData.backup_disk_uuid : "33a3cf69-9264-4d71-8d96-16dc1a72b39a"
    runCmd("sh -c 'DEV=$(blkid -U \"" + uuid + "\" 2>/dev/null); if [ -n \"$DEV\" ]; then TARGET=$(findmnt -rn -t btrfs -S \"$DEV\" -o TARGET 2>/dev/null | head -n 1); if [ -z \"$TARGET\" ]; then udisksctl mount -b \"$DEV\" >/dev/null 2>&1; TARGET=$(findmnt -rn -t btrfs -S \"$DEV\" -o TARGET 2>/dev/null | head -n 1); fi; if [ -n \"$TARGET\" ]; then xdg-open \"$TARGET\"; fi; fi'")
  }

  // Background status poller
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

  // 1-second ticker for live countdown rendering
  Timer {
    id: secondTicker
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: root.currentTimeSeconds = Math.floor(Date.now() / 1000)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: root.barSize

  // ---------------------------------------------------------------------------
  // TopBar Button (Nerd Font, zero emoji)
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
  // Popup Drawer Panel (Overhauled Architecture)
  // ---------------------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
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
            implicitHeight: headerRow.implicitHeight + Style.space(4)

            RowLayout {
              id: headerRow
              anchors.fill: parent
              spacing: Style.space(8)

              // Icon & Title Info
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(10)

                Text {
                  text: root.isRunning ? "󰑐" : (root.isConnected ? "󰁯" : "󱊞")
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
                      if (root.isRunning) return "Active data transfer in progress"
                      if (root.isError) return "Error: " + (root.backupData ? root.backupData.message : "")
                      if (root.isEjected) return "Drive safely unmounted (Ready to remove)"
                      if (!root.isConnected) return "External drive absent / disconnected"
                      if (!root.isMounted) return "Drive connected · Unmounted standby"
                      return "Retention Day " + root.cycleDay + " of 15 · " + (root.backupData ? root.backupData.storage_avail_human : "0B") + " free"
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
                  iconText: "󰔛"
                  tooltipText: "Edit Systemd Timer Schedule"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.triggerEditSchedule()
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

          // 2. Hardware Connection & Mount Status Card (NEW)
          Rectangle {
            width: parent.width
            implicitHeight: hwRow.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.foreground, root.accent)
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            border.width: 1

            RowLayout {
              id: hwRow
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              // Connection Pill
              Rectangle {
                Layout.fillWidth: true
                implicitHeight: Style.space(32)
                radius: Style.space(6)
                color: root.isConnected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                border.color: root.isConnected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                border.width: 1

                RowLayout {
                  anchors.centerIn: parent
                  spacing: Style.space(6)
                  Text {
                    text: root.isConnected ? "󱊞" : "󰚃"
                    color: root.isConnected ? root.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    text: root.isConnected ? "Physical: Attached" : "Physical: Absent"
                    color: root.isConnected ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: root.isConnected
                  }
                }
              }

              // Mount Status Pill
              Rectangle {
                Layout.fillWidth: true
                implicitHeight: Style.space(32)
                radius: Style.space(6)
                color: root.isMounted ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                border.color: root.isMounted ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                border.width: 1

                RowLayout {
                  anchors.centerIn: parent
                  spacing: Style.space(6)
                  Text {
                    text: root.isMounted ? "󰋊" : "󱊪"
                    color: root.isMounted ? root.accent : (root.isEjected ? root.urgent : root.dim)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    text: root.isMounted ? "Mounted (Active)" : (root.isEjected ? "Safely Ejected" : "Unmounted")
                    color: root.isMounted ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: root.isMounted
                  }
                }
              }
            }
          }

          // 3. Live Countdown & Schedule Hero Banner (NEW)
          Rectangle {
            width: parent.width
            implicitHeight: countdownCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.foreground, root.accent)
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            border.width: 1

            ColumnLayout {
              id: countdownCol
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(6)

              RowLayout {
                Layout.fillWidth: true
                Text {
                  text: "󰔛 Next Scheduled Run"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: Helper.formatSchedule(root.backupData)
                  color: (root.backupData && root.backupData.timer_active) ? root.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                Text {
                  text: "󱑊"
                  color: (root.backupData && root.backupData.next_backup_timestamp) ? root.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    // Reactive countdown driven by currentTimeSeconds
                    text: {
                      var dummy = root.currentTimeSeconds
                      if (!root.backupData || !root.backupData.next_backup_timestamp) return "Timer Not Set"
                      return Helper.formatCountdown(root.backupData.next_backup_timestamp)
                    }
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  Text {
                    text: {
                      if (!root.backupData || !root.backupData.next_backup_timestamp) return "Enable timer or run manual backup"
                      return "Estimated: " + Helper.formatDateTime(root.backupData.next_backup_timestamp)
                    }
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                // Toggle Timer Action
                PanelActionButton {
                  iconText: (root.backupData && root.backupData.timer_active) ? "󰓛" : "󰐥"
                  tooltipText: (root.backupData && root.backupData.timer_active) ? "Pause Daily Timer" : "Enable Daily Timer"
                  foreground: (root.backupData && root.backupData.timer_active) ? root.accent : root.dim
                  fontFamily: root.fontFamily
                  onClicked: root.triggerToggleTimer()
                }
              }
            }
          }

          // 4. Storage Progress Card
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
                  text: "󰋊 TUF_Backup Repository"
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
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

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
                  text: "󰁯 " + root.totalSnaps + " snapshots stored"
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

          // 5. 15-Day Cycle Retention Visualizer
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
                  text: "󱑊 15-Day Retention Cycle"
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
                      return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
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
                text: "F = Full Base Backup · Days 2-15 = Incremental Snapshots"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // 6. Interactive Actions Bottom Bar
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
              text: root.isMounted ? "󰚃  Safe Eject" : "󱊞  Mount Drive"
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
