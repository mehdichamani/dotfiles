import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DriveEjectHelper.js" as Helper

Panel {
  id: root
  moduleName: "mehdichamani.drive-eject"
  ipcTarget: "mehdichamani.drive-eject"
  manageIpc: true

  property var driveData: ({ ok: true, drives: [], drive_count: 0, mounted_partition_count: 0 })
  property bool isRefreshing: false

  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: (bar && bar.accent) ? bar.accent : Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int driveCount: (driveData && driveData.drive_count !== undefined) ? driveData.drive_count : 0
  readonly property int mountedCount: (driveData && driveData.mounted_partition_count !== undefined) ? driveData.mounted_partition_count : 0
  readonly property bool hasDrives: driveCount > 0

  function refresh() {
    if (!collectorProc.running) {
      root.isRefreshing = true
      collectorProc.running = true
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

  function ejectDrive(devicePath, model) {
    var helperPath = Quickshell.env("HOME") + "/.config/omarchy/plugins/mehdichamani.drive-eject/eject.py"
    var escapedPath = "'" + devicePath.replace(/'/g, "'\\''") + "'"
    var escapedModel = "'" + model.replace(/'/g, "'\\''") + "'"
    runCmd("python3 " + helperPath + " eject-drive " + escapedPath + " " + escapedModel)
  }

  function unmountPart(partPath, label) {
    var helperPath = Quickshell.env("HOME") + "/.config/omarchy/plugins/mehdichamani.drive-eject/eject.py"
    var escapedPath = "'" + partPath.replace(/'/g, "'\\''") + "'"
    var escapedLabel = "'" + label.replace(/'/g, "'\\''") + "'"
    runCmd("python3 " + helperPath + " unmount-part " + escapedPath + " " + escapedLabel)
  }

  function mountPart(partPath, label) {
    var helperPath = Quickshell.env("HOME") + "/.config/omarchy/plugins/mehdichamani.drive-eject/eject.py"
    var escapedPath = "'" + partPath.replace(/'/g, "'\\''") + "'"
    var escapedLabel = "'" + label.replace(/'/g, "'\\''") + "'"
    runCmd("python3 " + helperPath + " mount-part " + escapedPath + " " + escapedLabel)
  }

  function openMountPoint(mountpoint) {
    if (!mountpoint) return
    var escaped = "'" + mountpoint.replace(/'/g, "'\\''") + "'"
    runCmd("xdg-open " + escaped)
  }

  function openDisksApp() {
    runCmd("gnome-disks >/dev/null 2>&1 || omarchy-launch-floating-terminal-with-presentation \"lsblk -f\"")
  }

  // ---------------------------------------------------------------------------
  // Processes and Timers
  // ---------------------------------------------------------------------------
  Process {
    id: collectorProc
    command: ["python3", Quickshell.env("HOME") + "/.config/omarchy/plugins/mehdichamani.drive-eject/collector.py"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(text || "").trim()
        if (out.length > 0) {
          try {
            var parsed = JSON.parse(out)
            if (parsed && parsed.ok !== false) {
              root.driveData = parsed
            }
          } catch(e) {}
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
    interval: root.opened ? 2500 : 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: root.barSize

  // ---------------------------------------------------------------------------
  // TopBar Button (Always visible, Nerd Font \uf052 icon)
  // ---------------------------------------------------------------------------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰋊"
    useActiveColor: false
    tooltipText: Helper.getStatusTooltip(root.driveData)

    iconComponent: Component {
      Item {
        anchors.fill: parent

        OpticalGlyph {
          anchors.fill: parent
          text: "󰋊"
          fontFamily: root.fontFamily
          fontSize: Style.bar.iconFont
          color: root.hasDrives ? root.foreground : root.dim
        }

        BorderSurface {
          visible: root.hasDrives
          width: Math.max(10, badgeText.implicitWidth + Style.space(3))
          height: 10
          radius: height / 2
          color: (root.bar && root.bar.accent) ? root.bar.accent : Color.accent
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.topMargin: -Style.space(2)
          anchors.rightMargin: -Style.space(4)
          borderSpec: Border.none

          Text {
            id: badgeText
            anchors.centerIn: parent
            text: String((root.driveData && root.driveData.drive_count) || 0)
            color: Color.background
            font.family: root.fontFamily
            font.pixelSize: 7
            font.bold: true
          }
        }
      }
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else if (b === Qt.MiddleButton) root.openDisksApp()
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
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(600))

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

          // 1. Header Card
          Rectangle {
            width: parent.width
            implicitHeight: headerRow.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.foreground, root.accent)
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            border.width: 1

            RowLayout {
              id: headerRow
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(10)

              // Main Icon
              Rectangle {
                width: Style.space(34)
                height: Style.space(34)
                radius: Style.cornerRadius
                color: root.hasDrives ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

                Text {
                  anchors.centerIn: parent
                  text: "󰋊"
                  color: root.hasDrives ? root.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                  text: "External Drive Manager"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                }

                Text {
                  text: {
                    if (!root.hasDrives) return "No external drives detected"
                    return root.driveCount + (root.driveCount === 1 ? " drive connected" : " drives connected") +
                           " • " + root.mountedCount + " mounted"
                  }
                  color: root.hasDrives ? root.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // Actions on Header
              RowLayout {
                spacing: Style.space(4)
                Layout.alignment: Qt.AlignVCenter

                PanelActionButton {
                  iconText: "󰑐"
                  tooltipText: "Refresh Disk List"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.refresh()
                }

                PanelActionButton {
                  iconText: "󰟮"
                  tooltipText: "Open Disks Utility"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.openDisksApp()
                }
              }
            }
          }

          // 2. Drive List or Empty State
          Column {
            width: parent.width
            spacing: Style.space(10)

            // Empty State
            Rectangle {
              visible: !root.hasDrives
              width: parent.width
              implicitHeight: emptyCol.implicitHeight + Style.space(32)
              radius: Style.cornerRadius
              color: Style.hoverFillFor(root.foreground, root.accent)
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
              border.width: 1

              ColumnLayout {
                id: emptyCol
                anchors.centerIn: parent
                spacing: Style.space(8)

                Text {
                  text: "󰋊"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(36)
                  Layout.alignment: Qt.AlignHCenter
                }

                Text {
                  text: "Ready for USB / External Storage"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  Layout.alignment: Qt.AlignHCenter
                }

                Text {
                  text: "Plug in any external drive to safely manage & eject."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  Layout.alignment: Qt.AlignHCenter
                }
              }
            }

            // Drives Repeater
            Repeater {
              model: (root.driveData && root.driveData.drives) ? root.driveData.drives : []

              delegate: Rectangle {
                id: driveCard
                required property var modelData
                width: parent.width
                implicitHeight: driveCol.implicitHeight + Style.space(16)
                radius: Style.cornerRadius
                color: Style.hoverFillFor(root.foreground, root.accent)
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
                border.width: 1

                ColumnLayout {
                  id: driveCol
                  anchors.fill: parent
                  anchors.margins: Style.space(12)
                  spacing: Style.space(10)

                  // Drive Title & Eject Button Row
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(8)

                    Text {
                      text: "󰋊"
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 1

                      RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(6)

                        Text {
                          text: driveCard.modelData.model || "External Drive"
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.title
                          font.bold: true
                          Layout.fillWidth: true
                          elide: Text.ElideRight
                        }

                        // Bus Badge (e.g. USB)
                        Rectangle {
                          height: Style.space(16)
                          implicitWidth: tranText.implicitWidth + Style.space(8)
                          radius: 3
                          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

                          Text {
                            id: tranText
                            anchors.centerIn: parent
                            text: driveCard.modelData.tran || "USB"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.small
                            font.bold: true
                          }
                        }
                      }

                      Text {
                        text: (driveCard.modelData.path || "") + " • " + (driveCard.modelData.size_str || "")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    // Safe Eject Button (Clean, prominent)
                    Button {
                      Layout.alignment: Qt.AlignVCenter
                      implicitHeight: Style.space(28)
                      text: "Safe Eject"
                      iconText: "󰞱"
                      bordered: true
                      foreground: root.urgent
                      accent: root.urgent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.small
                      tooltipText: "Safely unmount and power down " + (driveCard.modelData.model || "drive")

                      onClicked: {
                        root.ejectDrive(driveCard.modelData.path, driveCard.modelData.model)
                      }
                    }
                  }

                  // Partition Separator
                  PanelSeparator {
                    Layout.fillWidth: true
                  }

                  // Partitions List
                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(8)

                    Repeater {
                      model: driveCard.modelData.partitions || []

                      delegate: Rectangle {
                        id: partRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: partCol.implicitHeight + Style.space(10)
                        radius: 4
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                        ColumnLayout {
                          id: partCol
                          anchors.fill: parent
                          anchors.margins: Style.space(8)
                          spacing: Style.space(6)

                          RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(6)

                            // Status bullet
                            Rectangle {
                              width: 8
                              height: 8
                              radius: 4
                              color: partRow.modelData.is_mounted ? root.accent : root.dim
                              Layout.alignment: Qt.AlignVCenter
                            }

                            // Partition label / name
                            Text {
                              text: partRow.modelData.label || partRow.modelData.name
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                              Layout.maximumWidth: Style.space(140)
                              elide: Text.ElideRight
                            }

                            // Filesystem badge
                            Rectangle {
                              height: Style.space(16)
                              implicitWidth: fsText.implicitWidth + Style.space(8)
                              radius: 3
                              color: Qt.rgba(0.5, 0.5, 0.5, 0.15)
                              border.color: Helper.getFsBadgeColor(partRow.modelData.fstype)
                              border.width: 1

                              Text {
                                id: fsText
                                anchors.centerIn: parent
                                text: partRow.modelData.fstype
                                color: Helper.getFsBadgeColor(partRow.modelData.fstype)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.small
                                font.bold: true
                              }
                            }

                            Item { Layout.fillWidth: true }

                            // Partition Size
                            Text {
                              text: partRow.modelData.size_str || ""
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }

                            // Open folder if mounted
                            PanelActionButton {
                              visible: partRow.modelData.is_mounted
                              iconText: "󰉖"
                              tooltipText: "Open in File Manager"
                              foreground: root.foreground
                              fontFamily: root.fontFamily
                              onClicked: root.openMountPoint(partRow.modelData.primary_mount)
                            }

                            // Mount / Unmount button
                            PanelActionButton {
                              iconText: partRow.modelData.is_mounted ? "󰞱" : "󰌒"
                              tooltipText: partRow.modelData.is_mounted ? "Unmount Partition" : "Mount Partition"
                              foreground: partRow.modelData.is_mounted ? root.urgent : root.accent
                              fontFamily: root.fontFamily
                              onClicked: {
                                if (partRow.modelData.is_mounted) {
                                  root.unmountPart(partRow.modelData.path, partRow.modelData.label)
                                } else {
                                  root.mountPart(partRow.modelData.path, partRow.modelData.label)
                                }
                              }
                            }
                          }

                          // Mount Path & Disk Usage (if mounted)
                          ColumnLayout {
                            visible: partRow.modelData.is_mounted
                            Layout.fillWidth: true
                            spacing: 3

                            RowLayout {
                              Layout.fillWidth: true
                              spacing: Style.space(4)

                              Text {
                                text: partRow.modelData.primary_mount || ""
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.small
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                              }

                              Text {
                                visible: partRow.modelData.usage !== null
                                text: (partRow.modelData.usage ? partRow.modelData.usage.free_str : "") + " free"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.small
                                font.bold: true
                              }
                            }

                            // Usage Progress Bar
                            Rectangle {
                              visible: partRow.modelData.usage !== null
                              Layout.fillWidth: true
                              height: 4
                              radius: 2
                              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

                              Rectangle {
                                width: parent.width * (Helper.getUsagePercent(partRow.modelData) / 100.0)
                                height: parent.height
                                radius: 2
                                color: {
                                  var pct = Helper.getUsagePercent(partRow.modelData)
                                  if (pct > 90) return root.urgent
                                  if (pct > 75) return "#e0af68"
                                  return root.accent
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
            }
          }
        }
      }
    }
  }
}
