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

  // ---- Sync status. Read-only on purpose: changing the Google account is an
  //      OAuth browser flow, which belongs to sync/setup and not to a popup
  //      in a status bar. What belongs here is knowing whether it is working.

  SectionTitle { text: root.t("syncTitle") }

  // Two items rather than two lines of one, for the same reason the panel's
  // empty state is split: a Text holding a Persian sentence is a
  // right-to-left paragraph throughout, and a shell command laid out
  // right-to-left is a command nobody can paste.
  Column {
    id: syncStatus
    width: parent.width
    spacing: Style.space(1)

    readonly property bool actionable: root.syncState === "missing"

    readonly property string message: {
      if (root.syncState === "missing") {
        return root.setupCommandCopied
          ? root.t("copiedRun")
          : root.t("noSyncConnect")
      }
      if (root.syncState === "version")
        return root.t("versionNewerShort")

      var line = root.t("syncCount").arg(root.num(root.eventCount)).arg(root.sourceLabel)
      return root.syncState === "stale"
        ? line + ("\n" + root.t("staleCheckShort"))
        : line + ("\n" + root.t("syncLast")).arg(root.syncedAt)
    }

    readonly property string command: {
      if (root.syncState === "missing") return root.setupCommand
      if (root.syncState === "stale") return "journalctl --user -u omarchy-calendar-sync"
      return ""
    }

    readonly property color shade: syncStatus.actionable && syncHover.hovered
      ? root.foreground
      : root.faint

    HoverHandler {
      id: syncHover
      enabled: syncStatus.actionable
      cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
      enabled: syncStatus.actionable
      onTapped: root.setupCommandCopyRequested()
    }

    Text {
      width: parent.width
      text: syncStatus.message
      color: syncStatus.shade
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      LayoutMirroring.enabled: false
      width: parent.width
      visible: text !== ""
      text: syncStatus.command
      color: syncStatus.shade
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WrapAnywhere
    }
  }
}
