import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "user.wireguard"
  ipcTarget: "user.wireguard"
  manageIpc: false

  property string focusSection: "header"
  property int connectionIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0

  readonly property var activePhrases: [
    "Securing tunnels",
    "Routing crypto packets",
    "Guarding endpoints",
    "Shielding traffic",
    "Protecting peers"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: wireguard.active ? foreground : dim
  readonly property color barIconColor: wireguard.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property string toggleHint: wireguard.active ? "Disconnect WireGuard" : "Connect WireGuard"

  function selectedConnection() {
    if (wireguard.connections.length === 0) return null
    return wireguard.connections[Math.max(0, Math.min(connectionIndex, wireguard.connections.length - 1))]
  }

  function ensureCursor() {
    if (connectionIndex >= wireguard.connections.length) connectionIndex = Math.max(0, wireguard.connections.length - 1)
    if (focusSection === "connections" && wireguard.connections.length === 0) focusSection = "header"
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy !== 0) {
      if (focusSection === "header") {
        if (dy > 0 && wireguard.connections.length > 0) focusSection = "connections"
      } else if (focusSection === "connections") {
        if (dy < 0) {
          if (connectionIndex <= 0) focusSection = "header"
          else connectionIndex--
        } else if (dy > 0) {
          if (connectionIndex < wireguard.connections.length - 1) connectionIndex++
        }
      }
    }
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") {
      wireguard.togglePrimary()
    } else if (focusSection === "connections") {
      var conn = selectedConnection()
      if (conn) wireguard.toggleConnection(conn.name)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    wireguard.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: wireguard
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { wireguard.refresh(); return "ok" }
    function togglePrimary(): string { wireguard.togglePrimary(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        WireguardIcon {
          anchors.centerIn: parent
          iconSize: Style.space(13)
          color: root.barIconColor
          badgeColor: root.urgent
          crossed: !wireguard.active
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) wireguard.togglePrimary()
      else if (buttonCode === Qt.MiddleButton) wireguard.refresh()
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(480))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") wireguard.togglePrimary()
        else if (t === "c" || t === "C") {
          var sc = root.selectedConnection()
          if (sc && sc.ip) wireguard.copyToClipboard(sc.ip, sc.name + " IP")
        }
        else if (t === "e" || t === "E") {
          var sce = root.selectedConnection()
          if (sce && sce.endpoint) wireguard.copyToClipboard(sce.endpoint, sce.name + " Endpoint")
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.cursorActive && root.focusSection === "header"

            PanelHero {
              id: hero
              width: parent.width
              title: wireguard.activeName ? wireguard.activeName : "WireGuard"
              meta: wireguard.active ? root.heroPhraseText : "WireGuard is disconnected"
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: wireguard.active ? 1.0 : 0.5

              iconComponent: Component {
                WireguardIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  badgeColor: root.urgent
                  crossed: !wireguard.active
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  checked: wireguard.active
                  busy: wireguard.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) {
                    if (on) {
                      root.cursorActive = true
                      root.focusSection = "header"
                    }
                  }
                  onToggled: wireguard.togglePrimary()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: wireguard.actionStatus !== "" || wireguard.lastError !== ""
            width: parent.width
            text: wireguard.actionStatus !== "" ? wireguard.actionStatus : wireguard.lastError
            color: wireguard.lastError !== "" && wireguard.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            visible: wireguard.connections.length > 0
            foreground: root.foreground
          }

          Column {
            visible: wireguard.connections.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "TUNNELS / PROFILES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: connectionColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: wireguard.connections
                ConnectionRow {
                  required property var modelData
                  required property int index
                  width: connectionColumn.width
                  conn: modelData
                  rowIndex: index
                }
              }
            }
          }

          Text {
            visible: wireguard.connections.length === 0
            width: parent.width
            text: "No WireGuard connections found in NetworkManager."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && wireguard.active
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  component ConnectionRow: CursorSurface {
    id: connRow
    property var conn: null
    property int rowIndex: 0

    readonly property bool isSelected: root.cursorActive && root.focusSection === "connections" && root.connectionIndex === rowIndex
    readonly property bool isConnActive: conn && conn.active === true
    readonly property string connName: conn ? String(conn.name || "Unknown") : "Unknown"
    readonly property string connIp: conn ? String(conn.ip || "") : ""
    readonly property string connEndpoint: conn ? String(conn.endpoint || "") : ""

    hasCursor: isSelected
    current: isConnActive
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill

    implicitHeight: Math.max(contentCol.implicitHeight, Style.space(34)) + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "connections"
        root.connectionIndex = connRow.rowIndex
      }
      onClicked: if (connRow.conn) wireguard.toggleConnection(connRow.conn.name)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        text: isConnActive ? "󰌾" : "󰌿"
        color: isConnActive ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: contentCol
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: connRow.connName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: isConnActive
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          visible: connRow.connIp !== "" || connRow.connEndpoint !== ""
          Layout.fillWidth: true
          text: {
            var parts = []
            if (connRow.connIp !== "") parts.push(connRow.connIp)
            if (connRow.connEndpoint !== "") parts.push(connRow.connEndpoint)
            return parts.join(" · ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        visible: connRow.connIp !== ""
        iconText: "󰆏"
        tooltipText: "Copy IP (" + connRow.connIp + ")"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: wireguard.copyToClipboard(connRow.connIp, connRow.connName + " IP")
      }

      ToggleSwitch {
        trackHeight: Math.round(Style.font.bodySmall * 1.3)
        cursorPad: Style.space(2)
        checked: isConnActive
        busy: wireguard.actionStatus.indexOf(connRow.connName) !== -1
        foreground: root.foreground
        Layout.alignment: Qt.AlignVCenter
        onToggled: if (connRow.conn) wireguard.toggleConnection(connRow.conn.name)
      }
    }
  }
}
