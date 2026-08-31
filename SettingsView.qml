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

  property var calendars: []
  property var hiddenCalendars: []
  property bool showYearProgress: false
  property bool weekStartsSaturday: true
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

  SectionTitle { text: qsTr("تقویم‌ها") }

  Text {
    width: parent.width
    visible: root.calendars.length === 0
    text: qsTr("هنوز چیزی همگام‌سازی نشده، پس چیزی برای انتخاب نیست.")
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

  // ---- Display

  SectionTitle { text: qsTr("نمایش") }

  ToggleRow {
    label: qsTr("شروع هفته از شنبه")
    hint: qsTr("خاموش یعنی هفته از دوشنبه شروع می‌شود")
    checked: root.weekStartsSaturday
    onActivated: root.weekStartToggled()
  }

  ToggleRow {
    // Friday is the weekend everywhere in Iran and is not negotiable, so it
    // is not offered here. Thursday genuinely differs between a bank and a
    // private office, which is the only reason this row exists.
    label: qsTr("پنجشنبه هم تعطیل است")
    hint: qsTr("جمعه همیشه تعطیل در نظر گرفته می‌شود")
    checked: root.thursdayWeekend
    onActivated: root.thursdayWeekendToggled()
  }

  ToggleRow {
    label: qsTr("ارقام فارسی")
    hint: qsTr("خاموش یعنی ارقام لاتین: ۱۴۰۵ در برابر 1405")
    checked: root.persianDigits
    onActivated: root.persianDigitsToggled()
  }

  ToggleRow {
    label: qsTr("چیدمان راست‌به‌چپ")
    hint: qsTr("خاموش یعنی همان چیدمان چپ‌به‌راست تقویم اصلی")
    checked: root.rightToLeft
    onActivated: root.rightToLeftToggled()
  }

  ToggleRow {
    label: qsTr("رویدادهای محل کار")
    hint: qsTr("نشانه‌های دورکاری گوگل، به‌صورت پیش‌فرض پنهان")
    checked: root.showWorkingLocation
    onActivated: root.workingLocationToggled()
  }

  ToggleRow {
    // Every row on this page reads "checked means shown". Phrasing this one as
    // "Hide ..." inverted that and made the page contradict itself.
    label: qsTr("دعوت‌های رد شده")
    hint: qsTr("وقتی روشن است، خط‌خورده نمایش داده می‌شوند")
    checked: !root.hideDeclined
    onActivated: root.hideDeclinedToggled()
  }

  ToggleRow {
    label: qsTr("نوار سال و زندگی")
    hint: qsTr("نوارهای ساعت اصلی اُمارچی، پیش‌فرض خاموش")
    checked: root.showYearProgress
    onActivated: root.yearProgressToggled()
  }

  // ---- Bar

  SectionTitle { text: qsTr("برچسب نوار") }

  Text {
    width: parent.width
    text: qsTr("چند دقیقه مانده به رویداد، نوار ساعت را کنار بگذارد و آن را اعلام کند.")
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
          text: modelData === 0 ? qsTr("هرگز") : root.num(modelData) + qsTr(" دقیقه")
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

  SectionTitle { text: qsTr("همگام‌سازی") }

  Text {
    width: parent.width
    color: root.syncState === "missing" && syncHover.hovered ? root.foreground : root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap

    HoverHandler {
      id: syncHover
      enabled: root.syncState === "missing"
      cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
      enabled: root.syncState === "missing"
      onTapped: root.setupCommandCopyRequested()
    }

    text: {
      if (root.syncState === "missing") {
        return root.setupCommandCopied
          ? qsTr("کپی شد. در ترمینال اجرا کنید:\n%1").arg(root.setupCommand)
          : qsTr("هنوز تقویمی وصل نشده. برای کپی کلیک کنید، سپس اجرا کنید:\n%1").arg(root.setupCommand)
      }
      if (root.syncState === "version") return qsTr("فایل رویدادها را نسخهٔ جدیدتری از این افزونه نوشته است.")

      var line = qsTr("%1 رویداد از %2").arg(root.num(root.eventCount)).arg(root.sourceLabel)
      if (root.syncState === "stale") {
        return line + qsTr("\nآخرین همگام‌سازی قدیمی به نظر می‌رسد. بررسی کنید: journalctl --user -u omarchy-calendar-sync")
      }
      return line + qsTr("\nآخرین همگام‌سازی %1").arg(root.syncedAt)
    }
  }
}
