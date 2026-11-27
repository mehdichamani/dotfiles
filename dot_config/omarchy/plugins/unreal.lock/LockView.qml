import QtQuick
import QtQuick.Effects
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property string backgroundPath: ""
  property string videoPosterPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool fingerprintUnavailable: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false
  property date currentDate: new Date()
  property int cpuPercent: 0
  property int ramPercent: 0
  property string netDownText: "0B/s"
  property string netUpText: "0B/s"
  property double prevCpuTotal: 0
  property double prevCpuIdle: 0
  property double prevNetRx: 0
  property double prevNetTx: 0
  property double prevSampleMs: 0

  readonly property string placeholderText: Commons.I18n.t("lock.enterPassword")
  readonly property int fieldWidth: 381
  readonly property int fieldHeight: 67
  readonly property int outlineThickness: 3
  readonly property int fieldFontSize: Math.round(Style.font.heading * 1.125)
  readonly property int passwordDotFontSize: Math.round(Style.font.heading * 1.33)
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.19)
  // Space to keep clear on each side of the field for the fingerprint icon
  // (icon width plus a gap) so the centered dots never run under it.
  readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
  // Shrink the dots to fit once the password outgrows the field, so every
  // keystroke stays visible — otherwise long passwords clip with no feedback.
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0
  readonly property var inputBorderSpec: errorState
    ? Border.surfaceSpec("lock", "border-error", Commons.Color.lock.borderError, root.outlineThickness, "border-alpha")
    : Border.surfaceSpec("lock", "border-active", Commons.Color.lock.borderActive, root.outlineThickness, "border-alpha")

  // A video wallpaper shows its still poster: nothing plays behind the lock.
  readonly property bool video: Util.isVideoPath(root.backgroundPath)

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  // Waking a DPMS-blanked display can stall the compositor for seconds while
  // the monitor modesets, so the wake key's release arrives late and client-side
  // key repeat floods the field with that character. A held key has no business
  // typing a password; only holding Backspace/Delete to clear stays useful.
  function dropsAutoRepeat(key) {
    return key !== Qt.Key_Backspace && key !== Qt.Key_Delete
  }

  function gregorianToJalali(gy, gm, gd) {
    var g_d_m = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
    var gy2 = (gm > 2) ? gy : (gy - 1)
    var days = 355666 + (365 * gy) + Math.floor((gy2 + 3) / 4) - Math.floor((gy2 + 99) / 100) + Math.floor((gy2 + 399) / 400) + gd + g_d_m[gm - 1]
    var jy = -1595 + (33 * Math.floor(days / 12053))
    days %= 12053
    jy += 4 * Math.floor(days / 1461)
    days %= 1461
    if (days > 365) {
      jy += Math.floor((days - 1) / 365)
      days = (days - 1) % 365
    }
    var jm, jd
    if (days < 186) {
      jm = 1 + Math.floor(days / 31)
      jd = 1 + (days % 31)
    } else {
      jm = 7 + Math.floor((days - 186) / 30)
      jd = 1 + ((days - 186) % 30)
    }
    return { year: jy, month: jm, day: jd }
  }

  function shamsiDateString(d) {
    var persianWeekdays = ["یکشنبه", "دوشنبه", "سه‌شنبه", "چهارشنبه", "پنج‌شنبه", "جمعه", "شنبه"]
    var persianMonths = [
      "فروردین", "اردیبهشت", "خرداد", "تیر", "مرداد", "شهریور",
      "مهر", "آبان", "آذر", "دی", "بهمن", "اسفند"
    ]
    var j = gregorianToJalali(d.getFullYear(), d.getMonth() + 1, d.getDate())
    return persianWeekdays[d.getDay()] + " " + j.day + " " + persianMonths[j.month - 1] + " " + j.year
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  // The field loses focus while a password is checked (it is disabled then),
  // and forcing focus onto it would not stick until the check ends.
  function restorePasswordFocus() {
    if (inputEnabled && passwordInput.enabled && !passwordInput.activeFocus) forcePasswordFocus()
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  // A VT switch, which the NVIDIA driver forces around every suspend, takes the
  // keyboard away and Qt drops the field's focus with it. Nothing gives it back
  // when the keyboard returns, so typing went nowhere until the field was clicked.
  Window.onActiveFocusItemChanged: Qt.callLater(restorePasswordFocus)
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  onVisibleChanged: if (visible) currentDate = new Date()
  onWakeRequested: currentDate = new Date()

  function formatRate(bytesPerSec) {
    if (bytesPerSec < 1024) return Math.round(bytesPerSec) + "B/s"
    if (bytesPerSec < 1024 * 1024) return (bytesPerSec / 1024).toFixed(0) + "K/s"
    if (bytesPerSec < 1024 * 1024 * 1024) return (bytesPerSec / (1024 * 1024)).toFixed(1) + "M/s"
    return (bytesPerSec / (1024 * 1024 * 1024)).toFixed(1) + "G/s"
  }

  function parseStatsOutput(raw) {
    var lines = String(raw || "").trim().split("\n")
    if (lines.length < 3) return
    var nowMs = Date.now()

    var cpuParts = lines[0].trim().split(/\s+/)
    if (cpuParts.length >= 5) {
      var total = 0
      for (var i = 0; i < cpuParts.length; i++) total += Number(cpuParts[i]) || 0
      var idle = (Number(cpuParts[3]) || 0) + (Number(cpuParts[4]) || 0)
      if (prevCpuTotal > 0 && total > prevCpuTotal) {
        var dTotal = total - prevCpuTotal
        var dIdle = idle - prevCpuIdle
        cpuPercent = Math.max(0, Math.min(100, Math.round((1 - (dIdle / dTotal)) * 100)))
      }
      prevCpuTotal = total
      prevCpuIdle = idle
    }

    var ram = Number(lines[1])
    if (isFinite(ram)) ramPercent = Math.max(0, Math.min(100, Math.round(ram)))

    var netParts = lines[2].trim().split(/\s+/)
    if (netParts.length >= 2) {
      var rx = Number(netParts[0]) || 0
      var tx = Number(netParts[1]) || 0
      if (prevSampleMs > 0 && nowMs > prevSampleMs && rx >= prevNetRx && tx >= prevNetTx) {
        var dt = (nowMs - prevSampleMs) / 1000.0
        netDownText = formatRate((rx - prevNetRx) / dt)
        netUpText = formatRate((tx - prevNetTx) / dt)
      }
      prevNetRx = rx
      prevNetTx = tx
    }
    prevSampleMs = nowMs
  }

  Timer {
    id: lockClockTimer
    interval: 1000
    repeat: true
    running: root.visible
    triggeredOnStart: true
    onTriggered: root.currentDate = new Date()
  }

  Timer {
    id: statsTimer
    interval: 2000
    repeat: true
    running: root.visible
    triggeredOnStart: true
    onTriggered: if (!statsProc.running) statsProc.running = true
  }

  Process {
    id: statsProc
    command: [
      "bash", "-c",
      "awk '/^cpu /{for(i=2;i<=NF;i++)printf \"%s \",$i; printf \"\\n\"; exit}' /proc/stat; " +
      "awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{if(t>0)printf \"%.0f\\n\",(t-a)*100/t;else print 0}' /proc/meminfo; " +
      "awk -F'[: ]+' 'NR>2 && $2!=\"lo\" && $2!=\"\"{rx+=$3; tx+=$11}END{printf \"%.0f %.0f\\n\",rx,tx}' /proc/net/dev"
    ]
    stdout: StdioCollector {
      id: statsOutput
      waitForEnd: true
      onStreamFinished: root.parseStatsOutput(statsOutput.text)
    }
  }

  // Measures the masked password at full size; passwordDotScale compares this
  // against the field width to decide how far the dots must shrink to fit.
  TextMetrics {
    id: dotMetrics
    font.family: Style.font.family
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(passwordInput.text.length)
  }

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.background

    BackgroundMedia {
      id: wallpaper
      objectName: "lockWallpaper"
      anchors.fill: parent
      path: root.loadBackground ? (root.video ? root.videoPosterPath : root.backgroundPath) : ""
      version: root.backgroundVersion
      // Decode only once sized, at the lock's own size: an unsized first
      // request decoded the file at its native resolution, then again once
      // sized. That size is what the lock service keeps decoded ahead of the
      // lock, so the first frame has the wallpaper.
      cached: true
      constrainDecode: true
      decodeSize: Qt.size(width, height)
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.ready
      blur: 1.0
      blurMax: 128
      blurMultiplier: 1.25
      contrast: -0.08
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    Column {
      id: clockBlock
      anchors.bottom: inputField.top
      anchors.bottomMargin: 44
      anchors.horizontalCenter: inputField.horizontalCenter
      spacing: 16

      OneUiClock {
        anchors.horizontalCenter: parent.horizontalCenter
        timeText: Qt.formatDateTime(root.currentDate, "HH:mm")
        clockHeight: 248
        textColor: Commons.Color.lock.text
      }

      Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.shamsiDateString(root.currentDate) + "  (" + Qt.formatDateTime(root.currentDate, "dddd, d MMMM") + ")"
        color: Commons.Color.lock.text
        opacity: 0.85
        font.family: "Vazirmatn"
        font.pixelSize: Math.round(Style.font.heading * 1.15)
        font.weight: Font.Medium
        renderType: Text.NativeRendering
      }
    }

    BorderSurface {
      id: inputField
      width: root.fieldWidth
      height: root.fieldHeight
      anchors.centerIn: parent
      color: Commons.Color.lock.background
      borderSpec: root.inputBorderSpec
      radius: Style.cornerRadius
      clip: true

      TextInput {
        id: passwordInput
        anchors.fill: parent
        anchors.topMargin: inputField.borderTop
        // Reserve the fingerprint icon's width on both sides so the centered
        // dots stay symmetric and never slide under the icon as they grow.
        anchors.rightMargin: inputField.borderRight + 18 + root.fingerprintReserve
        anchors.bottomMargin: inputField.borderBottom
        anchors.leftMargin: inputField.borderLeft + 18 + root.fingerprintReserve
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter
        activeFocusOnPress: true
        clip: true
        enabled: root.inputEnabled && !root.authenticatingPassword
        readOnly: root.authenticatingPassword
        echoMode: TextInput.Password
        passwordCharacter: "\u25CF"
        passwordMaskDelay: 0
        color: Commons.Color.lock.text
        selectionColor: Commons.Color.lock.selection
        selectedTextColor: Commons.Color.lock.text
        font.family: Style.font.family
        font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
        font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
        cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
        cursorDelegate: Rectangle {
          width: 2
          color: Commons.Color.lock.text
          visible: passwordInput.cursorVisible
        }

        onTextChanged: {
          if (!root.syncingPasswordText) root.passwordTextEdited(text)
          if (text.length > 0) {
            root.wakeRequested()
          }
          if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
        }

        onAccepted: {
          var submitted = root.passwordText
          root.passwordTextEdited("")
          if (submitted.length > 0) root.submitPassword(submitted)
        }

        Keys.onPressed: function(event) {
          root.wakeRequested()
          if (event.isAutoRepeat && root.dropsAutoRepeat(event.key)) {
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
            root.passwordTextEdited("")
            event.accepted = true
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.fill: passwordInput
        text: root.authenticatingPassword ? Commons.I18n.t("lock.checking") : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
        visible: passwordInput.text.length === 0
        color: root.authenticatingPassword ? Commons.Color.lock.text : (root.failureMessage.length > 0 ? Commons.Color.lock.textError : Commons.Color.lock.placeholder)
        font.family: Style.font.family
        font.pixelSize: root.fieldFontSize
        font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }

      // Fingerprint hint pinned inside the field's right edge when a sensor is
      // enrolled, so the user knows they can touch to unlock instead of typing.
      // Matches hyprlock, which draws its fingerprint icon in the same spot.
      // A reader the shell cannot reach crosses out rather than disappears, so
      // it stops inviting touches that can never unlock.
      Text {
        id: fingerprintIcon
        objectName: "fingerprintIndicator"
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.rightMargin: inputField.borderRight + 18
        anchors.verticalCenter: parent.verticalCenter
        visible: root.fingerprintConfigured
        text: root.fingerprintUnavailable ? "󰺱" : "󰈷"
        color: root.fingerprintUnavailable ? Commons.Color.lock.textError : Commons.Color.lock.placeholder
        font.family: Style.font.family
        font.pixelSize: Math.round(root.fieldFontSize * 1.1)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }

    // The crossed-out icon has no meaning to a user who has never seen it — it
    // is not intuitive that it signals a broken reader — so the words carry the
    // explanation and the icon only reinforces it.
    Text {
      id: fingerprintUnavailableNotice
      objectName: "fingerprintUnavailableNotice"
      textFormat: Text.PlainText
      anchors.top: inputField.bottom
      anchors.topMargin: 18
      anchors.horizontalCenter: inputField.horizontalCenter
      visible: root.fingerprintConfigured && root.fingerprintUnavailable
      text: Commons.I18n.t("lock.fingerprintUnavailable")
      color: Commons.Color.lock.textError
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      font.italic: true
      horizontalAlignment: Text.AlignHCenter
    }

    Row {
      id: systemStatsRow
      anchors.top: fingerprintUnavailableNotice.visible ? fingerprintUnavailableNotice.bottom : inputField.bottom
      anchors.topMargin: fingerprintUnavailableNotice.visible ? 14 : 22
      anchors.horizontalCenter: inputField.horizontalCenter
      spacing: 22

      Text {
        textFormat: Text.PlainText
        text: "  " + root.cpuPercent + "%"
        color: Commons.Color.lock.text
        opacity: 0.85
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.heading * 0.95)
        font.weight: Font.Medium
      }

      Text {
        textFormat: Text.PlainText
        text: "  " + root.ramPercent + "%"
        color: Commons.Color.lock.text
        opacity: 0.85
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.heading * 0.95)
        font.weight: Font.Medium
      }

      Text {
        textFormat: Text.PlainText
        text: "↓ " + root.netDownText + "  ↑ " + root.netUpText
        color: Commons.Color.lock.text
        opacity: 0.85
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.heading * 0.95)
        font.weight: Font.Medium
      }
    }
  }
}
