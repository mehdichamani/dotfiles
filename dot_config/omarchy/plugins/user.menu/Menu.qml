import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "user.menu"

  readonly property color fgColor: (root.bar && root.bar.barForeground) ? root.bar.barForeground : Color.foreground
  readonly property color accentColor: Color.accent

  implicitWidth: 38
  implicitHeight: root.bar ? root.bar.barSize : 38

  component MenuClickTarget: Item {
    id: clickRoot
    property var bar: root.bar
    property bool interactive: true
    property bool pressable: true
    property bool concealed: false
    property var registeredBar: null
    property string tooltipText: "Applications Menu"
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
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onEntered: if (root.bar && clickRoot.tooltipText !== "") root.bar.showTooltip(clickRoot, clickRoot.tooltipText)
      onExited: if (root.bar) root.bar.hideTooltip(clickRoot)
      onClicked: function(mouse) { clickRoot.triggerPress(mouse.button) }
    }
  }

  MenuClickTarget {
    id: target
    anchors.fill: parent
    onClicked: function(btn) {
      if (root.bar && typeof root.bar.run === "function") {
        root.bar.run("omarchy-menu")
      } else {
        menuProc.running = true
      }
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: 3
      radius: 6
      color: target.hovered ? Util.alpha(root.fgColor, 0.12) : "transparent"
      border.width: target.hovered ? 1 : 0
      border.color: Util.alpha(root.fgColor, 0.25)

      Text {
        anchors.centerIn: parent
        text: "󰣇"
        font.family: "Symbols Nerd Font, " + Style.font.family
        font.pixelSize: 22
        color: target.hovered ? root.accentColor : root.fgColor
        renderType: Text.NativeRendering
      }
    }
  }

  Process {
    id: menuProc
    command: ["omarchy-menu"]
    running: false
  }
}
