import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "GitHelper.js" as Helper

Panel {
  id: root
  moduleName: "user.git-status"
  ipcTarget: "user.git-status"
  manageIpc: true

  property var gitData: ({ repos: [], totalCount: 0, dirtyCount: 0, syncCount: 0, cleanCount: 0, errorCount: 0, attentionCount: 0 })
  property bool isRefreshing: false

  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int dirtyCount: gitData ? (gitData.dirtyCount || 0) : 0
  readonly property int syncCount: gitData ? (gitData.syncCount || 0) : 0
  readonly property int attentionCount: gitData ? (gitData.attentionCount || 0) : 0
  readonly property int totalCount: gitData ? (gitData.totalCount || 0) : 0

  function refresh() {
    if (!gitProc.running) {
      root.isRefreshing = true
      gitProc.running = true
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

  function openLazygit(repoPath) {
    var p = repoPath || "$HOME";
    runCmd("omarchy-launch-floating-terminal-with-presentation \"cd '" + p + "' && lazygit\"")
  }

  function openTerminal(repoPath) {
    var p = repoPath || "$HOME";
    runCmd("omarchy-launch-floating-terminal-with-presentation \"cd '" + p + "' && exec fish\"")
  }

  function openFileManager(repoPath) {
    var p = repoPath || "$HOME";
    runCmd("xdg-open '" + p + "'")
  }

  function fetchRepo(repoPath) {
    var p = repoPath || "$HOME";
    runCmd("git -C '" + p + "' fetch --all && notify-send -a 'Git Status' -u low 'Git Fetch' 'Fetched remote for " + p + "'")
  }

  function fetchAll() {
    runCmd("python3 -c \"import subprocess, json, os; from concurrent.futures import ThreadPoolExecutor; repos = [r['path'] for r in json.loads(open(os.path.expanduser('~/.config/omarchy/plugins/user.git-status/git-status-collector.py')).read().split('def inspect_repo')[0].split('def get_configured_repos')[0] or '[]')]\" || true")
    refresh()
  }

  // Background Git Status poller
  Process {
    id: gitProc
    command: ["python3", Quickshell.env("HOME") + "/.config/omarchy/plugins/user.git-status/git-status-collector.py"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var output = String(text || "").trim()
        root.gitData = Helper.parseGitOutput(output)
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
    interval: root.opened ? 4000 : 12000
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
    text: root.attentionCount > 0 ? ("󰊢 " + root.attentionCount) : "󰊢"
    dimmed: root.attentionCount === 0
    active: root.attentionCount > 0
    activeColor: (root.bar && root.bar.accent) ? root.bar.accent : Color.accent
    tooltipText: {
      if (root.totalCount === 0) return "Git Repositories";
      if (root.attentionCount === 0) return "All " + root.totalCount + " Git repositories clean";
      return root.attentionCount + " Git repositories need attention (" + root.dirtyCount + " dirty, " + root.syncCount + " sync)";
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else if (b === Qt.MiddleButton) {
        var firstDirty = (root.gitData && root.gitData.repos && root.gitData.repos.length > 0) ? root.gitData.repos[0].path : "";
        root.openLazygit(firstDirty)
      }
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

          // 1. Header Hero Card
          Item {
            id: headerItem
            width: parent.width
            implicitHeight: headerRow.implicitHeight + Style.space(6)

            RowLayout {
              id: headerRow
              anchors.fill: parent
              spacing: Style.space(8)

              // Git Icon & Title Info
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                Text {
                  text: "󰊢"
                  color: root.attentionCount > 0 ? root.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    text: "Git Repositories"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  Text {
                    text: {
                      if (root.totalCount === 0) return "No repositories found"
                      if (root.attentionCount === 0) return "All " + root.totalCount + " repositories clean"
                      var parts = []
                      if (root.dirtyCount > 0) parts.push(root.dirtyCount + " dirty")
                      if (root.syncCount > 0) parts.push(root.syncCount + " sync pending")
                      return parts.join(", ") + " · " + root.totalCount + " Total"
                    }
                    color: root.attentionCount > 0 ? root.accent : root.dim
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
                  tooltipText: "Refresh Git Status"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.refresh()
                }

                PanelActionButton {
                  iconText: "󰨞"
                  tooltipText: "Open Lazygit"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: {
                    var target = (root.gitData && root.gitData.repos && root.gitData.repos.length > 0) ? root.gitData.repos[0].path : "";
                    root.openLazygit(target)
                  }
                }
              }
            }
          }

          // 2. Repositories List
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.gitData.repos && root.gitData.repos.length > 0

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "MONITORED REPOSITORIES (" + (root.gitData.repos ? root.gitData.repos.length : 0) + ")"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.gitData.repos || []

              Rectangle {
                id: repoRow
                required property var modelData
                width: parent.width
                implicitHeight: Style.space(42)
                radius: Style.cornerRadius
                color: Style.hoverFillFor(root.foreground, root.accent)
                border.color: (repoRow.r.isDirty || repoRow.r.hasSync) ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                border.width: 1

                readonly property var r: modelData

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(6)
                  spacing: Style.space(8)

                  // Status Indicator Dot / Icon
                  Text {
                    text: repoRow.r.isError ? "⚠" : (repoRow.r.isDirty ? "●" : (repoRow.r.hasSync ? "󰛀" : "✓"))
                    color: repoRow.r.isError ? root.urgent : ((repoRow.r.isDirty || repoRow.r.hasSync) ? root.accent : root.dim)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    Layout.alignment: Qt.AlignVCenter
                  }

                  // Repo Title & Branch/Status
                  ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1

                    RowLayout {
                      Layout.fillWidth: true
                      Layout.minimumWidth: 0
                      spacing: Style.space(6)

                      Text {
                        text: repoRow.r.name
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.maximumWidth: Style.space(170)
                      }

                      // Branch badge
                      Rectangle {
                        implicitWidth: branchText.implicitWidth + Style.space(8)
                        implicitHeight: Style.space(16)
                        radius: Style.cornerRadius
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                        Layout.maximumWidth: Style.space(160)
                        clip: true

                        Text {
                          id: branchText
                          anchors.centerIn: parent
                          text: " " + repoRow.r.branch
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideMiddle
                          width: Math.min(implicitWidth, parent.width - Style.space(8))
                        }
                      }
                    }

                    // Status details (ahead/behind/staged/unstaged/untracked)
                    Text {
                      text: {
                        if (repoRow.r.isError) return repoRow.r.error;
                        var parts = []
                        if (repoRow.r.ahead > 0) parts.push("↑" + repoRow.r.ahead)
                        if (repoRow.r.behind > 0) parts.push("↓" + repoRow.r.behind)
                        if (repoRow.r.staged > 0) parts.push("+" + repoRow.r.staged + " staged")
                        if (repoRow.r.unstaged > 0) parts.push("*" + repoRow.r.unstaged + " modified")
                        if (repoRow.r.untracked > 0) parts.push("?" + repoRow.r.untracked + " untracked")
                        if (parts.length === 0) return "Up to date & clean"
                        return parts.join("  ·  ")
                      }
                      color: repoRow.r.isError ? root.urgent : ((repoRow.r.isDirty || repoRow.r.hasSync) ? root.accent : root.dim)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }
                  }

                  // Action Buttons for this Repo
                  RowLayout {
                    spacing: Style.space(4)
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: false

                    PanelActionButton {
                      iconText: "󰨞"
                      tooltipText: "Open in Lazygit"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      onClicked: root.openLazygit(repoRow.r.path)
                    }

                    PanelActionButton {
                      iconText: "󰑐"
                      tooltipText: "git fetch"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      onClicked: root.fetchRepo(repoRow.r.path)
                    }

                    PanelActionButton {
                      iconText: "󰞷"
                      tooltipText: "Open Terminal Here"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      onClicked: root.openTerminal(repoRow.r.path)
                    }

                    PanelActionButton {
                      iconText: "󰉋"
                      tooltipText: "Open Directory"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      onClicked: root.openFileManager(repoRow.r.path)
                    }
                  }
                }
              }
            }
          }

          // 3. Empty State
          Item {
            width: parent.width
            implicitHeight: Style.space(80)
            visible: !root.gitData.repos || root.gitData.repos.length === 0

            ColumnLayout {
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                text: "󰊢"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                Layout.alignment: Qt.AlignHCenter
              }

              Text {
                text: "No Git repositories monitored"
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
