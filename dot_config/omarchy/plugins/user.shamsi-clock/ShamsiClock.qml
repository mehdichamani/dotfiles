import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "user.shamsi-clock"

  readonly property color fgColor: (root.bar && root.bar.barForeground) ? root.bar.barForeground : Color.foreground
  readonly property color accentColor: Color.accent
  readonly property color dimColor: Qt.rgba(fgColor.r, fgColor.g, fgColor.b, 0.82)
  readonly property string barFontFamily: (root.bar && root.bar.fontFamily) ? root.bar.fontFamily : Style.font.family
  implicitWidth: Math.max(130, colLayout.implicitWidth + 16)
  implicitHeight: root.bar ? root.bar.barSize : 38

  property var currentDate: new Date()

  // High precision Jalali (Solar Hijri) Calendar algorithm
  function gregorianToJalali(gy, gm, gd) {
    var g_d_m = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
    var gy2 = (gm > 2) ? gy : (gy - 1);
    var days = 355666 + (365 * gy) + Math.floor((gy2 + 3) / 4) - Math.floor((gy2 + 99) / 100) + Math.floor((gy2 + 399) / 400) + gd + g_d_m[gm - 1];
    var jy = -1595 + (33 * Math.floor(days / 12053));
    days %= 12053;
    jy += 4 * Math.floor(days / 1461);
    days %= 1461;
    if (days > 365) {
      jy += Math.floor((days - 1) / 365);
      days = (days - 1) % 365;
    }
    var jm, jd;
    if (days < 186) {
      jm = 1 + Math.floor(days / 31);
      jd = 1 + (days % 31);
    } else {
      jm = 7 + Math.floor((days - 186) / 30);
      jd = 1 + ((days - 186) % 30);
    }
    return { year: jy, month: jm, day: jd };
  }

  function getShamsiString(d) {
    var persianWeekdays = ["یکشنبه", "دوشنبه", "سه‌شنبه", "چهارشنبه", "پنج‌شنبه", "جمعه", "شنبه"];
    var persianMonths = [
      "فروردین", "اردیبهشت", "خرداد", "تیر", "مرداد", "شهریور",
      "مهر", "آبان", "آذر", "دی", "بهمن", "اسفند"
    ];

    var j = gregorianToJalali(d.getFullYear(), d.getMonth() + 1, d.getDate());
    var dayOfWeek = persianWeekdays[d.getDay()];
    var monthName = persianMonths[j.month - 1];

    // Format: چهارشنبه 4 شهریور
    return dayOfWeek + " " + j.day + " " + monthName;
  }

  function getFullShamsiTooltip(d) {
    var j = gregorianToJalali(d.getFullYear(), d.getMonth() + 1, d.getDate());
    var persianMonths = [
      "فروردین", "اردیبهشت", "خرداد", "تیر", "مرداد", "شهریور",
      "مهر", "آبان", "آذر", "دی", "بهمن", "اسفند"
    ];
    return j.day + " " + persianMonths[j.month - 1] + " " + j.year;
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      root.currentDate = new Date();
    }
  }

  // Register click target with Omarchy bar
  component ShamsiClickTarget: Item {
    id: clickRoot
    property var bar: root.bar
    property bool interactive: true
    property bool pressable: true
    property bool concealed: false
    property var registeredBar: null
    property string tooltipText: ""

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

  ShamsiClickTarget {
    anchors.fill: parent
    tooltipText: Qt.formatDateTime(root.currentDate, "dddd, d MMMM yyyy HH:mm:ss") + " | " + root.getFullShamsiTooltip(root.currentDate)
  }

  readonly property string persianFontFamily: "Vazirmatn"

  ColumnLayout {
    id: colLayout
    anchors.centerIn: parent
    spacing: 0

    // Row 1: Clock (Top)
    Text {
      Layout.alignment: Qt.AlignHCenter
      text: Qt.formatDateTime(root.currentDate, "HH:mm")
      color: root.fgColor
      font.family: root.barFontFamily
      font.pixelSize: 12
      font.weight: Font.Bold
      renderType: Text.NativeRendering
    }

    // Row 2: Wednesday August 26 (Middle)
    Text {
      Layout.alignment: Qt.AlignHCenter
      text: Qt.formatDateTime(root.currentDate, "dddd MMMM d")
      color: root.dimColor
      font.family: root.barFontFamily
      font.pixelSize: 10
      font.weight: Font.Normal
      renderType: Text.NativeRendering
    }

    // Row 3: چهارشنبه 4 شهریور (Bottom)
    Text {
      Layout.alignment: Qt.AlignHCenter
      text: root.getShamsiString(root.currentDate)
      color: root.dimColor
      font.family: root.persianFontFamily
      font.pixelSize: 11
      font.weight: Font.Normal
      renderType: Text.NativeRendering
    }
  }
}
