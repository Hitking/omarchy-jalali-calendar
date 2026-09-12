import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Jalali date/time label for the bar, and the host for the calendar popup.
//
// Left click reveals the calendar — asking "what is the date?" is what a
// click on a clock means — right click walks the common label formats, and
// middle click opens the timezone picker.
//
// The label is formatted by Model.format rather than Qt.formatDateTime: Qt
// has no Jalali calendar and would answer every format string in Gregorian.
BarWidget {
  id: root
  moduleName: "masoud.jalali-calendar"

  property date displayDate: clock.date

  // Which calendar the label is written in. Switching it is what lets this
  // widget replace Omarchy's clock outright instead of sitting beside it.
  readonly property string calendar: Model.normalizeCalendar(setting("calendar", Model.JALALI))

  // Vazirmatn by default, because the bar's own family is a monospace
  // programming face that renders Persian, if at all, in a fallback nobody
  // chose. The face ships with the plugin -- see the FontLoaders below -- so
  // this default works on a machine with no Persian font installed. Blank
  // falls back to the bar's family.
  readonly property string configuredFontFamily: setting("fontFamily", "Vazirmatn")
  readonly property string iconFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string contentFontFamily: configuredFontFamily !== ""
    ? configuredFontFamily
    : iconFontFamily

  readonly property bool persianDigits: Model.resolveBoolean(
    setting("persianDigits", null), Model.usesPersianDigitsByDefault(calendar))

  readonly property string configuredFormat: vertical
    ? setting("verticalFormat", "HH\n—\nmm")
    : setting("format", "dddd HH:mm")
  readonly property string configuredAltFormat: vertical
    ? setting("verticalFormatAlt", "dd\nMMM\nyy")
    : setting("formatAlt", "dddd d MMMM yyyy")

  // The ring follows the calendar, so right-clicking under Gregorian walks
  // the built-in clock's own presets, ISO week token and all.
  readonly property var formatRing: Model.clockFormatRing(
    configuredFormat, configuredAltFormat, Model.clockFormats(vertical, calendar))

  // What the bar shows is what shell.json stores, so a cycled format is the
  // format from then on rather than something that reverts on restart.
  readonly property string activeFormat: configuredFormat

  // ---- The next thing coming up. The panel owns the file and the calendar
  //      filtering; the bar just reads the already-filtered list off it. The
  //      panel Loader is active even while closed, so this keeps counting
  //      whether or not anyone has opened the calendar.
  //
  //      displayDate is driven by SystemClock at minute precision, which is
  //      exactly the granularity a "۱۰ دقیقه دیگر" countdown needs. No extra
  //      timer.
  readonly property var visibleEventList: panelLoader.item ? panelLoader.item.visibleEventList : []
  readonly property real nowMs: displayDate.getTime()

  readonly property int announceLeadMinutes: setting("announceLeadMinutes", 15)
  readonly property var upcomingEvent: Model.nextEvent(visibleEventList, nowMs)
  readonly property bool announcing: announceLeadMinutes > 0
    && Model.shouldAnnounce(upcomingEvent, nowMs, announceLeadMinutes)

  readonly property string countdownPhrase: announcing
    ? (Model.formatCountdown(Model.millisUntil(upcomingEvent, nowMs),
        { calendar: root.calendar, persianDigits: root.persianDigits }) || "")
    : ""

  // The clock stays. This widget replaces the desktop's clock, so trading the
  // time away for a title would be a downgrade the rest of the day pays for.
  //
  // A vertical bar is left as a clock: it is a narrow column of stacked
  // lines, and an event title has nowhere to go in it.
  readonly property string displayText: vertical || countdownPhrase === ""
    ? formatted(displayDate)
    : Model.announceLabel(formatted(displayDate), upcomingEvent.title, countdownPhrase)
  readonly property var verticalLines: displayText.split("\n")

  function refresh() {
    displayDate = new Date()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function cycleFormat() {
    var current = String(configuredFormat)
    var next = Model.nextClockFormat(formatRing, current)
    if (next === "" || next === current) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[vertical ? "verticalFormat" : "format"] = next

    // Applied locally first so the label changes on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Month and day names in Gregorian mode come from the panel, which asks
  // Qt's locale for them; the bar reads them off it rather than keeping a
  // second copy of that logic.
  readonly property var localeNames: panelLoader.item ? panelLoader.item.localeNames : null

  function formatted(date) {
    return Model.format(date, activeFormat, {
      calendar: root.calendar,
      persianDigits: root.persianDigits,
      names: root.localeNames
    })
  }

  // ---- Calendar popup. Shape contract for shell.summon/hide/toggle
  //      routing: Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root.
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

  function openSettings() {
    if (panelLoader.item) panelLoader.item.openSettings()
  }

  function toggleWeekStart() {
    if (panelLoader.item) panelLoader.item.toggleWeekStart()
  }

  function toggleCalendar() {
    if (panelLoader.item) panelLoader.item.toggleCalendar()
  }

  function setCalendar(value) {
    if (panelLoader.item) panelLoader.item.setCalendar(value)
  }

  // The clock fills more slot than it paints a mark for, at both
  // orientations: horizontally it is a text label in a padded slot, so the
  // dot takes the label width; vertically it is a stack of icon-sized lines,
  // so the dot takes one line — the same mark every icon widget gets, rather
  // than a rule running the height of the whole stack.
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
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

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.displayDate = date
  }

  // The bar renders before the panel is loaded and outlives it being closed,
  // so it loads the bundled face itself rather than relying on the panel
  // having done it. Registering a family twice is free.
  FontLoader { source: Qt.resolvedUrl("fonts/Vazirmatn-Regular.ttf") }
  FontLoader { source: Qt.resolvedUrl("fonts/Vazirmatn-Bold.ttf") }

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

  IpcHandler {
    target: "jalali-calendar"

    function refresh(): void { root.broadcast("refresh") }
    function cycleFormat(): void { root.cycleFormat() }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function toggleCalendar(): void { root.toggleCalendar() }
    function setCalendar(system: string): void { root.setCalendar(system) }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function settings(): void { root.openSettings() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    fontFamily: root.contentFontFamily
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleFormat()
      else if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-menu-timezone") }
      else root.togglePanel()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3
            ? button.fontSize * 0.9
            : button.fontSize
          color: button.foreground
        }
      }
    }
  }
}
