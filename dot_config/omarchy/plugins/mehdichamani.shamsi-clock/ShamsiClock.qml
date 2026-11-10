import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "mehdichamani.shamsi-clock"

  property date displayDate: clock.date

  readonly property color fgColor: (root.bar && root.bar.barForeground) ? root.bar.barForeground : Color.foreground
  readonly property color accentColor: Color.accent
  readonly property color dimColor: Qt.rgba(fgColor.r, fgColor.g, fgColor.b, 0.82)
  readonly property string barFontFamily: (root.bar && root.bar.fontFamily) ? root.bar.fontFamily : Style.font.family
  readonly property string persianFontFamily: "Vazirmatn"

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

  function refresh() {
    displayDate = new Date()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  // ---- Calendar popup contract for Bar.findPanelWidget and shell summon/hide/toggle
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function toggleWeekStart() {
    if (panelLoader.item) panelLoader.item.toggleWeekStart()
  }

  readonly property real openPanelIndicatorWidth: button.width
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  WallClock {
    id: clock
    step: 1000
    onDateChanged: root.displayDate = date
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  ShellIpc {
    target: "mehdichamani.shamsi-clock"

    function refresh(): void { root.broadcast("refresh") }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  implicitWidth: Math.max(130, colLayout.implicitWidth + 24)
  implicitHeight: root.bar ? root.bar.barSize : 38

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 8.75
    verticalPadding: 4
    tooltipText: Qt.formatDateTime(root.displayDate, "dddd, d MMMM yyyy HH:mm:ss") + " | " + root.getFullShamsiTooltip(root.displayDate)
    pressFeedbackButtons: Qt.NoButton

    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        if (root.bar) root.bar.run("omarchy-menu-timezone")
      } else if (b === Qt.LeftButton) {
        root.togglePanel()
      }
    }

    ColumnLayout {
      id: colLayout
      anchors.centerIn: parent
      spacing: 0

      // Row 1: Time
      Text {
        Layout.alignment: Qt.AlignHCenter
        text: Qt.formatDateTime(root.displayDate, "HH:mm")
        color: root.fgColor
        font.family: root.barFontFamily
        font.pixelSize: 12
        font.weight: Font.Bold
        renderType: Text.NativeRendering
      }

      // Row 2: Shamsi + Gregorian Date
      Text {
        Layout.alignment: Qt.AlignHCenter
        text: root.getShamsiString(root.displayDate) + " (" + Qt.formatDateTime(root.displayDate, "d MMMM") + ")"
        color: root.dimColor
        font.family: root.persianFontFamily
        font.pixelSize: 11
        font.weight: Font.Normal
        renderType: Text.NativeRendering
      }
    }
  }
}
