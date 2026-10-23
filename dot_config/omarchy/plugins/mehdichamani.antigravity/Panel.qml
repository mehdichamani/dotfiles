import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "mehdichamani.antigravity"
  ipcTarget: "mehdichamani.antigravity"
  manageIpc: true

  property var quotaData: ({
    ok: true,
    five_hour_percent: 100,
    five_hour_reset: "",
    weekly_percent: 100,
    weekly_reset: "",
    min_percent: 100,
    time_str: ""
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

  readonly property int minPercent: quotaData ? (quotaData.min_percent !== undefined ? quotaData.min_percent : 100) : 100
  readonly property color statusColor: {
    if (root.isError) return root.urgent
    if (minPercent <= 15) return root.urgent
    if (minPercent <= 35) return "#e0af68" // Warning yellow/amber
    return root.accent
  }

  function refresh(force) {
    if (!fetchProc.running) {
      root.isRefreshing = true
      fetchProc.command = force ?
        [Quickshell.env("HOME") + "/.config/omarchy/plugins/mehdichamani.antigravity/fetch_usage.py", "--force"] :
        [Quickshell.env("HOME") + "/.config/omarchy/plugins/mehdichamani.antigravity/fetch_usage.py"]
      fetchProc.running = true
    }
  }

  function openAgy() {
    if (root.bar) {
      root.bar.run("omarchy-launch-floating-terminal-with-presentation \"agy\"")
    }
  }

  Process {
    id: fetchProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/mehdichamani.antigravity/fetch_usage.py"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(text || "").trim()
        if (out.length > 0) {
          try {
            var parsed = JSON.parse(out)
            if (parsed.ok) {
              root.quotaData = parsed
              root.isError = false
              root.errorMessage = ""
            } else {
              root.isError = true
              root.errorMessage = parsed.error || "Failed to fetch Gemini quota"
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
      if (code !== 0 && !root.quotaData.ok) {
        root.isError = true
      }
    }
  }

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

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰚩"
    useActiveColor: false
    tooltipText: "Gemini Quota: " + root.minPercent + "% remaining (Weekly: " +
                 (root.quotaData ? root.quotaData.weekly_percent : 0) + "%, 5h: " +
                 (root.quotaData ? root.quotaData.five_hour_percent : 0) + "%)"

    iconComponent: Component {
      Item {
        anchors.fill: parent

        Text {
          anchors.centerIn: parent
          text: "󰚩"
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
          color: root.foreground
        }

        BorderSurface {
          visible: root.minPercent < 20 || root.isError
          width: Math.max(7, parent.width * 0.42)
          height: width
          radius: width / 2
          color: root.urgent
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          borderSpec: Border.flat(Color.popups.background, 1)

          Text {
            anchors.centerIn: parent
            text: "!"
            color: Color.background
            font.family: root.fontFamily
            font.pixelSize: Math.max(6, parent.height * 0.72)
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

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight + Style.space(16), Style.space(480))

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
          spacing: Style.space(14)

          // 1. Header Card
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)

              Text {
                text: "󰚩"
                color: root.statusColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                Layout.alignment: Qt.AlignVCenter
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                  text: "Gemini Models"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }

                Text {
                  text: root.quotaData && root.quotaData.time_str ?
                        "Updated at " + root.quotaData.time_str : "Antigravity Pro"
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
                tooltipText: "Refresh Quota"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.refresh(true)
              }

              PanelActionButton {
                iconText: "󰞷"
                tooltipText: "Launch agy CLI"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.openAgy()
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

          // Separator
          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
          }

          // 2. Five Hour Session Card
          ColumnLayout {
            width: parent.width
            spacing: Style.space(6)

            RowLayout {
              Layout.fillWidth: true
              Text {
                text: "Session (5-hour)"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Item { Layout.fillWidth: true }
              Text {
                text: (root.quotaData ? root.quotaData.five_hour_percent : 0) + "% remaining"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            // Progress Bar
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(8)
              radius: 4
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

              Rectangle {
                width: parent.width * (Math.max(0, Math.min(100, (root.quotaData ? root.quotaData.five_hour_percent : 0))) / 100)
                height: parent.height
                radius: 4
                color: {
                  var p = root.quotaData ? root.quotaData.five_hour_percent : 100
                  if (p <= 15) return root.urgent
                  if (p <= 35) return "#e0af68"
                  return root.accent
                }
              }
            }

            Text {
              visible: !!(root.quotaData && (root.quotaData.five_hour_reset_rel || root.quotaData.five_hour_reset))
              text: "Resets " + (root.quotaData.five_hour_reset_rel ? "in " + root.quotaData.five_hour_reset_rel : root.quotaData.five_hour_reset)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // 3. Weekly Limit Card
          ColumnLayout {
            width: parent.width
            spacing: Style.space(6)

            RowLayout {
              Layout.fillWidth: true
              Text {
                text: "Weekly Limit"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Item { Layout.fillWidth: true }
              Text {
                text: (root.quotaData ? root.quotaData.weekly_percent : 0) + "% remaining"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            // Progress Bar
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(8)
              radius: 4
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

              Rectangle {
                width: parent.width * (Math.max(0, Math.min(100, (root.quotaData ? root.quotaData.weekly_percent : 0))) / 100)
                height: parent.height
                radius: 4
                color: {
                  var p = root.quotaData ? root.quotaData.weekly_percent : 100
                  if (p <= 15) return root.urgent
                  if (p <= 35) return "#e0af68"
                  return root.accent
                }
              }
            }

            Text {
              visible: !!(root.quotaData && (root.quotaData.weekly_reset_rel || root.quotaData.weekly_reset))
              text: "Resets " + (root.quotaData.weekly_reset_rel ? "in " + root.quotaData.weekly_reset_rel : root.quotaData.weekly_reset)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
