import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DockerHelper.js" as Model

Panel {
  id: root
  moduleName: "user.docker"
  ipcTarget: "user.docker"
  manageIpc: true

  property var dockerData: ({ containers: [], projects: [], standalone: [], totalRunning: 0, totalCount: 0 })
  property bool dockerAvailable: true
  property bool isRefreshing: false
  property var expandedProjects: ({})

  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int runningCount: dockerData ? (dockerData.totalRunning || 0) : 0
  readonly property int totalCount: dockerData ? (dockerData.totalCount || 0) : 0

  function isProjectExpanded(projectName) {
    return expandedProjects[projectName] !== false
  }

  function toggleProjectExpanded(projectName) {
    var copy = Object.assign({}, expandedProjects)
    copy[projectName] = !isProjectExpanded(projectName)
    expandedProjects = copy
  }

  function refresh() {
    if (!dockerProc.running) {
      root.isRefreshing = true
      dockerProc.running = true
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

  function startContainer(id) { runCmd("docker start " + id) }
  function stopContainer(id) { runCmd("docker stop " + id) }
  function restartContainer(id) { runCmd("docker restart " + id) }
  function startProject(name) { runCmd("docker compose -p " + name + " start") }
  function stopProject(name) { runCmd("docker compose -p " + name + " stop") }
  function restartProject(name) { runCmd("docker compose -p " + name + " restart") }
  function openLogs(id) { runCmd("omarchy-launch-floating-terminal-with-presentation \"docker logs -f --tail 100 " + id + "\"") }
  function openExec(id) { runCmd("omarchy-launch-floating-terminal-with-presentation \"docker exec -it " + id + " sh || docker exec -it " + id + " bash\"") }
  function openTui() { runCmd("omarchy-launch-floating-terminal-with-presentation lazydocker || wezterm start -- lazydocker") }

  // Background Docker poller
  Process {
    id: dockerProc
    command: ["sh", "-c", "docker ps -a --format '{{json .}}' 2>&1"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var output = String(text || "").trim()
        if (output.indexOf("Cannot connect to the Docker daemon") !== -1 ||
            output.indexOf("docker: command not found") !== -1 ||
            output.indexOf("permission denied") !== -1) {
          root.dockerAvailable = false
          root.dockerData = { containers: [], projects: [], standalone: [], totalRunning: 0, totalCount: 0 }
        } else {
          root.dockerAvailable = true
          root.dockerData = Model.parseDockerOutput(output)
        }
      }
    }
    onExited: function(code) {
      root.isRefreshing = false
      if (code !== 0 && root.dockerData.containers.length === 0) {
        root.dockerAvailable = false
      }
    }
  }

  // Action process fallback
  Process {
    id: actionProc
    running: false
  }

  Timer {
    id: actionRefreshTimer
    interval: 800
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: pollTimer
    interval: root.opened ? 3000 : 5000
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
    text: root.runningCount > 0 ? ("󰡨 " + root.runningCount) : "󰡨"
    dimmed: root.runningCount === 0
    active: root.runningCount > 0
    activeColor: (root.bar && root.bar.accent) ? root.bar.accent : Color.accent
    tooltipText: root.runningCount > 0 ? (root.runningCount + " running Docker containers") : "Docker Containers"

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else if (b === Qt.MiddleButton) root.openTui()
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
    contentWidth: panel.fittedContentWidth(Style.space(420))
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

              // Docker Icon & Title Info
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                Text {
                  text: "󰡨"
                  color: root.dockerAvailable && root.runningCount > 0 ? root.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    text: "Docker"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  Text {
                    text: {
                      if (!root.dockerAvailable) return "Daemon unreachable"
                      if (root.totalCount === 0) return "No containers found"
                      return root.runningCount + " Running · " + root.totalCount + " Total"
                    }
                    color: root.dockerAvailable && root.runningCount > 0 ? root.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              // Header Action Buttons
              RowLayout {
                spacing: Style.space(4)
                Layout.alignment: Qt.AlignVCenter

                PanelActionButton {
                  iconText: "󰑐"
                  tooltipText: "Refresh"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.refresh()
                }

                PanelActionButton {
                  iconText: "󰨞"
                  tooltipText: "Open Lazydocker / Terminal"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.openTui()
                }
              }
            }
          }

          // Error banner if daemon offline
          Rectangle {
            width: parent.width
            implicitHeight: errText.implicitHeight + Style.space(12)
            visible: !root.dockerAvailable
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.15)
            radius: Style.cornerRadius
            border.color: root.urgent
            border.width: 1

            Text {
              id: errText
              anchors.centerIn: parent
              text: "⚠ Docker daemon is not running or accessible without sudo."
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          // 2. Compose Projects Section
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.dockerData.projects && root.dockerData.projects.length > 0

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "COMPOSE PROJECTS (" + (root.dockerData.projects ? root.dockerData.projects.length : 0) + ")"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.dockerData.projects || []

              Column {
                id: projCol
                required property var modelData
                width: parent.width
                spacing: Style.space(4)

                readonly property var proj: modelData
                readonly property bool isExpanded: root.isProjectExpanded(proj.name)

                // Project Header Card
                Rectangle {
                  width: parent.width
                  implicitHeight: Style.space(34)
                  color: Style.hoverFillFor(root.foreground, root.accent)
                  radius: Style.cornerRadius
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                  border.width: 1

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleProjectExpanded(projCol.proj.name)
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(6)
                    spacing: Style.space(6)

                    Text {
                      text: projCol.isExpanded ? "󰅀" : "󰅂"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      text: "󰡨 " + projCol.proj.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    // Project Status Badge
                    Rectangle {
                      implicitWidth: projStatusText.implicitWidth + Style.space(8)
                      implicitHeight: Style.space(18)
                      radius: Style.cornerRadius
                      color: projCol.proj.allRunning ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2) : (projCol.proj.anyRunning ? Qt.rgba(0.9, 0.7, 0.2, 0.2) : Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.15))

                      Text {
                        id: projStatusText
                        anchors.centerIn: parent
                        text: projCol.proj.runningCount + "/" + projCol.proj.totalCount + " active"
                        color: projCol.proj.allRunning ? root.accent : (projCol.proj.anyRunning ? "#EBCB8B" : root.dim)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }

                    // Bulk Project Controls
                    PanelActionButton {
                      iconText: "󰐊"
                      tooltipText: "Start Project"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      onClicked: root.startProject(projCol.proj.name)
                    }

                    PanelActionButton {
                      iconText: "󰓛"
                      tooltipText: "Stop Project"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      onClicked: root.stopProject(projCol.proj.name)
                    }

                    PanelActionButton {
                      iconText: "󰑐"
                      tooltipText: "Restart Project"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      onClicked: root.restartProject(projCol.proj.name)
                    }
                  }
                }

                // Child Service Rows (when expanded)
                Column {
                  width: parent.width
                  spacing: Style.space(2)
                  visible: projCol.isExpanded

                  Repeater {
                    model: projCol.proj.containers || []

                    Rectangle {
                      id: childRow
                      required property var modelData
                      width: parent.width
                      implicitHeight: Style.space(32)
                      radius: Style.cornerRadius
                      color: "transparent"

                      readonly property var c: modelData

                      RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(16)
                        anchors.rightMargin: Style.space(4)
                        spacing: Style.space(6)

                        // Status dot
                        Text {
                          text: childRow.c.isRunning ? "●" : "○"
                          color: Model.statusColor(childRow.c.state, root.foreground, root.accent, root.urgent, root.dim)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }

                        // Container name & ports
                        ColumnLayout {
                          Layout.fillWidth: true
                          spacing: 0

                          Text {
                            text: childRow.c.composeService || childRow.c.name
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                          }

                          Text {
                            visible: childRow.c.ports !== "" || childRow.c.status !== ""
                            text: childRow.c.ports !== "" ? childRow.c.ports : childRow.c.status
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                          }
                        }

                        // Action Buttons
                        PanelActionButton {
                          visible: !childRow.c.isRunning
                          iconText: "󰐊"
                          tooltipText: "Start Container"
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          onClicked: root.startContainer(childRow.c.id)
                        }

                        PanelActionButton {
                          visible: childRow.c.isRunning
                          iconText: "󰓛"
                          tooltipText: "Stop Container"
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          onClicked: root.stopContainer(childRow.c.id)
                        }

                        PanelActionButton {
                          iconText: "󰑐"
                          tooltipText: "Restart Container"
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          onClicked: root.restartContainer(childRow.c.id)
                        }

                        PanelActionButton {
                          iconText: "󰈙"
                          tooltipText: "View Logs in Terminal"
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          onClicked: root.openLogs(childRow.c.id)
                        }

                        PanelActionButton {
                          visible: childRow.c.isRunning
                          iconText: "󰞷"
                          tooltipText: "Attach Shell (docker exec)"
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          onClicked: root.openExec(childRow.c.id)
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // 3. Standalone Containers Section
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.dockerData.standalone && root.dockerData.standalone.length > 0

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "STANDALONE CONTAINERS (" + (root.dockerData.standalone ? root.dockerData.standalone.length : 0) + ")"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.dockerData.standalone || []

              Rectangle {
                id: standRow
                required property var modelData
                width: parent.width
                implicitHeight: Style.space(38)
                radius: Style.cornerRadius
                color: Style.hoverFillFor(root.foreground, root.accent)
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                border.width: 1

                readonly property var c: modelData

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(6)
                  spacing: Style.space(6)

                  // Status dot
                  Text {
                    text: standRow.c.isRunning ? "●" : "○"
                    color: Model.statusColor(standRow.c.state, root.foreground, root.accent, root.urgent, root.dim)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  // Container info
                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                      text: standRow.c.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    Text {
                      text: (standRow.c.shortImage || standRow.c.image) + (standRow.c.ports ? (" · " + standRow.c.ports) : "")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }
                  }

                  // Container Actions
                  PanelActionButton {
                    visible: !standRow.c.isRunning
                    iconText: "󰐊"
                    tooltipText: "Start Container"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.startContainer(standRow.c.id)
                  }

                  PanelActionButton {
                    visible: standRow.c.isRunning
                    iconText: "󰓛"
                    tooltipText: "Stop Container"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.stopContainer(standRow.c.id)
                  }

                  PanelActionButton {
                    iconText: "󰑐"
                    tooltipText: "Restart Container"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.restartContainer(standRow.c.id)
                  }

                  PanelActionButton {
                    iconText: "󰈙"
                    tooltipText: "View Logs in Terminal"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.openLogs(standRow.c.id)
                  }

                  PanelActionButton {
                    visible: standRow.c.isRunning
                    iconText: "󰞷"
                    tooltipText: "Attach Shell (docker exec)"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.openExec(standRow.c.id)
                  }
                }
              }
            }
          }

          // 4. Empty State
          Item {
            width: parent.width
            implicitHeight: Style.space(80)
            visible: root.dockerAvailable && root.totalCount === 0

            ColumnLayout {
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                text: "󰡨"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                Layout.alignment: Qt.AlignHCenter
              }

              Text {
                text: "No Docker containers found"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                Layout.alignment: Qt.AlignHCenter
              }
            }
          }
        }
      }
    }
  }
}
