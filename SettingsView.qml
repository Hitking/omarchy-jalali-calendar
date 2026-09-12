import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The calendar's settings page, shown in place of the month grid.
//
// Kept in its own file rather than folded into Panel.qml: the panel is
// already long, and everything here is presentation over values the panel
// owns. This component reads state and emits intent, it never writes
// shell.json itself.
//
// It inherits the panel's LayoutMirroring, so every row here reads
// right-to-left without a single anchor being written twice.
Column {
  id: root

  property color foreground: "white"
  property string fontFamily: ""
  property bool persianDigits: true

  // Which calendar is on, which also picks the language of every label on
  // this page. A Persian "Settings" on a widget standing in for Omarchy's
  // English clock would be the wrong answer, so the two move together.
  property string calendar: Model.JALALI
  readonly property bool jalali: Model.isJalali(calendar)

  function t(key) {
    return Model.text(root.calendar, key)
  }

  property var calendars: []
  property var hiddenCalendars: []
  property bool showYearProgress: false
  property bool weekStartsOnDefault: true
  property bool thursdayWeekend: false
  property bool rightToLeft: true
  property bool showWorkingLocation: false
  property bool hideDeclined: false
  property int announceLeadMinutes: 15

  property string syncedAt: ""
  property string sourceLabel: ""
  property int eventCount: 0
  property string syncState: "missing"
  property string setupCommand: ""
  property bool setupCommandCopied: false

  // ---- The calendar account. Read from calendar-sync.json by the panel and
  //      written back through the connect helper, so this page never touches
  //      the config file itself.
  property string accountSource: Model.SOURCE_GOOGLE
  property string caldavUrl: ""
  property string caldavUsername: ""
  property bool caldavVerifyTls: true
  property bool hasStoredPassword: false

  // "idle" before anything is tried, "running" while the helper is out,
  // "done" once it has answered. The message is already translated.
  property string connectState: "idle"
  property string connectMessage: ""
  property bool connectOk: false

  // Which provider the form is showing. Seeded from what is configured,
  // because the first thing to see is what you already have.
  property string provider: Model.normalizeSource(accountSource)
  onAccountSourceChanged: root.provider = Model.normalizeSource(accountSource)

  readonly property bool caldavConnected: Model.normalizeSource(accountSource) === Model.SOURCE_CALDAV
    && caldavUrl !== ""

  // Open by default, and only ever closed by a click or by the one-time seed
  // below. It used to be bound to `!caldavConnected`, which meant a connect
  // that succeeded pulled the form shut underneath the person who had just
  // pressed the button -- taking the "it worked" message down with it, so the
  // only feedback for a successful connect was the form vanishing.
  property bool accountOpen: true
  property bool accountSeeded: false

  // An account that was already connected when this page opened is a line of
  // status, not a wall of inputs, so fold it away -- once. `connectState`
  // tells the two apart: "idle" means this page has not done anything yet,
  // so whatever is connected was connected before we got here.
  onCaldavConnectedChanged: {
    if (!root.accountSeeded && root.caldavConnected && root.connectState === "idle")
      root.accountOpen = false
    root.accountSeeded = true
  }

  // The toggle's own state while the form is being filled in, so turning it
  // off and changing your mind does not need a round trip through the config
  // file. Re-seeded whenever the file says something new.
  property bool verifyTlsDraft: caldavVerifyTls
  onCaldavVerifyTlsChanged: root.verifyTlsDraft = caldavVerifyTls

  // Somebody is typing in this page, so the panel's key catcher must not
  // read their keystrokes as calendar shortcuts.
  readonly property bool editing: accountForm.editing

  // Prefilled from the config file, but never over what is being typed: the
  // sync rewrites that file every five minutes, and a form that reverted
  // mid-sentence would be unusable.
  onCaldavUrlChanged: if (!urlField.input.activeFocus) urlField.text = root.caldavUrl
  onCaldavUsernameChanged: if (!usernameField.input.activeFocus) usernameField.text = root.caldavUsername

  Component.onCompleted: {
    urlField.text = root.caldavUrl
    usernameField.text = root.caldavUsername
  }

  // A password that worked is one the helper has stored; keeping it on screen
  // afterwards would be a password sitting in a popup for no reason.
  onConnectOkChanged: if (connectOk) passwordField.text = ""

  function submitConnect() {
    if (root.connectState === "running") return
    root.connectRequested(urlField.text, usernameField.text,
      passwordField.text, root.verifyTlsDraft)
  }

  // Enter connects from any field, Tab walks to the next one, Escape hands
  // the keyboard back to the panel. Written out rather than left to Qt's
  // focus chain because the panel's key catcher takes keys before its
  // children and there is no chain to fall back on.
  function fieldKey(event, next) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.submitConnect()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab) {
      next.input.selectAll()
      next.input.forceActiveFocus()
      event.accepted = true
    } else if (event.key === Qt.Key_Escape) {
      root.editingCancelled()
      event.accepted = true
    }
  }

  signal calendarToggled(string calendarId)
  signal calendarSystemPicked(string system)
  signal yearProgressToggled()
  signal weekStartToggled()
  signal thursdayWeekendToggled()
  signal persianDigitsToggled()
  signal rightToLeftToggled()
  signal workingLocationToggled()
  signal hideDeclinedToggled()
  signal leadMinutesPicked(int minutes)
  signal setupCommandCopyRequested()
  signal providerPicked(string provider)
  signal connectRequested(string url, string username, string password, bool verifyTls)
  signal syncNowRequested()
  signal editingCancelled()

  readonly property color muted: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 1.9)

  function num(value) {
    return root.persianDigits ? Model.toPersianDigits(value) : String(value)
  }

  spacing: Style.space(10)

  component SectionTitle: Text {
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  // A row that reads as a switch without pulling in a control library the
  // rest of this plugin does not use.
  component ToggleRow: Rectangle {
    id: toggle

    property string label: ""
    property string hint: ""
    property bool checked: false
    property color swatch: "transparent"

    signal activated()

    width: parent ? parent.width : 0
    height: toggleBody.height + Style.space(6)
    radius: Style.cornerRadius
    color: hovered.hovered
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
      : "transparent"

    HoverHandler { id: hovered }
    TapHandler { onTapped: toggle.activated() }

    Row {
      id: toggleBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(3)
      anchors.rightMargin: Style.space(3)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(14)
        text: toggle.checked ? "✓" : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: toggle.swatch != "transparent"
        width: Style.space(4)
        height: width
        radius: width / 2
        color: toggle.checked ? toggle.swatch : "transparent"
        border.width: Style.spacing.hairline
        border.color: toggle.swatch
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: toggleBody.width - Style.space(26)
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: toggle.label
          color: toggle.checked ? root.foreground : root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: toggle.hint !== ""
          text: toggle.hint
          color: root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  // A pill: a tab when it sits in a row of them, a button when it stands
  // alone. The same shape both times, because both times it is one word you
  // click.
  component Pill: Rectangle {
    id: pill

    property string label: ""
    property bool active: false
    property bool actionable: true

    signal activated()

    width: pillLabel.width + Style.space(12)
    height: pillLabel.height + Style.space(5)
    radius: height / 2
    opacity: actionable ? 1 : 0.45
    color: active
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
      : (pillHover.hovered
        ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
        : "transparent")
    border.width: Style.spacing.hairline
    border.color: active ? root.muted : Qt.darker(root.foreground, 2.4)

    HoverHandler {
      id: pillHover
      enabled: pill.actionable
      cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
      enabled: pill.actionable
      onTapped: pill.activated()
    }

    Text {
      id: pillLabel
      anchors.centerIn: parent
      text: pill.label
      color: pill.active ? root.foreground : root.faint
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // A labelled input. The field itself opts out of the mirroring the rest of
  // this page inherits: a URL and a username are Latin text, and typing one
  // into a right-to-left field puts the caret and the "https://" at the wrong
  // end of what you are reading.
  component Field: Column {
    id: field

    property alias input: entry
    property alias text: entry.text
    property string label: ""
    property string hint: ""
    property string placeholder: ""
    property bool secret: false

    // Raised from the field's own Keys handler rather than letting a caller
    // attach one through the `input` alias: an attached property reached
    // down an alias is not something QML promises to honour, and a key
    // handler that silently never fires is the kind of thing that only shows
    // up when somebody presses Enter and nothing happens.
    signal keyPressed(var event)

    width: parent ? parent.width : 0
    spacing: Style.space(1)

    Text {
      text: field.label
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    TextField {
      id: entry
      LayoutMirroring.enabled: false
      width: field.width
      password: field.secret
      placeholderText: field.placeholder
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall

      Keys.onPressed: function(event) { field.keyPressed(event) }
    }

    Text {
      width: field.width
      visible: field.hint !== ""
      text: field.hint
      color: root.faint
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  // ---- The calendar account. First on the page: there is nothing to choose
  //      in any section below until something is connected.

  SectionTitle { text: root.t("accountTitle") }

  // Collapsed to one line once it works. Opening it again is how you change
  // the password or move to another server.
  Row {
    width: parent.width
    spacing: Style.space(4)

    HoverHandler {
      enabled: root.caldavConnected
      cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
      enabled: root.caldavConnected
      onTapped: root.accountOpen = !root.accountOpen
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(14)
      visible: root.caldavConnected
      text: root.accountOpen ? "▾" : "▸"
      color: root.faint
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    // What is connected, right now, in one line that no collapse can hide.
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(20)
      text: root.caldavConnected
        ? root.t("connectedAs").arg(root.caldavUsername || root.caldavUrl)
        : (root.connectState === "idle" ? root.t("accountHint") : root.t("notConnectedYet"))
      color: root.caldavConnected ? root.foreground : root.faint
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  Column {
    id: accountForm
    width: parent.width
    visible: root.accountOpen
    spacing: Style.space(6)

    // Is anything in this form focused? The panel's key catcher takes keys
    // before its children do -- which is what makes "t" jump to today and the
    // arrows step the month -- so it has to stand down while someone is
    // typing a server name into it.
    readonly property bool editing: urlField.input.activeFocus
      || usernameField.input.activeFocus
      || passwordField.input.activeFocus

    Row {
      spacing: Style.space(3)

      Pill {
        label: root.t("caldavOption")
        active: root.provider === Model.SOURCE_CALDAV
        onActivated: root.providerPicked(Model.SOURCE_CALDAV)
      }

      Pill {
        label: root.t("googleOption")
        active: root.provider === Model.SOURCE_GOOGLE
        onActivated: root.providerPicked(Model.SOURCE_GOOGLE)
      }
    }

    // ---- CalDAV: three fields and a button, which is the whole of it.

    Column {
      width: parent.width
      visible: root.provider === Model.SOURCE_CALDAV
      spacing: Style.space(6)

      Text {
        width: parent.width
        text: root.t("caldavHint")
        color: root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Field {
        id: urlField
        label: root.t("serverLabel")
        hint: root.t("serverHint")
        placeholder: "https://mail.example.com/"
        onKeyPressed: function(event) { root.fieldKey(event, usernameField) }
      }

      Field {
        id: usernameField
        label: root.t("usernameLabel")
        hint: root.t("usernameHint")
        placeholder: "you@example.com"
        onKeyPressed: function(event) { root.fieldKey(event, passwordField) }
      }

      Field {
        id: passwordField
        label: root.t("passwordLabel")
        hint: root.hasStoredPassword ? root.t("passwordHint") : root.t("passwordTwoFactor")
        secret: true
        onKeyPressed: function(event) { root.fieldKey(event, urlField) }
      }

      ToggleRow {
        label: root.t("verifyTlsLabel")
        hint: root.t("verifyTlsHint")
        checked: root.verifyTlsDraft
        onActivated: root.verifyTlsDraft = !root.verifyTlsDraft
      }

      Row {
        spacing: Style.space(3)

        Pill {
          label: root.connectState === "running"
            ? root.t("connectingNow")
            : (root.caldavConnected ? root.t("reconnectAction") : root.t("connectAction"))
          active: true
          actionable: root.connectState !== "running"
          onActivated: root.submitConnect()
        }

        Pill {
          label: root.t("syncNowAction")
          actionable: root.caldavConnected && root.connectState !== "running"
          onActivated: root.syncNowRequested()
        }
      }

      // Directly under the button that caused it, because that is where the
      // eye already is. A message at the top of a section this tall is a
      // message nobody sees.
      Rectangle {
        width: parent.width
        height: connectResult.height + Style.space(6)
        visible: root.connectMessage !== ""
        radius: Style.cornerRadius
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

        Text {
          id: connectResult
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.space(4)
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          text: root.connectMessage
          color: root.connectState === "done" && !root.connectOk
            ? Color.urgent
            : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }

    // ---- Google: a browser login and four steps in a cloud console, none of
    //      which fits in a status bar popup. So this stays what it always
    //      was: one command, copied for you.

    Column {
      width: parent.width
      visible: root.provider === Model.SOURCE_GOOGLE
      spacing: Style.space(1)

      HoverHandler { id: googleHover; cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: root.setupCommandCopyRequested() }

      Text {
        width: parent.width
        text: root.setupCommandCopied ? root.t("copiedRun") : root.t("googleNeedsTerminal")
        color: googleHover.hovered ? root.foreground : root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Text {
        LayoutMirroring.enabled: false
        width: parent.width
        text: root.setupCommand
        color: googleHover.hovered ? root.foreground : root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WrapAnywhere
      }
    }
  }

  // ---- Calendars

  SectionTitle { text: root.t("calendarsTitle") }

  Text {
    width: parent.width
    visible: root.calendars.length === 0
    text: root.t("nothingSynced")
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: root.calendars

    ToggleRow {
      required property var modelData

      label: modelData.name
      swatch: modelData.color
      checked: root.hiddenCalendars.indexOf(modelData.id) === -1
      onActivated: root.calendarToggled(modelData.id)
    }
  }

  // ---- Calendar system. First on the page because it is the one control
  //      that changes the meaning of every control under it.

  SectionTitle { text: root.t("calendarSystemTitle") }

  Text {
    width: parent.width
    text: root.t("calendarSystemHint")
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Row {
    spacing: Style.space(3)

    Repeater {
      model: [
        { id: Model.JALALI, label: root.t("jalaliOption") },
        { id: Model.GREGORIAN, label: root.t("gregorianOption") }
      ]

      Rectangle {
        required property var modelData

        readonly property bool active: modelData.id === root.calendar

        width: systemLabel.width + Style.space(12)
        height: systemLabel.height + Style.space(5)
        radius: height / 2
        color: active
          ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
          : "transparent"
        border.width: Style.spacing.hairline
        border.color: active ? root.muted : Qt.darker(root.foreground, 2.4)

        Text {
          id: systemLabel
          anchors.centerIn: parent
          text: modelData.label
          color: active ? root.foreground : root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        TapHandler { onTapped: root.calendarSystemPicked(modelData.id) }
      }
    }
  }

  // ---- Display

  SectionTitle { text: root.t("displayTitle") }

  ToggleRow {
    label: root.t("weekStartsLabel")
    hint: root.t("weekStartsHint")
    checked: root.weekStartsOnDefault
    onActivated: root.weekStartToggled()
  }

  ToggleRow {
    // Friday is the weekend everywhere in Iran and is not negotiable, so it
    // is not offered here. Thursday genuinely differs between a bank and a
    // private office, which is the only reason this row exists -- and under
    // Gregorian, where the weekend is Saturday and Sunday, it means nothing
    // at all, so it is not shown.
    visible: root.jalali
    label: root.t("thursdayWeekend")
    hint: root.t("thursdayWeekendHint")
    checked: root.thursdayWeekend
    onActivated: root.thursdayWeekendToggled()
  }

  ToggleRow {
    label: root.t("persianDigitsLabel")
    hint: root.t("persianDigitsHint")
    checked: root.persianDigits
    onActivated: root.persianDigitsToggled()
  }

  ToggleRow {
    label: root.t("rtlLabel")
    hint: root.t("rtlHint")
    checked: root.rightToLeft
    onActivated: root.rightToLeftToggled()
  }

  ToggleRow {
    label: root.t("workingLocation")
    hint: root.t("workingLocationHint")
    checked: root.showWorkingLocation
    onActivated: root.workingLocationToggled()
  }

  ToggleRow {
    // Every row on this page reads "checked means shown". Phrasing this one as
    // "Hide ..." inverted that and made the page contradict itself.
    label: root.t("declinedInvitations")
    hint: root.t("declinedInvitationsHint")
    checked: !root.hideDeclined
    onActivated: root.hideDeclinedToggled()
  }

  ToggleRow {
    label: root.t("yearLifeProgress")
    hint: root.t("yearLifeProgressHint")
    checked: root.showYearProgress
    onActivated: root.yearProgressToggled()
  }

  // ---- Bar

  SectionTitle { text: root.t("barLabelTitle") }

  Text {
    width: parent.width
    text: root.t("barLabelHint")
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Row {
    spacing: Style.space(3)

    Repeater {
      model: [0, 5, 15, 30, 60]

      Rectangle {
        required property var modelData

        readonly property bool active: modelData === root.announceLeadMinutes

        width: leadLabel.width + Style.space(8)
        height: leadLabel.height + Style.space(4)
        radius: height / 2
        color: active
          ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
          : "transparent"
        border.width: Style.spacing.hairline
        border.color: active ? root.muted : Qt.darker(root.foreground, 2.4)

        Text {
          id: leadLabel
          anchors.centerIn: parent
          text: modelData === 0 ? root.t("never") : root.num(modelData) + root.t("minutesSuffix")
          color: active ? root.foreground : root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        TapHandler { onTapped: root.leadMinutesPicked(modelData) }
      }
    }
  }

  // ---- Sync status. Whether it is working, and nothing else: connecting an
  //      account is the section at the top of this page, and the one command
  //      still worth showing is the one for reading the log.

  SectionTitle { text: root.t("syncTitle") }

  // Two items rather than two lines of one, for the same reason the panel's
  // empty state is split: a Text holding a Persian sentence is a
  // right-to-left paragraph throughout, and a shell command laid out
  // right-to-left is a command nobody can paste.
  Column {
    id: syncStatus
    width: parent.width
    spacing: Style.space(1)

    // Nothing to click here. The one thing to do about a missing sync is to
    // connect an account, which is a form at the top of this same page.
    readonly property string message: {
      if (root.syncState === "missing")
        return root.t("noSyncConnect")
      if (root.syncState === "version")
        return root.t("versionNewerShort")

      var line = root.t("syncCount").arg(root.num(root.eventCount)).arg(root.sourceLabel)
      return root.syncState === "stale"
        ? line + ("\n" + root.t("staleCheckShort"))
        : line + ("\n" + root.t("syncLast")).arg(root.syncedAt)
    }

    readonly property string command: {
      if (root.syncState === "stale") return "journalctl --user -u omarchy-calendar-sync"
      return ""
    }

    Text {
      width: parent.width
      text: syncStatus.message
      color: root.faint
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      LayoutMirroring.enabled: false
      width: parent.width
      visible: text !== ""
      text: syncStatus.command
      color: root.faint
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WrapAnywhere
    }
  }
}
