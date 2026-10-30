import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "mehdichamani.tasks"
  ipcTarget: "mehdichamani.tasks"
  manageIpc: true

  property var tasksData: ({
    ok: true,
    count: 0,
    root_count: 0,
    tasks: [],
    updated_at: "",
    error: ""
  })
  property bool isRefreshing: false
  property bool isError: false
  property string errorMessage: ""

  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: (bar && bar.accent) ? bar.accent : Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int taskCount: tasksData ? (tasksData.count || 0) : 0
  readonly property string scriptPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/mehdichamani.tasks/tasks_backend.py"

  function refresh(force) {
    if (!fetchProc.running) {
      root.isRefreshing = true
      fetchProc.command = force ?
        [root.scriptPath, "list", "--force"] :
        [root.scriptPath, "list"]
      fetchProc.running = true
    }
  }

  function addTask(title) {
    var t = String(title || "").trim()
    if (t.length === 0) return
    actionProc.command = [root.scriptPath, "add", t]
    actionProc.running = true
    actionRefreshTimer.restart()
  }

  function removeTaskFromState(taskId) {
    if (!root.tasksData || !root.tasksData.tasks) return
    var newTasks = []
    var totalCount = 0
    for (var i = 0; i < root.tasksData.tasks.length; i++) {
      var item = root.tasksData.tasks[i]
      if (item.id === taskId) {
        continue
      }
      var copy = Object.assign({}, item)
      if (copy.subtasks && copy.subtasks.length > 0) {
        copy.subtasks = copy.subtasks.filter(function(st) { return st.id !== taskId })
        totalCount += copy.subtasks.length
      }
      totalCount += 1
      newTasks.push(copy)
    }
    root.tasksData.tasks = newTasks
    root.tasksData.count = totalCount
  }

  function completeTask(taskId) {
    if (!taskId) return
    root.removeTaskFromState(taskId)
    actionProc.command = [root.scriptPath, "complete", taskId]
    actionProc.running = true
    actionRefreshTimer.restart()
  }

  function deleteTask(taskId) {
    if (!taskId) return
    root.removeTaskFromState(taskId)
    actionProc.command = [root.scriptPath, "delete", taskId]
    actionProc.running = true
    actionRefreshTimer.restart()
  }

  function openTodoistWeb() {
    Quickshell.execDetached(["xdg-open", "https://app.todoist.com"])
  }

  // Fetch process
  Process {
    id: fetchProc
    command: [root.scriptPath, "list"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(text || "").trim()
        if (out.length > 0) {
          try {
            var parsed = JSON.parse(out)
            if (parsed.ok) {
              root.tasksData = parsed
              root.isError = false
              root.errorMessage = ""
            } else {
              root.isError = true
              root.errorMessage = parsed.error || "Failed to fetch tasks"
            }
          } catch(e) {
            root.isError = true
            root.errorMessage = "JSON parse error"
          }
        }
      }
    }
    onExited: function(code) {
      root.isRefreshing = false
      if (code !== 0 && !root.tasksData.ok) {
        root.isError = true
      }
    }
  }

  // Action process (add / complete / delete)
  Process {
    id: actionProc
    running: false
  }

  Timer {
    id: actionRefreshTimer
    interval: 800
    repeat: false
    onTriggered: root.refresh(true)
  }

  // Polling timer
  Timer {
    id: pollTimer
    interval: root.opened ? 15000 : 45000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: root.barSize

  // 1. Status Bar Icon & Badge
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰄲"
    useActiveColor: false
    tooltipText: root.taskCount > 0 ?
                 root.taskCount + " pending task" + (root.taskCount > 1 ? "s" : "") + " (Todoist · S24 & Watch Synced)" :
                 "Todoist (Synced with S24 & Watch)"

    iconComponent: Component {
      Item {
        anchors.fill: parent

        Text {
          anchors.centerIn: parent
          text: "󰄲"
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
          color: root.taskCount > 0 ? root.accent : root.foreground
        }

        // Counter badge
        BorderSurface {
          visible: root.taskCount > 0
          width: Math.max(14, badgeText.implicitWidth + Style.space(6))
          height: 14
          radius: height / 2
          color: root.accent
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.topMargin: Style.space(2)
          borderSpec: Border.flat(Color.popups.background, 1)

          Text {
            id: badgeText
            anchors.centerIn: parent
            text: String(root.taskCount)
            color: Color.background
            font.family: root.fontFamily
            font.pixelSize: 9
            font.bold: true
          }
        }
      }
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.refresh(true)
      } else {
        root.toggle()
      }
    }
  }

  // 2. Interactive Popup Drawer
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight + Style.space(20), Style.space(540))

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

        Column {
          id: panelColumn
          width: panelFlick.width
          spacing: Style.space(12)

          // Header Card
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)

              Text {
                text: "󰄲"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                Layout.alignment: Qt.AlignVCenter
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                  text: "Todoist"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }

                Text {
                  text: root.taskCount > 0 ?
                        root.taskCount + " pending · S24 & Watch Synced" :
                        "All completed · Synced"
                  color: root.dim
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
                tooltipText: "Refresh Tasks"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.refresh(true)
              }

              PanelActionButton {
                iconText: "󰖟"
                tooltipText: "Open Todoist Web"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.openTodoistWeb()
              }
            }
          }

          // Error Banner if needed
          Rectangle {
            width: parent.width
            implicitHeight: errText.implicitHeight + Style.space(10)
            visible: root.isError
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.15)
            radius: Style.cornerRadius
            border.color: root.urgent

            Text {
              id: errText
              anchors.centerIn: parent
              width: parent.width - Style.space(16)
              text: root.errorMessage
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
              horizontalAlignment: Text.AlignHCenter
            }
          }

          // Quick Add Input Box
          Rectangle {
            width: parent.width
            height: Style.space(38)
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
            border.width: 1
            border.color: taskInput.activeFocus ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(8)

              Text {
                text: "󰐕"
                color: taskInput.activeFocus ? root.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                Layout.alignment: Qt.AlignVCenter
              }

              Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  visible: taskInput.text.length === 0 && !taskInput.activeFocus
                  text: "New task... (e.g. Meeting @ tomorrow 18:30) (Enter)"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                TextInput {
                  id: taskInput
                  anchors.fill: parent
                  verticalAlignment: TextInput.AlignVCenter
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  clip: true
                  onAccepted: {
                    root.addTask(text)
                    text = ""
                  }
                }
              }

              Text {
                visible: taskInput.text.length > 0
                text: "↵"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                Layout.alignment: Qt.AlignVCenter

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.addTask(taskInput.text)
                    taskInput.text = ""
                  }
                }
              }
            }
          }

          // Separator
          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
          }

          // Section Header: Tasks
          RowLayout {
            width: parent.width
            Text {
              text: "TASKS (" + root.taskCount + ")"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Item { Layout.fillWidth: true }
            Text {
              visible: !!(root.tasksData && root.tasksData.updated_at)
              text: "Synced " + root.tasksData.updated_at
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // Empty state
          Rectangle {
            width: parent.width
            implicitHeight: emptyCol.implicitHeight + Style.space(24)
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
            visible: root.taskCount === 0 && !root.isError

            ColumnLayout {
              id: emptyCol
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                text: "󰄲"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                Layout.alignment: Qt.AlignHCenter
              }

              Text {
                text: "هیچ یادآوری برای انجام باقی نمانده"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
              }

              Text {
                text: "کارهای تیک خورده روی ساعت و موبایل سینک شدند"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                Layout.alignment: Qt.AlignHCenter
              }
            }
          }

          // Task List Repeater
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.taskCount > 0

            Repeater {
              model: (root.tasksData && root.tasksData.tasks) ? root.tasksData.tasks : []

              delegate: Rectangle {
                id: taskCard
                width: parent.width
                implicitHeight: taskCol.implicitHeight + Style.space(14)
                radius: Style.cornerRadius
                color: taskHover.hovered ?
                       Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07) :
                       Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
                border.width: 1
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)

                HoverHandler {
                  id: taskHover
                }

                ColumnLayout {
                  id: taskCol
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(6)

                  // 1. Root Task Row
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(10)

                    // Checkbox (Click to complete)
                    Rectangle {
                      width: Style.space(22)
                      height: width
                      radius: width / 2
                      color: "transparent"
                      border.width: 1.5
                      border.color: checkHover.hovered ? root.accent : root.dim
                      Layout.alignment: Qt.AlignVCenter

                      Text {
                        anchors.centerIn: parent
                        text: "✓"
                        color: root.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        visible: checkHover.hovered
                      }

                      HoverHandler {
                        id: checkHover
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.completeTask(modelData.id)
                      }
                    }

                    // Title, Due Badge, and Notes
                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 2

                      RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(6)

                        Text {
                          text: modelData.title
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          wrapMode: Text.Wrap
                          Layout.fillWidth: true
                        }

                        // Due Badge
                        Rectangle {
                          visible: !!(modelData.due_badge && modelData.due_badge.length > 0)
                          height: Style.space(18)
                          width: dueBadgeText.implicitWidth + Style.space(10)
                          radius: height / 2
                          color: modelData.is_overdue ?
                                 Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.15) :
                                 Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
                          border.width: 1
                          border.color: modelData.is_overdue ? root.urgent : root.accent

                          Text {
                            id: dueBadgeText
                            anchors.centerIn: parent
                            text: modelData.due_badge || ""
                            color: modelData.is_overdue ? root.urgent : root.accent
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.bold: true
                          }
                        }
                      }

                      Text {
                        visible: !!(modelData.notes && modelData.notes.length > 0)
                        text: modelData.notes || ""
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                      }
                    }

                    // Delete button
                    Rectangle {
                      width: Style.space(20)
                      height: width
                      radius: width / 2
                      color: "transparent"
                      visible: taskHover.hovered
                      Layout.alignment: Qt.AlignVCenter

                      Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        color: delHover.hovered ? root.urgent : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                      }

                      HoverHandler {
                        id: delHover
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.deleteTask(modelData.id)
                      }
                    }
                  }

                  // 2. Subtasks Section (Indented)
                  Column {
                    Layout.fillWidth: true
                    Layout.leftMargin: Style.space(28)
                    spacing: Style.space(6)
                    visible: !!(modelData.subtasks && modelData.subtasks.length > 0)

                    Repeater {
                      model: modelData.subtasks || []

                      delegate: RowLayout {
                        id: subtaskRow
                        width: parent ? parent.width : 0
                        spacing: Style.space(8)

                        // Subtask Checkbox
                        Rectangle {
                          width: Style.space(16)
                          height: width
                          radius: width / 2
                          color: "transparent"
                          border.width: 1.2
                          border.color: subCheckHover.hovered ? root.accent : root.dim
                          Layout.alignment: Qt.AlignVCenter

                          Text {
                            anchors.centerIn: parent
                            text: "✓"
                            color: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: 8
                            font.bold: true
                            visible: subCheckHover.hovered
                          }

                          HoverHandler {
                            id: subCheckHover
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.completeTask(modelData.id)
                          }
                        }

                        // Subtask Title
                        Text {
                          text: modelData.title
                          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.85)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          wrapMode: Text.Wrap
                          Layout.fillWidth: true
                          Layout.alignment: Qt.AlignVCenter
                        }

                        // Subtask Due Badge
                        Rectangle {
                          visible: !!(modelData.due_badge && modelData.due_badge.length > 0)
                          height: Style.space(15)
                          width: subDueBadgeText.implicitWidth + Style.space(6)
                          radius: height / 2
                          color: modelData.is_overdue ?
                                 Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.12) :
                                 Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.1)
                          border.width: 1
                          border.color: modelData.is_overdue ? root.urgent : root.accent

                          Text {
                            id: subDueBadgeText
                            anchors.centerIn: parent
                            text: modelData.due_badge || ""
                            color: modelData.is_overdue ? root.urgent : root.accent
                            font.family: root.fontFamily
                            font.pixelSize: 8
                            font.bold: true
                          }
                        }

                        // Subtask Delete Button
                        Rectangle {
                          width: Style.space(16)
                          height: width
                          radius: width / 2
                          color: "transparent"
                          visible: subHover.hovered
                          Layout.alignment: Qt.AlignVCenter

                          Text {
                            anchors.centerIn: parent
                            text: "󰅖"
                            color: subDelHover.hovered ? root.urgent : root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }

                          HoverHandler {
                            id: subDelHover
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.deleteTask(modelData.id)
                          }
                        }

                        HoverHandler {
                          id: subHover
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
