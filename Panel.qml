import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The Jalali clock's calendar popup: a month grid with Jalali week numbers,
// built to sit beside the weather panel — same hero-over-detail composition,
// same spacing scale, same small-caps labels.
//
// The grid is a read-out rather than a picker: today is the only marked
// day, and the only thing that moves is which month is on screen —
// chevrons, the scroll wheel, and the arrow keys all step it.
//
// Two things run through the whole file and are worth stating once:
//
//  - `viewYear`/`viewMonth` are Jalali, and `viewMonth` is 1-12, the way a
//    Jalali month is written. Only day *keys* stay Gregorian, because that is
//    the contract the events file is written to.
//  - The layout mirrors under LayoutMirroring rather than being rebuilt
//    right-to-left by hand, so the same anchors describe both directions.
//    Anything positioned by an explicit `x` is mirrored by hand instead,
//    because LayoutMirroring only reaches anchors and positioners.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "masoud.jalali-calendar"
  ipcTarget: "jalali-calendar"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)
  readonly property var todayJalali: Model.jalaliFromDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: todayJalali.jy
  property int viewMonth: todayJalali.jm

  readonly property bool viewingCurrentMonth: viewYear === todayJalali.jy && viewMonth === todayJalali.jm

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone. Measured on the
  // Jalali year, so the bar empties at Nowruz rather than in January.
  readonly property real yearDone: Model.yearProgress(todayJalali.jy, todayJalali.jm, todayJalali.jd)
  readonly property int yearDonePercent: Model.yearProgressPercent(todayJalali.jy, todayJalali.jm, todayJalali.jd)

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A Jalali birth year, because that is the year an
  // Iranian knows their own birth by. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), todayJalali.jy)
  readonly property int age: Model.ageFromBirthYear(birthYear, todayJalali.jy)
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // ---- Persian presentation.

  readonly property bool persianDigits: setting("persianDigits", true)
  readonly property bool rtl: setting("rightToLeft", true)

  // Vazirmatn for text, the bar's own family for icons. They cannot be the
  // same string: the chevrons and the gear are Nerd Font glyphs that no
  // Persian face carries, and the dates are Persian text that a monospace
  // programming face renders in whatever fallback fontconfig picks.
  readonly property string configuredFontFamily: setting("fontFamily", "Vazirmatn")
  readonly property string iconFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string contentFontFamily: configuredFontFamily !== ""
    ? configuredFontFamily
    : iconFontFamily

  function num(value) {
    return root.persianDigits ? Model.toPersianDigits(value) : String(value)
  }

  function percent(value) {
    return num(value) + (root.persianDigits ? "٪" : "%")
  }

  function formatDate(date, pattern) {
    return Model.format(date, pattern, root.persianDigits)
  }

  // Week starts on Saturday, not on whatever Qt's locale says. A Jalali
  // calendar laid out Monday-first because the desktop is in en_US would be
  // wrong in the one way this widget exists to fix. Clicking the grid's
  // week-number heading writes the choice back to shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Model.SATURDAY)
  readonly property string nextWeekStartLabel: Model.weekdayName(Model.toggledWeekStart(weekStart))
  readonly property var weekdays: Model.weekdayOrder(weekStart)

  // Friday is the weekend everywhere in Iran; Thursday is a real
  // disagreement rather than a preference, so it is a setting.
  readonly property bool thursdayWeekend: setting("thursdayWeekend", false)

  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey, eventIndex, {
    thursdayWeekend: thursdayWeekend
  })

  // ---- Events, read from whatever wrote the state file. The panel never
  //      learns where they came from: Google, khal, an ICS feed and a shell
  //      script all look identical from here. It is deliberately the same
  //      file and the same Gregorian date keys the upstream calendar uses, so
  //      one sync feeds both plugins.
  property var eventDoc: null
  property var eventIndex: ({})
  property bool eventVersionMismatch: false

  // Matches the sync timer's interval. Model.syncState allows four of these
  // to elapse before calling the file stale, so one missed run stays quiet.
  readonly property int syncIntervalSeconds: 300

  // Spelled out in full because the people who need it are the ones who
  // installed from the marketplace listing and never opened the README.
  // Resolved from this file's own location, so it is right whether the plugin
  // was installed by `omarchy plugin add` or cloned somewhere by hand.
  readonly property string setupCommand: Model.commandPathFromUrl(
    Qt.resolvedUrl("sync/setup"), Quickshell.env("HOME") || "")
  readonly property string syncState: eventVersionMismatch
    ? "version"
    : Model.syncState(eventDoc, Date.now(), syncIntervalSeconds)

  // The day whose agenda is listed under the grid.
  property string selectedDayKey: todayKey
  readonly property var selectedEvents: Model.eventsForDateKey(eventIndex, selectedDayKey)
  readonly property date selectedDate: Model.dateFromKey(selectedDayKey, today)

  function selectDay(key) {
    root.selectedDayKey = String(key)
  }

  function applyEvents(raw) {
    var doc = null
    var mismatch = false

    if (raw) {
      try {
        var parsed = JSON.parse(raw)
        if (parsed && parsed.version === 1) {
          doc = parsed
        } else if (parsed && parsed.version !== undefined) {
          // Written by a newer sync than this widget understands. Say so
          // rather than render an empty month that reads as a quiet week.
          mismatch = true
        }
      } catch (error) {
        doc = null
      }
    }

    root.eventDoc = doc
    root.eventVersionMismatch = mismatch
    root.rebuildIndex()
  }

  // Flat, already filtered. BarWidget.qml reads this to work out what is
  // coming up next, so the bar label can count down without the popup ever
  // being opened.
  property var visibleEventList: []

  function rebuildIndex() {
    var all = root.eventDoc ? root.eventDoc.events : []
    root.visibleEventList = Model.visibleEvents(all, root.hiddenCalendars, {
      hideWorkingLocation: !root.showWorkingLocation,
      hideDeclined: root.hideDeclined
    })
    root.eventIndex = Model.indexEventsByDate(root.visibleEventList)
  }

  // Ticks every minute regardless of whether the day rolled over, which is
  // what a countdown needs. `today` deliberately only moves at midnight.
  property date nowTick: new Date()
  readonly property var upcomingEvent: Model.nextEventToday(visibleEventList, nowTick.getTime(), todayKey)
  readonly property string upcomingCountdown: Model.formatCountdown(
    Model.millisUntil(upcomingEvent, nowTick.getTime()), root.persianDigits) || ""

  // The year and life bars are the upstream clock's, kept but opt-in. What
  // most people want in that slot is what is coming up next, not how much of
  // the year is gone.
  readonly property bool showYearProgress: setting("showYearProgress", false)

  // Google's working-location markers arrive as all-day events and describe no
  // commitment, so they are out by default. Declined invitations stay in by
  // default: you probably still want to see what you said no to.
  readonly property bool showWorkingLocation: setting("showWorkingLocation", false)
  readonly property bool hideDeclined: setting("hideDeclined", false)

  // Hiding happens here rather than in the sync, so toggling a calendar back
  // on is instant instead of waiting for the next fetch. The sync keeps
  // pulling everything.
  //
  // Held as local state rather than read straight off `settings` on every
  // access. Persisting round-trips through shell.json and comes back
  // asynchronously, so a binding would still be serving the old value when a
  // second click arrives, and the first toggle would be silently undone.
  property var hiddenCalendars: []
  readonly property var knownCalendars: Model.calendarsInDocument(eventDoc)

  function adoptSettings() {
    var stored = setting("hiddenCalendars", [])
    root.hiddenCalendars = Array.isArray(stored) ? stored.slice() : []
  }

  function toggleCalendar(calendarId) {
    root.hiddenCalendars = Model.toggleHiddenCalendar(root.hiddenCalendars, calendarId)
    persistSettings({ hiddenCalendars: root.hiddenCalendars })
  }

  function toggleYearProgress() {
    persistSettings({ showYearProgress: !root.showYearProgress })
  }

  function togglePersianDigits() {
    persistSettings({ persianDigits: !root.persianDigits })
  }

  function toggleRightToLeft() {
    persistSettings({ rightToLeft: !root.rtl })
  }

  function toggleThursdayWeekend() {
    persistSettings({ thursdayWeekend: !root.thursdayWeekend })
  }

  function setAnnounceLeadMinutes(minutes) {
    persistSettings({ announceLeadMinutes: minutes })
  }

  property bool settingsOpen: false

  function toggleWorkingLocation() {
    persistSettings({ showWorkingLocation: !root.showWorkingLocation })
  }

  function toggleHideDeclined() {
    persistSettings({ hideDeclined: !root.hideDeclined })
  }

  // Qt.openUrlExternally rather than the shell helper on purpose. That helper
  // runs `bash -lc`, and a meeting link is supplied by whoever sent the
  // invitation, so putting it through a shell would be a command injection.
  // Model.safeUrl also refuses anything that is not plain https.
  function openExternally(url) {
    if (!url) return
    Qt.openUrlExternally(url)
    root.close()
  }

  function openMeeting(event) {
    root.openExternally(Model.meetingUrlFor(event))
  }

  // Clicking the row opens the event itself. Joining is the button's job, so
  // both actions stay reachable while a meeting is live.
  function openEvent(event) {
    root.openExternally(Model.eventUrlFor(event))
  }

  onHiddenCalendarsChanged: root.rebuildIndex()
  onShowWorkingLocationChanged: root.rebuildIndex()
  onHideDeclinedChanged: root.rebuildIndex()
  onSettingsChanged: root.adoptSettings()
  Component.onCompleted: root.adoptSettings()

  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  // Wider than the upstream clock's: the heading reads "هفته" rather than a
  // single "W", and a two-digit week number set in Persian digits is wider
  // than the same number in Latin ones.
  readonly property int weekColumnWidth: Style.space(40)
  readonly property int gutterWidth: Style.space(14)

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  function goToToday() {
    root.viewYear = root.todayJalali.jy
    root.viewMonth = root.todayJalali.jm
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? root.num(root.birthYear) : ""
      expectancyField.text = root.num(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  // Model.parse* accept Persian digits, which is the point: the fields are
  // typed into with whatever keyboard is on, and refusing ۱۳۵۸ while
  // accepting 1358 would be a trap in a Persian calendar.
  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, root.todayJalali.jy)
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // One letter per column. Seven columns headed "چهارشنبه" would set the
  // width of the whole grid off a single day name.
  function weekdayLabel(weekday) {
    return Model.weekdayShortName(weekday)
  }

  // watchChanges is the point of this whole widget. The sync rewrites the
  // file every few minutes and the popup has to follow it without the shell
  // being restarted. There is deliberately no "already loaded" guard here:
  // one exists upstream in a similar plugin and it is exactly what made an
  // externally written file impossible to pick up.
  FileView {
    id: eventsFile
    path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/calendar-events.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyEvents(text())
    onLoadFailed: root.applyEvents("")
    onFileChanged: reload()
  }

  // Copying beats reading a long path back to yourself. Argv array rather than
  // a shell string, so there is nothing to quote.
  Process {
    id: setupCommandCopier
    command: ["wl-copy", "--", root.setupCommand]
  }

  property bool setupCommandCopied: false

  function copySetupCommand() {
    setupCommandCopier.running = true
    root.setupCommandCopied = true
    copiedReset.restart()
  }

  Timer {
    id: copiedReset
    interval: 2000
    onTriggered: root.setupCommandCopied = false
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      // Always, so the countdown moves even when the day has not.
      root.nowTick = clock.date
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife
      onMoveRequested: function(dx, dy) {
        // Right-to-left means the arrow keys point the other way too:
        // pressing Left on a mirrored grid moves forward, the way it moves
        // your eye forward through the row.
        if (dx !== 0) root.moveMonth(root.rtl ? -dx : dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn

          // The whole panel mirrors from here down. Rows reverse, left and
          // right anchors and their margins swap, and Text with no explicit
          // alignment follows the direction of its own script — which is
          // what puts Persian labels against the correct edge without a
          // single hand-written alignment.
          LayoutMirroring.enabled: root.rtl
          LayoutMirroring.childrenInherit: true

          // Never narrower than the grid. The popup width is capped to what
          // the screen allows, and a fixed seven-column grid would otherwise
          // lose its last days off the edge instead of scrolling.
          width: Math.max(calendarScroll.width, gridColumn.width)
          spacing: Style.space(8)

          // ---- Hero: today, centered. Once the view has stepped back
          //      it is also the way home — clicking the date you are
          //      looking for beats hunting for a reset button.
          Item {
            width: parent.width
            height: heroRow.height

            // Sits in the hero's outer margin rather than in the row itself,
            // so turning it on and off never shifts the date off centre.
            PanelActionButton {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.settingsOpen ? "󰅖" : "󰒓"
              tooltipText: root.settingsOpen ? qsTr("بازگشت به تقویم") : qsTr("تنظیمات")
              foreground: root.contentForeground
              fontFamily: root.iconFontFamily
              onClicked: root.settingsOpen = !root.settingsOpen
            }

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                // Baseline-aligned, not center-aligned: the date carries
                // descenders, so centering the two boxes leaves the icon
                // sitting visibly low against the digits.
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.iconFontFamily
                // Decorative, and deliberately outside the Style.font.*
                // scale. Sized so the glyph reads at the cap height of the
                // date beside it rather than towering over it.
                font.pixelSize: 48
              }

              Text {
                id: heroDate
                anchors.verticalCenter: parent.verticalCenter
                text: root.formatDate(root.today, "d MMMM")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                // A shade smaller than the upstream clock's 52px. Persian
                // month names are words, not three-letter abbreviations, and
                // "اردیبهشت" at 52 pushed the hero wider than the grid.
                font.pixelSize: 44
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: qsTr("بازگشت به امروز")
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Year progress, doubling as the rule under the hero:
          //      a plain hairline said nothing, and whole days done
          //      over days in the Jalali year says the same thing louder.
          Item {
            visible: !root.settingsOpen
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              TapHandler {
                enabled: root.showYearProgress && !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              // ---- What is coming up, in the slot the year bar used to own.
              //      Reads as a sentence rather than a gauge, because the
              //      answer people want here is "what next", not "how far in".
              Row {
                visible: !root.showYearProgress
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.upcomingEvent !== null
                  width: Style.space(4)
                  height: width
                  radius: width / 2
                  color: root.upcomingEvent ? root.upcomingEvent.color : "transparent"
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(110)
                  text: root.upcomingEvent ? root.upcomingEvent.title : qsTr("امروز رویداد دیگری نیست")
                  color: root.upcomingEvent
                    ? root.contentForeground
                    : Qt.darker(root.contentForeground, 1.9)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.upcomingCountdown
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: qsTr("متولد")
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: qsTr("سال")
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  leftPadding: Style.space(6)
                  text: qsTr("تا سن")
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: root.num(90)
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily

                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }

              Text {
                id: yearLabel
                visible: root.showYearProgress && !root.editingLife
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.num(root.todayJalali.jy)
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                id: yearPercent
                visible: root.showYearProgress && !root.editingLife
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.percent(root.yearDonePercent)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                visible: root.showYearProgress && !root.editingLife
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  // Anchored to the track's leading edge rather than left, so
                  // a mirrored year bar fills from the right the way the year
                  // it measures is read.
                  anchors.left: root.rtl ? undefined : parent.left
                  anchors.right: root.rtl ? parent.right : undefined
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ---- Memento mori. Only here once someone has gone looking and
          //      given a birth year; the same rail as the year above it,
          //      measured against a nominal lifetime.
          Item {
            visible: !root.settingsOpen && root.showYearProgress && root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))

              Text {
                id: lifeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("زندگی")
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                id: lifePercent
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.percent(root.lifeDonePercent)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: lifeLabel.right
                anchors.right: lifePercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  anchors.left: root.rtl ? undefined : parent.left
                  anchors.right: root.rtl ? parent.right : undefined
                  width: Math.round(parent.width * root.lifeDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  text: qsTr("یادِ مرگ")
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }

          // ---- Month grid: week numbers down a gutter on the leading edge,
          //      then the seven day columns. Always six rows, so the popup is
          //      exactly as tall in Esfand as it is in Mordad.
          Item {
            visible: !root.settingsOpen
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                // Horizontal wheels and touchpad side-scrolls report y === 0;
                // without this they would every one read as "next month".
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              // The meter above is a solid rule; the grid needs room to
              // read as its own block rather than hanging off it.
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                // The week-number heading doubles as the week-start toggle.
                // It is the one control in the panel whose meaning is not
                // self-evident, so it carries a tooltip naming the day the
                // click will switch to.
                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent)
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: qsTr("هفته")
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: qsTr("شروع هفته از %1").arg(root.nextWeekStartLabel)
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Model.isWeekendDay(modelData, root.thursdayWeekend)
                      ? Qt.darker(root.contentForeground, 1.9)
                      : Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.num(modelData.week)
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      id: dayCell
                      required property var modelData

                      readonly property bool selected: modelData.key === root.selectedDayKey

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius
                      // Today is outlined, not filled: a lit-up block shouts
                      // over a grid this quiet. The selected day gets a faint
                      // wash instead, so the two marks never compete.
                      color: dayCell.selected
                        ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.10)
                        : "transparent"
                      border.width: modelData.today ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

                      Text {
                        id: dayNumber
                        anchors.centerIn: parent
                        // Lifted just enough to clear the dots, and only on
                        // days that have any, so an empty month does not
                        // shift under the cursor.
                        anchors.verticalCenterOffset: modelData.hasEvent ? -Style.space(3) : 0
                        text: root.num(modelData.jd)
                        color: modelData.inMonth
                          ? (modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                          : Qt.darker(root.contentForeground, 2.2)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: modelData.today
                      }

                      Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: dayNumber.bottom
                        anchors.topMargin: Style.space(1)
                        spacing: Style.space(1)
                        visible: dayCell.modelData.hasEvent

                        Repeater {
                          model: dayCell.modelData.dots

                          Rectangle {
                            required property var modelData
                            width: Style.space(3)
                            height: width
                            radius: width / 2
                            color: modelData
                            opacity: dayCell.modelData.inMonth ? 0.9 : 0.4
                          }
                        }
                      }

                      TapHandler {
                        onTapped: root.selectDay(dayCell.modelData.key)
                      }
                    }
                  }
                }
              }
            }

            // Hairline down the week-number gutter, drawn only beside the
            // day rows so it does not cut through the header band.
            //
            // Positioned by hand on both axes, so it is also mirrored by
            // hand: LayoutMirroring reaches anchors and positioners, and an
            // explicit x is neither.
            Rectangle {
              readonly property real gutterOffset: root.weekColumnWidth + root.cellSpacing
                + Math.round((root.gutterWidth - width) / 2)

              x: root.rtl
                ? gridColumn.x + gridColumn.width - gutterOffset - width
                : gridColumn.x + gutterOffset
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // ---- Month stepping, spanning the grid it drives. The chevrons
          //      sit on the grid's outer bounds, the same edges the year
          //      rail above uses, so the row reads as the panel's other
          //      full-width rail instead of a cluster floating in space.
          //      The label is centered and fixed-width, so it holds still
          //      from "دی" to "اردیبهشت".
          Item {
            visible: !root.settingsOpen
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                id: monthLabel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // Fixed width so the chevrons hold still between a
                // "دی ۱۴۰۵" and an "اردیبهشت ۱۴۰۵".
                width: Style.space(160)
                horizontalAlignment: Text.AlignHCenter
                text: Model.monthName(root.viewMonth) + " " + root.num(root.viewYear)
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              PanelActionButton {
                // Pulled out by the button's own padding so the glyph, not
                // its hit box, lines up with the year on the rail above.
                //
                // The anchor mirrors on its own; the glyph does not, so it is
                // swapped here. A chevron that kept pointing left while
                // sitting on the right edge would be telling the truth about
                // nothing.
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: root.rtl ? "󰅂" : "󰅁"
                tooltipText: qsTr("ماه قبل")
                foreground: root.contentForeground
                fontFamily: root.iconFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: root.rtl ? "󰅁" : "󰅂"
                tooltipText: qsTr("ماه بعد")
                foreground: root.contentForeground
                fontFamily: root.iconFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }

          // ---- The selected day's agenda. Headed by its own date, because
          //      the selection survives stepping to another month and an
          //      undated list would then be a quiet lie.
          Column {
            visible: !root.settingsOpen
            width: gridColumn.width
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(4)

            Text {
              width: parent.width
              text: root.formatDate(root.selectedDate, "dddd d MMMM")
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Repeater {
              model: root.selectedEvents

              // The hover wash lives on this wrapper, never inside the Row. A
              // Row lays out every visible child, so an anchored background
              // added as a Row child fights the layout and ejects the content.
              Rectangle {
                id: eventRow
                required property var modelData

                readonly property string meetingUrl: Model.meetingUrlFor(modelData)
                readonly property bool declined: Model.isDeclined(modelData)
                // Only around the actual time. A Join button on next week's
                // meeting is noise that dilutes the one that matters.
                readonly property bool joinable: Model.isJoinableNow(modelData, root.nowTick.getTime(), root.todayKey)
                readonly property string eventUrl: Model.eventUrlFor(modelData)
                readonly property bool openable: eventUrl !== ""

                width: gridColumn.width
                height: eventBody.height + Style.space(2)
                radius: Style.cornerRadius
                color: eventHover.hovered
                  ? Qt.rgba(root.contentForeground.r, root.contentForeground.g,
                            root.contentForeground.b, 0.08)
                  : "transparent"

                // Only rows that can actually do something respond to a click.
                HoverHandler {
                  id: eventHover
                  enabled: eventRow.openable || eventRow.joinable
                  cursorShape: Qt.PointingHandCursor
                }

                Rectangle {
                  id: joinButton
                  visible: eventRow.joinable
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: joinLabel.implicitWidth + Style.space(8)
                  height: joinLabel.implicitHeight + Style.space(3)
                  radius: height / 2
                  color: joinHover.hovered
                    ? Style.selectedStateColor(root.contentForeground, Color.accent)
                    : "transparent"
                  border.width: Style.spacing.hairline
                  border.color: joinHover.hovered
                    ? "transparent"
                    : Qt.darker(root.contentForeground, 2.0)

                  HoverHandler {
                    id: joinHover
                    cursorShape: Qt.PointingHandCursor
                  }

                  // Its own handler, declared on the button, so the grab
                  // happens here and the row's opener does not also fire.
                  TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.openMeeting(eventRow.modelData)
                  }

                  Text {
                    id: joinLabel
                    anchors.centerIn: parent
                    text: qsTr("پیوستن")
                    color: joinHover.hovered ? Color.background : Qt.darker(root.contentForeground, 1.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Row {
                  id: eventBody
                  anchors.left: parent.left
                  anchors.right: eventRow.joinable ? joinButton.left : parent.right
                  anchors.rightMargin: eventRow.joinable ? Style.space(3) : 0
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  // Deliberately here and not on the row: this stops at the
                  // Join button's edge, so the two hit areas cannot overlap.
                  // Two TapHandlers over one point would both fire and open
                  // two tabs.
                  TapHandler {
                    enabled: eventRow.openable
                    onTapped: root.openEvent(eventRow.modelData)
                  }

                  Rectangle {
                    width: Style.space(2)
                    height: eventLines.height
                    radius: width / 2
                    color: eventRow.declined
                      ? Qt.darker(eventRow.modelData.color, 2.2)
                      : eventRow.modelData.color
                  }

                  Text {
                    width: Style.space(52)
                    horizontalAlignment: Text.AlignHCenter
                    text: eventRow.modelData.allDay
                      ? qsTr("تمام‌روز")
                      : root.formatDate(new Date(eventRow.modelData.start), "HH:mm")
                    color: Qt.darker(root.contentForeground, eventRow.declined ? 2.2 : 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.strikeout: eventRow.declined
                  }

                  Column {
                    id: eventLines
                    width: eventBody.width - Style.space(62)
                    spacing: Style.space(1)

                    Text {
                      width: parent.width
                      text: eventRow.modelData.title
                      color: eventRow.declined
                        ? Qt.darker(root.contentForeground, 2.0)
                        : root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.strikeout: eventRow.declined
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      visible: text !== ""
                      text: {
                        if (eventRow.declined) return qsTr("رد شده")
                        if (Model.isOutOfOffice(eventRow.modelData)) return qsTr("خارج از دفتر")
                        return eventRow.modelData.location
                      }
                      color: Qt.darker(root.contentForeground, 1.9)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }
              }
            }

            // An empty day and a sync that never ran look identical unless
            // we say which one it is.
            Text {
              id: emptyState
              width: parent.width
              visible: root.selectedEvents.length === 0
              color: root.syncState === "missing" && emptyHover.hovered
                ? Style.hoverStateColor(root.contentForeground, Color.accent)
                : Qt.darker(root.contentForeground, 1.9)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap

              HoverHandler {
                id: emptyHover
                enabled: root.syncState === "missing"
                cursorShape: Qt.PointingHandCursor
              }

              TapHandler {
                enabled: root.syncState === "missing"
                onTapped: root.copySetupCommand()
              }

              // Every Latin run below goes through Model.ltrIsolate. A shell
              // command reordered by the surrounding Persian is a command
              // that cannot be pasted, which is the whole point of printing
              // it here.
              text: root.syncState === "missing"
                ? (root.setupCommandCopied
                  ? qsTr("کپی شد. در ترمینال اجرا کنید:\n%1").arg(Model.ltrIsolate(root.setupCommand))
                  : qsTr("هنوز تقویمی همگام‌سازی نشده. برای کپی کلیک کنید، سپس اجرا کنید:\n%1").arg(Model.ltrIsolate(root.setupCommand)))
                : root.syncState === "version"
                  ? qsTr("فایل رویدادها را نسخهٔ جدیدتری نوشته است. افزونه را به‌روز کنید.")
                  : root.syncState === "stale"
                    ? qsTr("ممکن است تقویم به‌روز نباشد. بررسی کنید:\n%1").arg(Model.ltrIsolate("journalctl --user -u omarchy-calendar-sync"))
                    : qsTr("رویدادی ثبت نشده")
            }
          }

          // ---- Settings, shown in place of the grid. Everything it changes
          //      is owned by this panel and persisted to shell.json here, so
          //      the view stays a pure read-and-emit surface.
          SettingsView {
            visible: root.settingsOpen
            width: gridColumn.width
            anchors.horizontalCenter: parent.horizontalCenter

            foreground: root.contentForeground
            fontFamily: root.contentFontFamily

            calendars: root.knownCalendars
            hiddenCalendars: root.hiddenCalendars
            showYearProgress: root.showYearProgress
            showWorkingLocation: root.showWorkingLocation
            hideDeclined: root.hideDeclined
            weekStartsSaturday: root.weekStart === Model.SATURDAY
            thursdayWeekend: root.thursdayWeekend
            persianDigits: root.persianDigits
            rightToLeft: root.rtl
            announceLeadMinutes: root.setting("announceLeadMinutes", 15)

            syncState: root.syncState
            setupCommand: root.setupCommand
            setupCommandCopied: root.setupCommandCopied
            onSetupCommandCopyRequested: root.copySetupCommand()
            eventCount: root.eventDoc && root.eventDoc.events ? root.eventDoc.events.length : 0
            sourceLabel: root.eventDoc ? String(root.eventDoc.source || "") : ""
            syncedAt: root.eventDoc && root.eventDoc.syncedAt
              ? root.formatDate(new Date(root.eventDoc.syncedAt), "d MMMM 'ساعت' HH:mm")
              : ""

            onCalendarToggled: function(calendarId) { root.toggleCalendar(calendarId) }
            onYearProgressToggled: root.toggleYearProgress()
            onWorkingLocationToggled: root.toggleWorkingLocation()
            onHideDeclinedToggled: root.toggleHideDeclined()
            onWeekStartToggled: root.toggleWeekStart()
            onThursdayWeekendToggled: root.toggleThursdayWeekend()
            onPersianDigitsToggled: root.togglePersianDigits()
            onRightToLeftToggled: root.toggleRightToLeft()
            onLeadMinutesPicked: function(minutes) { root.setAnnounceLeadMinutes(minutes) }
          }
        }
      }
    }
  }
}
