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

  // ---- Which calendar. Everything below reads through Model's dispatch
  //      layer rather than branching on this, so the panel never has two
  //      versions of the same logic.
  //
  //      Switching is what lets this widget stand in for Omarchy's built-in
  //      clock outright, instead of sitting next to it: turn it to Gregorian
  //      and it is that clock, week numbers, format ring and all.
  readonly property string calendar: Model.normalizeCalendar(setting("calendar", Model.JALALI))
  readonly property bool jalali: Model.isJalali(calendar)

  function t(key) {
    return Model.text(root.calendar, key)
  }

  // In Gregorian mode the month and day names come from Qt's own locale, so a
  // desktop running in French keeps reading French exactly as the built-in
  // clock did. Model.js stays locale-free and testable; the locale stays
  // where the locale lives. Jalali has one set of names and no locale to ask.
  readonly property var localeNames: root.jalali ? null : ({
    months: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map(function(m) {
      return Qt.locale().standaloneMonthName(m - 1, Locale.LongFormat)
    }),
    monthsShort: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map(function(m) {
      return Qt.locale().standaloneMonthName(m - 1, Locale.ShortFormat)
    }),
    weekdays: [0, 1, 2, 3, 4, 5, 6].map(function(d) {
      return Qt.locale().standaloneDayName(d, Locale.LongFormat)
    }),
    weekdaysShort: [0, 1, 2, 3, 4, 5, 6].map(function(d) {
      return String(Qt.locale().standaloneDayName(d, Locale.ShortFormat))
        .replace(/\.$/, "").toUpperCase()
    })
  })

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)
  readonly property var todayCivil: Model.fromDate(calendar, today)

  // The month on screen, in the calendar on screen. Stepping moves this and
  // nothing else: the grid is a read-out, not a picker, so there is no
  // per-day cursor to keep in sync.
  property int viewYear: todayCivil.year
  property int viewMonth: todayCivil.month

  readonly property bool viewingCurrentMonth: viewYear === todayCivil.year && viewMonth === todayCivil.month

  // Switching calendars renames the month underfoot, so the view has to be
  // re-derived rather than left holding a number that means something else
  // now. Following today is the only sane landing place: 1405/6 and 2026/6
  // are not the same month, and there is no honest way to carry the old view
  // across.
  onCalendarChanged: root.goToToday()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone. Measured on the
  // year of the active calendar, so under Jalali the bar empties at Nowruz
  // rather than in January.
  readonly property real yearDone: Model.yearProgress(calendar, todayCivil.year, todayCivil.month, todayCivil.day)
  readonly property int yearDonePercent: Model.yearProgressPercent(calendar, todayCivil.year, todayCivil.month, todayCivil.day)

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. Without one the bar stays hidden.
  //
  // Read and written in the calendar on screen -- an Iranian knows their birth
  // year as 1358, not 1979 -- but stored as Gregorian, so flipping the
  // calendar does not silently invalidate a year already entered.
  readonly property int birthYear: Model.parseBirthYear(
    Model.birthYearInCalendar(setting("birthYear", 0), calendar), todayCivil.year)
  readonly property int age: Model.ageFromBirthYear(birthYear, todayCivil.year)
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // ---- Presentation.
  //
  // Unset follows the calendar, so switching moves everything that ought to
  // move. An explicit choice always wins and survives the switch, because a
  // deliberate setting is not something a display toggle gets to undo.

  readonly property bool persianDigits: Model.resolveBoolean(
    setting("persianDigits", null), Model.usesPersianDigitsByDefault(calendar))
  readonly property bool rtl: Model.resolveBoolean(
    setting("rightToLeft", null), Model.isRightToLeftByDefault(calendar))

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
    return Model.format(date, pattern, {
      calendar: root.calendar,
      persianDigits: root.persianDigits,
      names: root.localeNames
    })
  }

  // Saturday under Jalali, Monday under Gregorian, and never whatever Qt's
  // locale says: a Jalali calendar laid out Monday-first because the desktop
  // is in en_US would be wrong in the one way this widget exists to fix.
  // Clicking the grid's week-number heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(
    setting("weekStartDay", null), Model.defaultWeekStart(calendar))
  readonly property string nextWeekStartLabel: Model.weekdayName(
    calendar, Model.toggledWeekStart(weekStart, calendar), localeNames)
  readonly property var weekdays: Model.weekdayOrder(weekStart, calendar)

  // Friday is the weekend everywhere in Iran; Thursday is a real
  // disagreement rather than a preference, so it is a setting. It means
  // nothing under Gregorian, where the weekend is Saturday and Sunday.
  readonly property bool thursdayWeekend: setting("thursdayWeekend", false)

  readonly property var weeks: Model.monthGrid(calendar, viewYear, viewMonth, weekStart, todayKey, eventIndex, {
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
  //
  // This is the Google command now: CalDAV is connected from the settings
  // page itself, and Google is the one that cannot be, because it needs a
  // browser login and four steps in a cloud console.
  readonly property string setupCommand: Model.commandPathFromUrl(
    Qt.resolvedUrl("sync/setup-google"), Quickshell.env("HOME") || "")

  // The same script, as a path a process can actually run: no "~", because
  // nothing expands it once QML hands the argv straight to exec.
  readonly property string connectBin: Model.commandPathFromUrl(
    Qt.resolvedUrl("sync/omarchy-calendar-connect"), "")

  // ---- The sync's own config file, read so the settings page can show what
  //      is connected and prefill the form with it. Written only through the
  //      connect helper: this panel has no business hand-editing a file the
  //      sync validates on every run.
  property var syncConfig: null
  readonly property var caldavSettings: Model.caldavSettings(syncConfig)
  readonly property string configuredSource: Model.normalizeSource(
    syncConfig ? syncConfig.source : "")

  // Which provider the settings form is showing. Seeded from the file and
  // then owned by the user's clicks, so opening the Google tab to read the
  // command does not claim the account has moved to Google.
  property string accountProvider: ""
  readonly property string activeProvider: accountProvider !== ""
    ? accountProvider
    : Model.preferredProvider(syncConfig)

  property string connectState: "idle"
  property string connectMessage: ""
  property bool connectOk: false
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
    Model.millisUntil(upcomingEvent, nowTick.getTime()),
    { calendar: root.calendar, persianDigits: root.persianDigits }) || ""

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

  // Named for what it hides, not for what it is called in the settings page.
  // `toggleCalendar` now means switching Jalali for Gregorian, and two
  // functions a letter apart doing unrelated things is a bug waiting to be
  // written.
  function toggleCalendarVisibility(calendarId) {
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

  // Only the calendar is written. Week start, digits and direction are left
  // unset so they follow it, unless someone has already set one on purpose --
  // in which case that choice survives the switch, which is the point of
  // storing it.
  function setCalendar(value) {
    var next = Model.normalizeCalendar(value)
    if (next === root.calendar) return
    persistSettings({ calendar: next })
  }

  function toggleCalendar() {
    root.setCalendar(Model.otherCalendar(root.calendar))
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
    // Hiding comes first, and everything after it is tidy-up. The panel is a
    // full-screen overlay layer that holds the keyboard: if anything below
    // throws before the hide lands, the desktop is left with a popup it
    // cannot dismiss and a compositor that routes every key into it. That is
    // not a hypothetical -- it is what a readonly `centerHoverRevealSuppressed`
    // on the plugin bar facade did here.
    root.controller.hide()
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  // Straight to the settings page. Connecting an account is the one thing
  // somebody arrives wanting to do and cannot find: it is three clicks into a
  // popup they have never opened.
  function openSettings() {
    root.settingsOpen = true
    root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  // Through the setter, never by assignment: a plugin is handed PluginBarApi
  // rather than the Bar itself, and the flag is readonly there. Assigning it
  // throws, and a throw on the way out of close() is how this panel became
  // impossible to dismiss. Both the facade and the Bar expose the method.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
  }

  // Guarded because the settings view is inside the panel's own Flickable and
  // is not built until the panel is, and `editingAccount` is read by the key
  // catcher from the first key press onwards.
  readonly property bool editingAccount: root.settingsOpen
    && typeof settingsView !== "undefined" && settingsView && settingsView.editing === true

  function returnKeyboardToPanel() {
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  function goToToday() {
    root.viewYear = root.todayCivil.year
    root.viewMonth = root.todayCivil.month
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
    var born = Model.parseBirthYear(bornField.text, root.todayCivil.year)
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy) {
      persistSettings({
        birthYear: Model.birthYearToStorage(born, root.calendar),
        lifeExpectancy: span
      })
    }
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart, root.calendar))
  }

  // One letter per column under Jalali, three under Gregorian. Seven columns
  // headed "چهارشنبه" would set the width of the whole grid off a single day
  // name.
  function weekdayLabel(weekday) {
    return Model.weekdayShortName(root.calendar, weekday, root.localeNames)
  }

  // ---- The bundled face.
  //
  // Vazirmatn ships with the plugin rather than being a prerequisite. The
  // README used to say `yay -S ttf-vazirmatn`, which installs nothing --
  // the AUR package is `vazirmatn-fonts` -- and even the right command is a
  // step between someone and a working widget for a font the widget cannot
  // do without. FontLoader registers the family for the whole shell process,
  // so `font.family: "Vazirmatn"` resolves to this copy whether or not one
  // is installed system-wide.
  //
  // Regular and Bold, because the panel sets font.bold and a synthesised
  // bold of a Persian face is a smear. Under OFL 1.1; see fonts/OFL.txt.
  FontLoader { id: vazirRegular; source: Qt.resolvedUrl("fonts/Vazirmatn-Regular.ttf") }
  FontLoader { id: vazirBold; source: Qt.resolvedUrl("fonts/Vazirmatn-Bold.ttf") }

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

  // The sync's config, watched for the same reason the events file is: the
  // connect helper rewrites it, and the form above it has to agree with what
  // was written without the shell being restarted.
  FileView {
    id: syncConfigFile
    path: (Quickshell.env("HOME") || "") + "/.config/omarchy/calendar-sync.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.syncConfig = Model.parseConfigDocument(text())
    onLoadFailed: root.syncConfig = null
    onFileChanged: reload()
  }

  // Is there a password already stored? Inferred from the config rather than
  // read off disk: an account that is connected was connected with a
  // password, and the panel has no business holding a mail password in a
  // property for the life of the popup to learn something it can deduce.
  //
  // It decides one thing -- whether a blank password field means "keep the
  // current one" or "you left a field out". If the file has been deleted
  // behind our back the helper says so, which is the right place for it.
  readonly property bool hasStoredPassword: root.configuredSource === Model.SOURCE_CALDAV
    && root.caldavSettings.url !== ""

  // ---- Connecting. One JSON object down the pipe, one JSON object back.
  //
  // The password goes over stdin and never becomes an argument: argv is
  // world-readable through ps, and this is a mail password typed into a
  // status bar popup while the user watches.
  Process {
    id: connectProc

    property string request: ""

    command: [root.connectBin]
    stdinEnabled: true

    onStarted: {
      write(request + "\n")
      // Held only as long as it takes to hand over. Nothing downstream reads
      // it back, and it must not sit in a QML property for the life of the
      // panel.
      request = ""
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyConnectReply(text, 0)
    }

    onExited: function(exitCode, exitStatus) {
      // A helper that never ran writes nothing at all, so the collector above
      // has nothing to report and this is the only place the failure shows.
      if (root.connectState === "running") root.applyConnectReply("", exitCode)
    }
  }

  function connectCalDav(url, username, password, verifyTls) {
    if (root.connectState === "running") return

    var request = Model.connectRequest({
      url: url, username: username, password: password, verifyTls: verifyTls
    })

    // Asked and answered here rather than at the far end of a process: a
    // missing username is not worth spawning python to be told about.
    var problem = Model.connectRequestProblem(request, root.hasStoredPassword)
    if (problem !== "") {
      root.connectState = "done"
      root.connectOk = false
      root.connectMessage = root.t(problem)
      console.log("jalali-calendar: connect refused before running,", problem)
      return
    }

    root.connectState = "running"
    root.connectOk = false
    root.connectMessage = root.t("connectingNow")

    // A line in the journal for every attempt: the URL and the username, and
    // never the password. Whether the button did anything at all is the first
    // question asked when this goes wrong, and it should not need a debug
    // build to answer.
    console.log("jalali-calendar: connecting to", request.url, "as", request.username,
      "verifyTls", request.verifyTls, "via", root.connectBin)

    connectProc.request = JSON.stringify(request)
    connectProc.running = true
  }

  function applyConnectReply(raw, exitCode) {
    var outcome = Model.connectOutcome(raw, exitCode)
    console.log("jalali-calendar: connect finished ok =", outcome.ok,
      "as", outcome.key, "exit", exitCode)
    root.connectState = "done"
    root.connectOk = outcome.ok === true
    root.connectMessage = outcome.value === ""
      ? root.t(outcome.key)
      : root.t(outcome.key).arg(outcome.value)

    // The helper rewrote the config and the events file; both are watched, so
    // nothing here has to reload them by hand.
  }

  // Between the timer's five-minute ticks. Not the connect path: this asks
  // systemd to run the unit that is already installed, so it needs no
  // credentials and nothing on stdin.
  Process {
    id: syncNowProc
    command: ["systemctl", "--user", "start", "omarchy-calendar-sync.service"]
  }

  function syncNow() {
    syncNowProc.running = true
    root.connectState = "done"
    root.connectOk = true
    root.connectMessage = root.t("syncStarted")
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
      // This handler takes keys before its children do, which is what makes
      // "t" jump to today. It has to stand down whenever a text field has the
      // focus, or a server name cannot be typed: every letter in it would be
      // read as a calendar shortcut instead.
      blocked: root.editingLife || root.editingAccount
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

            // Both of the hero's controls sit in its outer margins rather
            // than in the row itself, so showing or hiding either never
            // shifts the date off centre.
            PanelActionButton {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.settingsOpen ? "󰅖" : "󰒓"
              tooltipText: root.settingsOpen ? root.t("backToCalendar") : root.t("settings")
              foreground: root.contentForeground
              fontFamily: root.iconFontFamily
              onClicked: root.settingsOpen = !root.settingsOpen
            }

            // The calendar switch, on the margin opposite the gear. The
            // settings page carries the same control, but which calendar you
            // are reading is something you change while reading it, not a
            // preference you go and set -- and a switch two clicks deep is a
            // switch nobody uses twice.
            //
            // It names the calendar it would switch *to*, in the language
            // currently on screen: a page written in Persian offers you
            // "English", not "انگلیسی". The tooltip says what the click does,
            // so the label cannot be misread as a statement of where you are.
            Rectangle {
              id: calendarSwitch

              readonly property string targetLabel: root.t(
                root.jalali ? "gregorianOption" : "jalaliOption")

              // Hidden behind the settings page, which has its own picker.
              // Two controls for one setting, both on screen, invites the
              // question of whether they are the same setting.
              visible: !root.settingsOpen
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: calendarSwitchLabel.implicitWidth + Style.space(14)
              height: calendarSwitchLabel.implicitHeight + Style.space(6)
              radius: height / 2
              color: calendarSwitchHover.hovered
                ? Style.hoverFillFor(root.contentForeground, Color.accent)
                : "transparent"
              border.width: Style.spacing.hairline
              border.color: calendarSwitchHover.hovered
                ? "transparent"
                : Qt.darker(root.contentForeground, 2.4)

              HoverHandler {
                id: calendarSwitchHover
                cursorShape: Qt.PointingHandCursor
              }

              TapHandler {
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: root.toggleCalendar()
              }

              Text {
                id: calendarSwitchLabel
                anchors.centerIn: parent
                text: calendarSwitch.targetLabel
                color: calendarSwitchHover.hovered
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : Qt.darker(root.contentForeground, 1.6)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              PanelToolTip {
                visible: calendarSwitchHover.hovered
                text: root.t("switchTo").arg(calendarSwitch.targetLabel)
                fontFamily: root.contentFontFamily
              }
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
                text: root.t("backToToday")
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
                  text: root.upcomingEvent ? root.upcomingEvent.title : root.t("nothingElseToday")
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
                  text: root.t("born")
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: root.t("yearPlaceholder")
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  leftPadding: Style.space(6)
                  text: root.t("liveTo")
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
                text: root.num(root.todayCivil.year)
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
                text: root.t("life")
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
                  text: root.t("mementoMori")
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
                    text: root.t("weekHeader")
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
                    text: root.t("weekStartTooltip").arg(root.nextWeekStartLabel)
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
                    color: Model.isWeekendDay(root.calendar, modelData, { thursdayWeekend: root.thursdayWeekend })
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
                        text: root.num(modelData.civilDay)
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
                text: Model.monthName(root.calendar, root.viewMonth, root.localeNames) + " " + root.num(root.viewYear)
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
                tooltipText: root.t("previousMonth")
                foreground: root.contentForeground
                fontFamily: root.iconFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: root.rtl ? "󰅁" : "󰅂"
                tooltipText: root.t("nextMonth")
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
                    text: root.t("join")
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
                      ? root.t("allDay")
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
                        if (eventRow.declined) return root.t("declined")
                        if (Model.isOutOfOffice(eventRow.modelData)) return root.t("outOfOffice")
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
            //
            // The message and the shell command it names are two Text items,
            // not two lines of one. A Text takes its base direction from its
            // own content, and one holding a Persian sentence is a
            // right-to-left paragraph all the way down -- which drags the
            // weak "~/" off the front of the path and prints it at the far
            // end, as "config/.../setup./~". Giving the command its own
            // Latin-only item gives it its own left-to-right paragraph, and
            // the command a new user is told to paste is one they can paste.
            Column {
              id: emptyState
              width: parent.width
              visible: root.selectedEvents.length === 0
              spacing: Style.space(1)

              readonly property bool actionable: root.syncState === "missing"

              readonly property string message: {
                if (root.syncState === "missing")
                  return root.t("noSyncRun")
                if (root.syncState === "version")
                  return root.t("versionNewer")
                if (root.syncState === "stale")
                  return root.t("staleCheck")
                return root.t("nothingScheduled")
              }

              readonly property string command: {
                if (root.syncState === "stale") return "journalctl --user -u omarchy-calendar-sync"
                return ""
              }

              readonly property color shade: emptyState.actionable && emptyHover.hovered
                ? Style.hoverStateColor(root.contentForeground, Color.accent)
                : Qt.darker(root.contentForeground, 1.9)

              HoverHandler {
                id: emptyHover
                enabled: emptyState.actionable
                cursorShape: Qt.PointingHandCursor
              }

              // Opens the page that connects one, rather than copying a
              // command for someone to paste into a terminal they may not
              // have open. The form is three fields and a button now.
              TapHandler {
                enabled: emptyState.actionable
                onTapped: root.settingsOpen = true
              }

              Text {
                width: parent.width
                text: emptyState.message
                color: emptyState.shade
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Text {
                // Mirroring is switched off here and nowhere else: this is
                // the one run of text in the panel that is not Persian, and
                // it has to lay out as what it is.
                LayoutMirroring.enabled: false
                width: parent.width
                visible: text !== ""
                text: emptyState.command
                color: emptyState.shade
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WrapAnywhere
              }
            }
          }

          // ---- Settings, shown in place of the grid. Everything it changes
          //      is owned by this panel and persisted to shell.json here, so
          //      the view stays a pure read-and-emit surface.
          SettingsView {
            id: settingsView
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
            calendar: root.calendar
            weekStartsOnDefault: root.weekStart === Model.defaultWeekStart(root.calendar)
            thursdayWeekend: root.thursdayWeekend
            persianDigits: root.persianDigits
            rightToLeft: root.rtl
            announceLeadMinutes: root.setting("announceLeadMinutes", 15)

            syncState: root.syncState
            setupCommand: root.setupCommand
            setupCommandCopied: root.setupCommandCopied
            onSetupCommandCopyRequested: root.copySetupCommand()

            accountSource: root.activeProvider
            caldavUrl: root.caldavSettings.url
            caldavUsername: root.caldavSettings.username
            caldavVerifyTls: root.caldavSettings.verifyTls
            hasStoredPassword: root.hasStoredPassword
            connectState: root.connectState
            connectMessage: root.connectMessage
            connectOk: root.connectOk

            onProviderPicked: function(provider) { root.accountProvider = provider }
            onConnectRequested: function(url, username, password, verifyTls) {
              root.connectCalDav(url, username, password, verifyTls)
            }
            onSyncNowRequested: root.syncNow()
            onEditingCancelled: root.returnKeyboardToPanel()
            eventCount: root.eventDoc && root.eventDoc.events ? root.eventDoc.events.length : 0
            sourceLabel: root.eventDoc ? String(root.eventDoc.source || "") : ""
            syncedAt: root.eventDoc && root.eventDoc.syncedAt
              ? root.formatDate(new Date(root.eventDoc.syncedAt), "d MMMM '" + root.t("atTime") + "' HH:mm")
              : ""

            onCalendarToggled: function(calendarId) { root.toggleCalendarVisibility(calendarId) }
            onCalendarSystemPicked: function(system) { root.setCalendar(system) }
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
