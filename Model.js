// Pure date, calendar and format math for the Jalali clock widget and its
// panel. Locale- and Qt-free so it loads under node and is unit tested there
// (tests/model.test.js, tests/jalali.test.js).
//
// This file is one module rather than two on purpose. QML gives an imported
// .js file no way to import another one that node can also load -- Qt's
// `.import` is a syntax error under node, and injecting the dependency from
// QML would have to be repeated in every .qml file, since a plain (non
// `.pragma library`) JS import is instantiated once per importing document.
// So the Jalali arithmetic sits here, in its own section, rather than in a
// second file that neither side could use comfortably.
//
// ============================================================================
// Section 1 -- Jalali (Solar Hijri / Shamsi) calendar arithmetic
// ============================================================================
//
// The conversion is the Borkowski 33-year-cycle algorithm, the same one
// jalaali-js implements. It is exact for Jalali years 1178 to 1633, which
// covers 1799 to 2256 in the Gregorian calendar -- every date this widget can
// be pointed at and then some.
//
// Nothing in this section knows about events. The events file speaks
// Gregorian "YYYY-MM-DD" date keys and keeps doing so: a Jalali front end
// over a Gregorian data contract means any sync written for the upstream
// calendar feeds this one unchanged, and the two plugins can share one file.

function div(a, b) {
  return Math.trunc(a / b)
}

function mod(a, b) {
  return a - Math.trunc(a / b) * b
}

// Years at which the 33-year leap cycle shifts. Straight from Borkowski.
var BREAKS = [-61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181, 1210,
              1635, 2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178]

var MIN_JALALI_YEAR = -61
var MAX_JALALI_YEAR = 3177

// Leap flag for a Jalali year, plus the Gregorian March day that year's
// Farvardin 1 lands on. `leap` is 0 in a leap year, which reads backwards but
// is what the cycle arithmetic falls out as.
function jalCal(jy) {
  var year = Math.round(Number(jy))
  if (!isFinite(year) || year < MIN_JALALI_YEAR || year > MAX_JALALI_YEAR) return null

  var gy = year + 621
  var leapJ = -14
  var jp = BREAKS[0]
  var jump = 0
  var i, jm

  for (i = 1; i < BREAKS.length; i++) {
    jm = BREAKS[i]
    jump = jm - jp
    if (year < jm) break
    leapJ = leapJ + div(jump, 33) * 8 + div(mod(jump, 33), 4)
    jp = jm
  }

  var n = year - jp
  leapJ = leapJ + div(n, 33) * 8 + div(mod(n, 33) + 3, 4)
  if (mod(jump, 33) === 4 && jump - n === 4) leapJ += 1

  var leapG = div(gy, 4) - div((div(gy, 100) + 1) * 3, 4) - 150
  var march = 20 + leapJ - leapG

  if (jump - n < 6) n = n - jump + div(jump + 4, 33) * 33
  var leap = mod(mod(n + 1, 33) - 1, 4)
  if (leap === -1) leap = 4

  return { leap: leap, gy: gy, march: march }
}

// Julian Day Number for a Gregorian date. gm is 1-12, not JS's 0-11: this
// half of the file is calendar arithmetic and 1-based months are what every
// published form of these formulas is written in.
function g2d(gy, gm, gd) {
  var d = div((gy + div(gm - 8, 6) + 100100) * 1461, 4)
    + div(153 * mod(gm + 9, 12) + 2, 5)
    + gd - 34840408
  return d - div(div(gy + 100100 + div(gm - 8, 6), 100) * 3, 4) + 752
}

function d2g(jdn) {
  var j = 4 * jdn + 139361631
  j = j + div(div(4 * jdn + 183187720, 146097) * 3, 4) * 4 - 3908
  var i = div(mod(j, 1461), 4) * 5 + 308
  var gd = div(mod(i, 153), 5) + 1
  var gm = mod(div(i, 153), 12) + 1
  var gy = div(j, 1461) - 100100 + div(8 - gm, 6)
  return { gy: gy, gm: gm, gd: gd }
}

function j2d(jy, jm, jd) {
  var r = jalCal(jy)
  if (!r) return null
  return g2d(r.gy, 3, r.march) + (jm - 1) * 31 - div(jm, 7) * (jm - 7) + jd - 1
}

function d2j(jdn) {
  var gy = d2g(jdn).gy
  var jy = gy - 621
  var r = jalCal(jy)
  if (!r) return null

  var k = jdn - g2d(gy, 3, r.march)
  var jm, jd

  if (k >= 0) {
    if (k <= 185) {
      jm = 1 + div(k, 31)
      jd = mod(k, 31) + 1
      return { jy: jy, jm: jm, jd: jd }
    }
    k -= 186
  } else {
    jy -= 1
    k += 179
    if (r.leap === 1) k += 1
  }

  jm = 7 + div(k, 30)
  jd = mod(k, 30) + 1
  return { jy: jy, jm: jm, jd: jd }
}

// ---- The pair everything else is built on.

function toJalali(gy, gm, gd) {
  return d2j(g2d(gy, gm, gd))
}

function toGregorian(jy, jm, jd) {
  var jdn = j2d(jy, jm, jd)
  return jdn === null ? null : d2g(jdn)
}

// A JS Date's local Y/M/D, never its UTC ones: which Jalali day it is depends
// on where you are standing, and getUTC* would roll the calendar over at the
// wrong midnight for everyone outside Greenwich.
function jalaliFromDate(date) {
  return toJalali(date.getFullYear(), date.getMonth() + 1, date.getDate())
}

// Local midnight of a Jalali date. Built field by field through the Date
// constructor rather than parsed from a string, for the same reason.
function dateFromJalali(jy, jm, jd) {
  var g = toGregorian(jy, jm, jd)
  if (!g) return null
  return new Date(g.gy, g.gm - 1, g.gd)
}

function isLeapJalaliYear(jy) {
  var r = jalCal(jy)
  return r !== null && r.leap === 0
}

// The first six months are 31 days, the next five are 30, and Esfand is 29
// except in a leap year. No table needed.
function jalaliMonthLength(jy, jm) {
  var month = Math.round(Number(jm))
  if (!isFinite(month) || month < 1 || month > 12) return 0
  if (month <= 6) return 31
  if (month <= 11) return 30
  return isLeapJalaliYear(jy) ? 30 : 29
}

function jalaliDaysInYear(jy) {
  return isLeapJalaliYear(jy) ? 366 : 365
}

function jalaliDayOfYear(jy, jm, jd) {
  var month = Math.round(Number(jm))
  var total = Number(jd)
  for (var i = 1; i < month; i++) total += jalaliMonthLength(jy, i)
  return total
}

// ---- Names.
//
// Weekday arrays are indexed by JS Date.getDay(), so index 0 is Sunday and
// index 6 is Saturday. That matches QML's Locale.Sunday..Locale.Saturday
// too, which is what lets a week-start setting be passed straight through.

var JALALI_MONTHS = [
  "فروردین", "اردیبهشت", "خرداد", "تیر", "مرداد", "شهریور",
  "مهر", "آبان", "آذر", "دی", "بهمن", "اسفند"
]

var WEEKDAYS = ["یکشنبه", "دوشنبه", "سه‌شنبه", "چهارشنبه", "پنجشنبه", "جمعه", "شنبه"]

// One letter each, because seven columns of "چهارشنبه" would set the width of
// the whole grid off a single day name.
var WEEKDAYS_SHORT = ["ی", "د", "س", "چ", "پ", "ج", "ش"]

// Saturday. The Iranian week runs شنبه to جمعه, and Friday is the weekend.
var SATURDAY = 6
var FRIDAY = 5
var THURSDAY = 4

function jalaliMonthName(jm) {
  var index = Math.round(Number(jm)) - 1
  return JALALI_MONTHS[index] || ""
}

function persianWeekdayName(weekday) {
  return WEEKDAYS[((Math.round(Number(weekday)) % 7) + 7) % 7] || ""
}

function persianWeekdayShortName(weekday) {
  return WEEKDAYS_SHORT[((Math.round(Number(weekday)) % 7) + 7) % 7] || ""
}

// ---- Digits.

var PERSIAN_DIGITS = ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"]

function toPersianDigits(text) {
  return String(text === undefined || text === null ? "" : text)
    .replace(/[0-9]/g, function(digit) { return PERSIAN_DIGITS[Number(digit)] })
}

// Both Persian (۰-۹) and Arabic-Indic (٠-٩) digits map back, because a
// keyboard set to Arabic produces the second set and a number typed into the
// birth-year field has to parse either way.
function toLatinDigits(text) {
  return String(text === undefined || text === null ? "" : text)
    .replace(/[۰-۹]/g, function(ch) { return String(ch.charCodeAt(0) - 0x06F0) })
    .replace(/[٠-٩]/g, function(ch) { return String(ch.charCodeAt(0) - 0x0660) })
}

// ---- Week of the year.
//
// Weeks run Saturday to Friday, week 1 is the week holding Farvardin 1, and
// the count restarts every Nowruz. That is the Iranian convention, and it is
// not ISO 8601: there is no four-day rule, so a year's first week is usually
// a partial one.
//
// A week is owned by the year its Friday falls in. Without that rule a year
// whose Nowruz lands on a Friday opens with a one-day week 1 and closes with
// a one-day week 54, which is a number no Persian calendar prints. Handing
// the trailing days to the next year's week 1 -- the week they share with
// that year's Nowruz -- caps every year at 52 or 53 weeks.
function jalaliWeek(jy, jm, jd) {
  var date = dateFromJalali(jy, jm, jd)
  if (!date) return 0

  var toFriday = (FRIDAY - date.getDay() + 7) % 7
  var friday = new Date(date.getFullYear(), date.getMonth(), date.getDate() + toFriday)
  var owner = jalaliFromDate(friday)

  var first = dateFromJalali(owner.jy, 1, 1)
  if (!first) return 0
  var offset = (first.getDay() - SATURDAY + 7) % 7
  return Math.floor((jalaliDayOfYear(owner.jy, owner.jm, owner.jd) - 1 + offset) / 7) + 1
}

// ============================================================================
// Section 2 -- Gregorian calendar arithmetic
// ============================================================================
//
// The other calendar this widget can be switched into, so it can stand in for
// Omarchy's built-in clock rather than sitting beside it. Written in the same
// shape as the Jalali section above -- 1-based months, JS weekday indices --
// so the dispatch layer below can treat the two as interchangeable instead of
// special-casing one of them at every call.

var MS_PER_DAY = 86400000

function isGregorianLeapYear(gy) {
  var year = Math.round(Number(gy))
  return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0
}

var GREGORIAN_MONTH_LENGTHS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

function gregorianMonthLength(gy, gm) {
  var month = Math.round(Number(gm))
  if (!isFinite(month) || month < 1 || month > 12) return 0
  if (month === 2 && isGregorianLeapYear(gy)) return 29
  return GREGORIAN_MONTH_LENGTHS[month - 1]
}

function gregorianDaysInYear(gy) {
  return isGregorianLeapYear(gy) ? 366 : 365
}

function gregorianDayOfYear(gy, gm, gd) {
  var month = Math.round(Number(gm))
  var total = Number(gd)
  for (var i = 1; i < month; i++) total += gregorianMonthLength(gy, i)
  return total
}

function gregorianFromDate(date) {
  return { year: date.getFullYear(), month: date.getMonth() + 1, day: date.getDate() }
}

function dateFromGregorian(gy, gm, gd) {
  return new Date(gy, gm - 1, gd)
}

// ISO-8601 week number: the week owning the Thursday of that date's
// Monday-based week. This is the built-in clock's 'ww' token, kept exactly,
// so switching this widget to Gregorian gives back the same numbers the
// widget it replaces was giving.
function isoWeek(gy, gm, gd) {
  var date = new Date(Date.UTC(gy, gm - 1, gd))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

var GREGORIAN_MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"
]

var GREGORIAN_MONTHS_SHORT = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]

// Indexed by JS Date.getDay(), like every other weekday table here.
var GREGORIAN_WEEKDAYS = [
  "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
]

var GREGORIAN_WEEKDAYS_SHORT = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

// ============================================================================
// Section 3 -- One widget, two calendars
// ============================================================================
//
// Everything above is arithmetic on one calendar or the other. Everything
// below asks this layer instead, so the panel and the bar never branch on
// which calendar is active: they pass it down and get answers back.
//
// The choice carries more than month names with it. A Jalali calendar that
// opened its weeks on Monday, numbered them ISO, wrote its digits in Latin
// and laid itself out left to right would be a Gregorian calendar wearing
// Persian labels. So the calendar picks the week start, the weekend, the week
// numbering, the digits, the reading direction and the interface language --
// and every one of those stays overridable on its own, because the defaults
// are a starting point and not a claim about how anyone works.

var JALALI = "jalali"
var GREGORIAN = "gregorian"

function normalizeCalendar(value) {
  var text = String(value === undefined || value === null ? "" : value)
    .replace(/^\s+|\s+$/g, "").toLowerCase()
  // "miladi" and "shamsi" are what these two are called in Persian, and
  // shell.json is hand-edited often enough for that to be worth accepting.
  if (text === GREGORIAN || text === "miladi" || text === "gregorian") return GREGORIAN
  return JALALI
}

function isJalali(calendar) {
  return normalizeCalendar(calendar) === JALALI
}

function otherCalendar(calendar) {
  return isJalali(calendar) ? GREGORIAN : JALALI
}

// A civil date -- { year, month, day } with a 1-based month -- in whichever
// calendar was asked for. The Date it came from is untouched: a calendar is
// a way of naming a day, never the day itself.
function fromDate(calendar, date) {
  if (!isJalali(calendar)) return gregorianFromDate(date)
  var j = jalaliFromDate(date)
  return j ? { year: j.jy, month: j.jm, day: j.jd } : null
}

function toDate(calendar, year, month, day) {
  return isJalali(calendar)
    ? dateFromJalali(year, month, day)
    : dateFromGregorian(year, month, day)
}

function monthLength(calendar, year, month) {
  return isJalali(calendar)
    ? jalaliMonthLength(year, month)
    : gregorianMonthLength(year, month)
}

function daysInYear(calendar, year) {
  return isJalali(calendar) ? jalaliDaysInYear(year) : gregorianDaysInYear(year)
}

function dayOfYear(calendar, year, month, day) {
  return isJalali(calendar)
    ? jalaliDayOfYear(year, month, day)
    : gregorianDayOfYear(year, month, day)
}

// Two genuinely different definitions, not one with the names swapped. The
// Jalali count restarts at Nowruz and runs Saturday to Friday with no
// four-day rule; ISO restarts in January and runs Monday to Sunday with one.
function weekOfYear(calendar, year, month, day) {
  return isJalali(calendar)
    ? jalaliWeek(year, month, day)
    : isoWeek(year, month, day)
}

// Saturday opens the Iranian week. Monday opens the ISO one, which is what
// the built-in clock defaulted to through Qt's locale.
function defaultWeekStart(calendar) {
  return isJalali(calendar) ? SATURDAY : 1
}

// Friday in Iran, Saturday and Sunday elsewhere. Thursday is offered as an
// extra rather than assumed, because whether it is a working day is a real
// disagreement in Iran and not a preference: banks and schools are shut,
// plenty of private offices are not.
function isWeekendDay(calendar, weekday, options) {
  var day = ((Math.round(Number(weekday)) % 7) + 7) % 7
  var opts = options || {}

  if (!isJalali(calendar)) return day === 0 || day === SATURDAY
  if (day === FRIDAY) return true
  return opts.thursdayWeekend === true && day === THURSDAY
}

function usesPersianDigitsByDefault(calendar) {
  return isJalali(calendar)
}

function isRightToLeftByDefault(calendar) {
  return isJalali(calendar)
}

// A setting that is unset should follow the calendar rather than sit on a
// hardcoded default, so switching calendars moves everything that ought to
// move. An explicit true or false always wins, so a deliberate choice is
// never undone by a later switch.
function resolveBoolean(value, fallback) {
  if (value === true || value === false) return value
  if (value === "true") return true
  if (value === "false") return false
  return fallback === true
}

// ---- Names.
//
// `overrides` exists for one case: in Gregorian mode the panel hands in
// Qt.locale()'s own month and day names, so a desktop running in French
// keeps reading French, exactly as the built-in clock did. Model.js stays
// locale-free and testable; the locale stays where the locale lives.
function calendarNames(calendar, overrides) {
  var base = isJalali(calendar)
    ? {
        months: JALALI_MONTHS,
        // Persian month names have no accepted abbreviation, so the short
        // form is the long one. Inventing "فرو" would only be harder to read.
        monthsShort: JALALI_MONTHS,
        weekdays: WEEKDAYS,
        weekdaysShort: WEEKDAYS_SHORT
      }
    : {
        months: GREGORIAN_MONTHS,
        monthsShort: GREGORIAN_MONTHS_SHORT,
        weekdays: GREGORIAN_WEEKDAYS,
        weekdaysShort: GREGORIAN_WEEKDAYS_SHORT
      }

  var over = overrides || {}
  return {
    months: over.months && over.months.length === 12 ? over.months : base.months,
    monthsShort: over.monthsShort && over.monthsShort.length === 12 ? over.monthsShort : base.monthsShort,
    weekdays: over.weekdays && over.weekdays.length === 7 ? over.weekdays : base.weekdays,
    weekdaysShort: over.weekdaysShort && over.weekdaysShort.length === 7 ? over.weekdaysShort : base.weekdaysShort
  }
}

function monthName(calendar, month, overrides) {
  var index = Math.round(Number(month)) - 1
  return calendarNames(calendar, overrides).months[index] || ""
}

function weekdayName(calendar, weekday, overrides) {
  var index = ((Math.round(Number(weekday)) % 7) + 7) % 7
  return calendarNames(calendar, overrides).weekdays[index] || ""
}

function weekdayShortName(calendar, weekday, overrides) {
  var index = ((Math.round(Number(weekday)) % 7) + 7) % 7
  return calendarNames(calendar, overrides).weekdaysShort[index] || ""
}

// ---- Interface strings.
//
// A table rather than qsTr, because the language here follows the calendar
// rather than the desktop: switching to Gregorian is how this widget stands
// in for the built-in clock, and a Persian "Settings" button on that clock
// would be the wrong answer. There are no translation files to ship and no
// lupdate step to forget.
var STRINGS = {}

STRINGS[JALALI] = {
  settings: "تنظیمات",
  backToCalendar: "بازگشت به تقویم",
  backToToday: "بازگشت به امروز",
  nothingElseToday: "امروز رویداد دیگری نیست",
  born: "متولد",
  yearPlaceholder: "سال",
  liveTo: "تا سن",
  life: "زندگی",
  mementoMori: "یادِ مرگ",
  weekHeader: "هفته",
  weekStartTooltip: "شروع هفته از %1",
  previousMonth: "ماه قبل",
  nextMonth: "ماه بعد",
  join: "پیوستن",
  allDay: "تمام‌روز",
  declined: "رد شده",
  outOfOffice: "خارج از دفتر",
  nothingScheduled: "رویدادی ثبت نشده",
  atTime: "ساعت",
  countdownNow: "هم‌اکنون",

  copiedRun: "کپی شد. در ترمینال اجرا کنید:",
  noSyncRun: "هنوز تقویمی همگام‌سازی نشده. برای کپی کلیک کنید، سپس اجرا کنید:",
  noSyncConnect: "هنوز تقویمی وصل نشده. برای کپی کلیک کنید، سپس اجرا کنید:",
  versionNewer: "فایل رویدادها را نسخهٔ جدیدتری نوشته است. افزونه را به‌روز کنید.",
  versionNewerShort: "فایل رویدادها را نسخهٔ جدیدتری از این افزونه نوشته است.",
  staleCheck: "ممکن است تقویم به‌روز نباشد. بررسی کنید:",
  staleCheckShort: "آخرین همگام‌سازی قدیمی به نظر می‌رسد. بررسی کنید:",

  calendarsTitle: "تقویم‌ها",
  nothingSynced: "هنوز چیزی همگام‌سازی نشده، پس چیزی برای انتخاب نیست.",
  calendarSystemTitle: "تقویم",
  calendarSystemHint: "کل ویجت عوض می‌شود: نام ماه‌ها، شروع هفته، تعطیلی، شمارهٔ هفته، ارقام و جهت چیدمان.",
  jalaliOption: "شمسی",
  gregorianOption: "میلادی",
  displayTitle: "نمایش",
  weekStartsLabel: "شروع هفته از شنبه",
  weekStartsHint: "خاموش یعنی هفته از دوشنبه شروع می‌شود",
  thursdayWeekend: "پنجشنبه هم تعطیل است",
  thursdayWeekendHint: "جمعه همیشه تعطیل در نظر گرفته می‌شود",
  persianDigitsLabel: "ارقام فارسی",
  persianDigitsHint: "خاموش یعنی ارقام لاتین: ۱۴۰۵ در برابر 1405",
  rtlLabel: "چیدمان راست‌به‌چپ",
  rtlHint: "خاموش یعنی همان چیدمان چپ‌به‌راست تقویم اصلی",
  workingLocation: "رویدادهای محل کار",
  workingLocationHint: "نشانه‌های دورکاری گوگل، به‌صورت پیش‌فرض پنهان",
  declinedInvitations: "دعوت‌های رد شده",
  declinedInvitationsHint: "وقتی روشن است، خط‌خورده نمایش داده می‌شوند",
  yearLifeProgress: "نوار سال و زندگی",
  yearLifeProgressHint: "نوارهای ساعت اصلی اُمارچی، پیش‌فرض خاموش",
  barLabelTitle: "برچسب نوار",
  barLabelHint: "چند دقیقه مانده به رویداد، نوار ساعت را کنار بگذارد و آن را اعلام کند.",
  never: "هرگز",
  minutesSuffix: " دقیقه",
  syncTitle: "همگام‌سازی",
  syncCount: "%1 رویداد از %2",
  syncLast: "آخرین همگام‌سازی %1"
}

STRINGS[GREGORIAN] = {
  settings: "Settings",
  backToCalendar: "Back to calendar",
  backToToday: "Back to today",
  nothingElseToday: "Nothing else today",
  born: "BORN",
  yearPlaceholder: "year",
  liveTo: "LIVE TO",
  life: "LIFE",
  mementoMori: "Memento Mori",
  weekHeader: "W",
  weekStartTooltip: "Start weeks on %1",
  previousMonth: "Previous month",
  nextMonth: "Next month",
  join: "Join",
  allDay: "All day",
  declined: "Declined",
  outOfOffice: "Out of office",
  nothingScheduled: "Nothing scheduled",
  atTime: "at",
  countdownNow: "now",

  copiedRun: "Copied. Paste it in a terminal:",
  noSyncRun: "No calendar synced yet. Click to copy, then run:",
  noSyncConnect: "No calendar connected yet. Click to copy, then run:",
  versionNewer: "Events file was written by a newer version. Update the plugin.",
  versionNewerShort: "The events file was written by a newer version of this plugin.",
  staleCheck: "Calendar may be out of date. Check:",
  staleCheckShort: "Last sync looks old. Check:",

  calendarsTitle: "CALENDARS",
  nothingSynced: "Nothing synced yet, so there is nothing to choose from.",
  calendarSystemTitle: "CALENDAR",
  calendarSystemHint: "Switches the whole widget: month names, week start, weekend, week numbers, digits and reading direction.",
  jalaliOption: "Jalali",
  gregorianOption: "Gregorian",
  displayTitle: "DISPLAY",
  weekStartsLabel: "Week starts on Monday",
  weekStartsHint: "Off starts the week on Sunday",
  thursdayWeekend: "Thursday is a weekend too",
  thursdayWeekendHint: "Only applies to the Jalali calendar",
  persianDigitsLabel: "Persian digits",
  persianDigitsHint: "Off uses Latin digits: 2026 rather than ۲۰۲۶",
  rtlLabel: "Right-to-left layout",
  rtlHint: "Off is the usual left-to-right layout",
  workingLocation: "Working location events",
  workingLocationHint: "Google's work-from-home markers, hidden by default",
  declinedInvitations: "Declined invitations",
  declinedInvitationsHint: "Shown struck through when on",
  yearLifeProgress: "Year and life progress",
  yearLifeProgressHint: "The upstream clock's bars, off by default",
  barLabelTitle: "BAR LABEL",
  barLabelHint: "How early the bar gives up the clock to announce what is next.",
  never: "Never",
  minutesSuffix: "min",
  syncTitle: "SYNC",
  syncCount: "%1 events from %2",
  syncLast: "Last sync %1"
}

function text(calendar, key) {
  var table = STRINGS[normalizeCalendar(calendar)] || STRINGS[JALALI]
  var value = table[key]
  return value === undefined ? "" : value
}

// Exported so a test can hold the two tables against each other. A key
// present in one and missing from the other renders as an empty label --
// a blank button rather than a crash, which is exactly the kind of thing
// no other test would notice.
function stringKeys(calendar) {
  var table = STRINGS[normalizeCalendar(calendar)] || STRINGS[JALALI]
  var keys = []
  for (var key in table) keys.push(key)
  return keys.sort()
}

// ---- Formatting.
//
// Qt's format tokens, resolved against whichever calendar is active, so one
// format string in shell.json keeps meaning what it meant across a switch --
// MMMM is still the month name, it is just a different calendar's now.
// Implemented here rather than handed to Qt.formatDateTime because Qt has no
// Jalali calendar and would answer every one of these in Gregorian.

function pad2(value) {
  var n = Math.abs(Math.round(Number(value)))
  return (n < 10 ? "0" : "") + n
}

var TOKENS = [
  "yyyy", "yy",
  "MMMM", "MMM", "MM", "M",
  "dddd", "ddd", "dd", "d",
  "HH", "H", "hh", "h",
  "mm", "m",
  "ss", "s",
  "ww", "w",
  "AP", "ap", "A", "a"
]

function tokenValue(token, parts) {
  switch (token) {
    case "yyyy": return String(parts.year)
    case "yy": return pad2(parts.year % 100)
    case "MMMM": return parts.names.months[parts.month - 1] || ""
    case "MMM": return parts.names.monthsShort[parts.month - 1] || ""
    case "MM": return pad2(parts.month)
    case "M": return String(parts.month)
    case "dddd": return parts.names.weekdays[parts.weekday] || ""
    case "ddd": return parts.names.weekdaysShort[parts.weekday] || ""
    case "dd": return pad2(parts.day)
    case "d": return String(parts.day)
    case "HH": return pad2(parts.hours)
    case "H": return String(parts.hours)
    case "hh": return pad2(parts.hours12)
    case "h": return String(parts.hours12)
    case "mm": return pad2(parts.minutes)
    case "m": return String(parts.minutes)
    case "ss": return pad2(parts.seconds)
    case "s": return String(parts.seconds)
    case "ww": return pad2(parts.week)
    case "w": return String(parts.week)
    case "AP":
    case "A":
    case "ap":
    case "a":
      return parts.calendar === JALALI
        ? (parts.hours < 12 ? "ق.ظ" : "ب.ظ")
        : (parts.hours < 12 ? "AM" : "PM")
    default: return token
  }
}

function dateParts(calendar, date, names) {
  var civil = fromDate(calendar, date)
  if (!civil) return null

  var hours = date.getHours()
  return {
    calendar: normalizeCalendar(calendar),
    names: calendarNames(calendar, names),
    year: civil.year,
    month: civil.month,
    day: civil.day,
    weekday: date.getDay(),
    hours: hours,
    hours12: (hours % 12) === 0 ? 12 : (hours % 12),
    minutes: date.getMinutes(),
    seconds: date.getSeconds(),
    week: weekOfYear(calendar, civil.year, civil.month, civil.day)
  }
}

// `options` is { calendar, persianDigits, names }, every field optional. An
// omitted calendar means Jalali and omitted digits follow the calendar, so a
// bare two-argument call still does the obvious thing.
function format(date, pattern, options) {
  var opts = options || {}
  var calendar = normalizeCalendar(opts.calendar)
  var parts = dateParts(calendar, date, opts.names)
  if (!parts) return ""

  var input = String(pattern === undefined || pattern === null ? "" : pattern)
  var out = ""
  var i = 0

  while (i < input.length) {
    var ch = input.charAt(i)

    // Single quotes escape a literal run, and '' is a literal quote, both
    // inside and outside a run -- Qt's rules, so "'هفته'ww" and "''yy" keep
    // working.
    if (ch === "'") {
      if (input.charAt(i + 1) === "'") { out += "'"; i += 2; continue }
      i += 1
      while (i < input.length) {
        if (input.charAt(i) === "'") {
          if (input.charAt(i + 1) === "'") { out += "'"; i += 2; continue }
          i += 1
          break
        }
        out += input.charAt(i)
        i += 1
      }
      continue
    }

    var matched = ""
    for (var t = 0; t < TOKENS.length; t++) {
      var token = TOKENS[t]
      if (input.substr(i, token.length) === token) { matched = token; break }
    }

    if (matched === "") { out += ch; i += 1; continue }
    out += tokenValue(matched, parts)
    i += matched.length
  }

  return resolveBoolean(opts.persianDigits, usesPersianDigitsByDefault(calendar))
    ? toPersianDigits(out)
    : out
}

// ============================================================================
// Section 4 -- The widget's own model
// ============================================================================

// Weekday indices match both JS Date.getDay() and QML's Locale.Sunday…
// Locale.Saturday, so a locale's firstDayOfWeek can be passed straight in.
// The names are the English ones because they are what gets written to
// shell.json: a config file is read by tooling, not by a reader.
var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

// ---- Bar label formats. Right-clicking the clock walks these in order and
//      writes the result back to shell.json, so the label the bar shows and
//      the format the config stores are always the same thing.
//
// Each 24-hour preset is followed by its 12-hour twin, so walking from one to
// the other is a single right click rather than a lap of the ring. The
// numeric yyyy/MM/dd preset has no twin: it is the form used on forms and
// invoices, which is not written with ق.ظ after it.
var CLOCK_FORMATS = {}

CLOCK_FORMATS[JALALI] = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "HH:mm",
  "h:mm AP",
  "d MMMM HH:mm",
  "d MMMM h:mm AP",
  "dddd d MMMM yyyy",
  "yyyy/MM/dd HH:mm"
]

// The built-in clock's own ring, so switching to Gregorian gives back the
// formats the widget it replaces offered, in the order it offered them.
CLOCK_FORMATS[GREGORIAN] = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

// Vertical bars have room for a few stacked lines and nothing else, so the
// ring stays short. AM/PM costs a fourth line, which is why only the plain
// time carries it here.
var VERTICAL_CLOCK_FORMATS = {}

VERTICAL_CLOCK_FORMATS[JALALI] = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\nyy",
  "HH\nmm"
]

VERTICAL_CLOCK_FORMATS[GREGORIAN] = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

function clockFormats(vertical, calendar) {
  var table = vertical ? VERTICAL_CLOCK_FORMATS : CLOCK_FORMATS
  return (table[normalizeCalendar(calendar)] || []).slice()
}

// The presets in a fixed order, plus the configured alternate and current
// format when they are something else. The order must not depend on which
// entry is current: cycling writes the result back to shell.json, and a ring
// that reshuffled itself around the current value would bounce between two
// entries instead of walking.
function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var candidate = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (candidate === "" || ring.indexOf(candidate) !== -1) continue
    ring.push(candidate)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}

// Next entry after `current`. An unknown current format (a hand-written one
// that is not in the ring) starts the walk at the top.
function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

// ---- Day identity.
//
// Deliberately still Gregorian. This is the key the events file is written
// with, and the one the grid looks events up by, so it has to stay exactly
// what a sync built for the upstream calendar emits. The Jalali date is a
// rendering of a day, never its name.

function padTwo(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

function dateKey(year, month, day) {
  return year + "-" + padTwo(Number(month) + 1) + "-" + padTwo(day)
}

function keyForDate(date) {
  return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

// Turn a YYYY-MM-DD key back into a local Date. Built field by field rather
// than parsed from the string, because new Date("2026-08-10") is UTC midnight
// and lands on the previous day for anyone west of Greenwich.
function dateFromKey(key, fallback) {
  var parts = String(key || "").split("-")
  if (parts.length !== 3) return fallback

  var year = parseInt(parts[0], 10)
  var month = parseInt(parts[1], 10)
  var day = parseInt(parts[2], 10)
  if (isNaN(year) || isNaN(month) || isNaN(day)) return fallback

  return new Date(year, month - 1, day)
}

// ---- Week start.

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null

  var text = toLatinDigits(String(value)).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "") return null

  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i

  var parsed = parseInt(text, 10)
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null
}

// Configured week start, falling back to whatever the active calendar opens
// its weeks on. Unlike the built-in clock this never defers to Qt's locale:
// a Jalali calendar laid out Monday-first because the desktop is in en_US
// would be wrong in the one way this widget exists to fix.
function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value)
  if (configured !== null) return configured
  var fallbackStart = coerceWeekStart(fallback)
  return fallbackStart === null ? SATURDAY : fallbackStart
}

function weekStartSettingName(index) {
  return WEEKDAY_NAMES[normalizedWeekStart(index, SATURDAY)]
}

// Each calendar toggles between the two starts people actually switch
// between in it: Saturday and Monday under Jalali, Monday and Sunday under
// Gregorian. A calendar configured to anything else is shown as it is and
// lands on its own default the first time it is toggled.
function toggledWeekStart(index, calendar) {
  var start = normalizedWeekStart(index, defaultWeekStart(calendar))
  if (isJalali(calendar)) return start === SATURDAY ? 1 : SATURDAY
  return start === 1 ? 0 : 1
}

function weekdayOrder(weekStart, calendar) {
  var start = normalizedWeekStart(weekStart, defaultWeekStart(calendar))
  var out = []
  for (var i = 0; i < 7; i++) out.push((start + i) % 7)
  return out
}

// ---- Year progress, measured on whichever year is on screen. Under Jalali
//      the bar empties at Nowruz rather than in January, which is the whole
//      reason it is not simply the Gregorian one relabelled.

function yearProgress(calendar, year, month, day) {
  var total = daysInYear(calendar, year)
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, (dayOfYear(calendar, year, month, day) - 1) / total))
}

function yearProgressPercent(calendar, year, month, day) {
  return Math.round(yearProgress(calendar, year, month, day) * 100)
}

// Memento mori. The default span is a round number rather than anything from
// an actuarial table: the point of the bar is the reminder, not the
// arithmetic, and whoever wants a different number can say so.
var DEFAULT_LIFE_EXPECTANCY = 90

// A birth year rather than an age, so the bar keeps counting on its own
// instead of going stale the moment it is entered. 0 means "not set", which
// is also what a blank, malformed, future, or implausibly distant year means.
// Persian digits are accepted: the field is typed into with a Persian
// keyboard as often as not.
//
// The year is read and written in whatever calendar is on screen -- an
// Iranian knows their birth year as 1358, not 1979 -- so `currentYear` is the
// current year in that same calendar. Storage is a separate question, handled
// by the pair below.
function parseBirthYear(value, currentYear) {
  var now = Math.round(Number(currentYear))
  if (!isFinite(now)) return 0
  var text = toLatinDigits(String(value === undefined || value === null ? "" : value)).replace(/^\s+|\s+$/g, "")
  if (!/^\d{4}$/.test(text)) return 0
  var year = parseInt(text, 10)
  if (!isFinite(year) || year > now || year < now - 120) return 0
  return year
}

// Whole years, the way people say their age: born in 1358 makes you 47 for
// all of 1405, whichever side of your birthday today falls. Both arguments
// are in the same calendar, so the answer is the same in either.
function ageFromBirthYear(birthYear, currentYear) {
  var born = parseBirthYear(birthYear, currentYear)
  if (born <= 0) return 0
  return Math.round(Number(currentYear)) - born
}

// 0 means "not set", which is also what a blank, negative, fractional, or
// absurd entry means — the life bar simply stays hidden.
function parseAge(value) {
  var text = toLatinDigits(String(value === undefined || value === null ? "" : value)).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return 0
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 120) return 0
  return years
}

// Unset or nonsense falls back to the default rather than to zero, so the
// bar always has something to measure against.
function parseLifeExpectancy(value) {
  var text = toLatinDigits(String(value === undefined || value === null ? "" : value)).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return DEFAULT_LIFE_EXPECTANCY
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 150) return DEFAULT_LIFE_EXPECTANCY
  return years
}

function lifeProgress(age, expectancy) {
  var years = parseAge(age)
  var span = parseLifeExpectancy(expectancy)
  if (years <= 0 || span <= 0) return 0
  return Math.max(0, Math.min(1, years / span))
}

function lifeProgressPercent(age, expectancy) {
  return Math.round(lifeProgress(age, expectancy) * 100)
}

// The stored birth year is always Gregorian, whichever calendar is on screen,
// so switching the display never silently invalidates a year someone typed --
// 1358 read as a Gregorian year would be six centuries ago and parse to
// "not set".
//
// The conversion is the 621-year offset between the two eras, not a real date
// conversion. A Jalali year straddles two Gregorian ones, so this is wrong by
// up to a year for anyone born between January and Nowruz. That is the right
// trade here: the bar measures a lifetime against a nominal span in whole
// years, and asking for a birth *date* to win back a rounding error nobody
// can see would be a worse widget.
var ERA_OFFSET = 621

function birthYearInCalendar(storedYear, calendar) {
  var year = Math.round(Number(storedYear))
  if (!isFinite(year) || year <= 0) return 0
  return isJalali(calendar) ? year - ERA_OFFSET : year
}

function birthYearToStorage(displayedYear, calendar) {
  var year = Math.round(Number(displayedYear))
  if (!isFinite(year) || year <= 0) return 0
  return isJalali(calendar) ? year + ERA_OFFSET : year
}

// ---- The month grid.
//
// Six rows of seven days, always. A fixed grid keeps the popup exactly the
// same height in every month, so stepping through the year never makes the
// panel jump under the pointer. Six is also always enough in either calendar:
// the longest month is 31 days and the most leading blanks a row can carry
// is six.
//
// `month` is 1-12, the way months are written in both calendars. Only the
// cell *keys* stay Gregorian, always, because that is what the events file is
// written with -- so switching the calendar on screen never disturbs which
// events land on which day.
function monthGrid(calendar, year, month, weekStart, todayKey, eventIndex, options) {
  var opts = options || {}
  var start = normalizedWeekStart(weekStart, defaultWeekStart(calendar))
  var first = toDate(calendar, year, month, 1)
  if (!first) return []

  var leading = (first.getDay() - start + 7) % 7
  var cursor = new Date(first.getFullYear(), first.getMonth(), first.getDate() - leading)
  var today = String(todayKey || "")
  var weeks = []

  // The day a row's week number is taken from. Jalali weeks are owned by
  // their Saturday, ISO weeks by their Thursday.
  var anchorWeekday = isJalali(calendar) ? SATURDAY : 4

  for (var w = 0; w < 6; w++) {
    var days = []
    var anchor = null
    var opener = null

    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getFullYear()
      var cellMonth = cursor.getMonth()
      var cellDay = cursor.getDate()
      var weekday = cursor.getDay()
      var civil = fromDate(calendar, cursor)
      var key = dateKey(cellYear, cellMonth, cellDay)

      if (d === 0) opener = civil
      if (weekday === anchorWeekday) anchor = civil

      days.push({
        key: key,
        civilYear: civil.year,
        civilMonth: civil.month,
        civilDay: civil.day,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: civil.month === Number(month) && civil.year === Number(year),
        weekend: isWeekendDay(calendar, weekday, opts),
        today: key === today,
        hasEvent: eventIndex ? !!eventIndex[key] : false,
        dots: eventIndex ? eventColors(eventIndex, key, 3) : []
      })

      cursor.setDate(cursor.getDate() + 1)
    }

    // Number every row by the week owning its anchor day -- the Saturday of a
    // Jalali week, the Thursday of an ISO one. For a grid started on that
    // calendar's own first day the anchor is the definition itself; for any
    // other start the row straddles two weeks, and the anchor is the only
    // thing that stays stable as the grid is stepped.
    var owner = anchor || opener
    weeks.push({
      week: weekOfYear(calendar, owner.year, owner.month, owner.day),
      days: days
    })
  }

  return weeks
}

// Month arithmetic in the calendar on screen, so stepping from Esfand lands
// on Farvardin of the next year rather than on a Gregorian month that happens
// to overlap it. No calendar argument: both have twelve months, so the same
// modular walk is right for either.
function stepMonth(year, month, delta) {
  var index = (Math.round(Number(year)) * 12) + (Math.round(Number(month)) - 1) + Math.round(Number(delta))
  return {
    year: Math.floor(index / 12),
    month: ((index % 12) + 12) % 12 + 1
  }
}

// ---- Events. The widget renders whatever the sync wrote; none of this knows
//      where the events came from, or that the calendar around them is not
//      the one they were written in.

var STALE_INTERVAL_MULTIPLIER = 4

function indexEventsByDate(events) {
  var index = {}
  if (!events || !events.length) return index
  for (var i = 0; i < events.length; i++) {
    var event = events[i]
    var key = event && event.dateKey
    if (!key) continue
    if (!index[key]) index[key] = []
    index[key].push(event)
  }
  return index
}

function eventsForDateKey(index, key) {
  if (!index || !key) return []
  return index[key] || []
}

// The calendars present in a synced document, in display order, each with
// the colour the sync resolved for it. Derived from the events themselves so
// the widget needs no separate calendar list and no configuration file: it
// can only ever offer you calendars you actually have events in.
function calendarsInDocument(doc) {
  var events = (doc && doc.events) || []
  var byId = {}
  var ordered = []

  for (var i = 0; i < events.length; i++) {
    var event = events[i]
    var id = event && event.calendarId
    if (!id || byId[id]) continue
    byId[id] = true
    ordered.push({
      id: id,
      name: event.calendarName || id,
      color: event.color || ""
    })
  }

  ordered.sort(function(a, b) {
    return a.name.localeCompare(b.name)
  })
  return ordered
}

function isCalendarHidden(hidden, calendarId) {
  if (!hidden || !hidden.length) return false
  return hidden.indexOf(String(calendarId)) !== -1
}

// Returns a new list rather than mutating, so the caller can hand the result
// straight to persistSettings without touching the settings object in place.
function toggleHiddenCalendar(hidden, calendarId) {
  var id = String(calendarId)
  var next = []
  var found = false

  for (var i = 0; i < (hidden || []).length; i++) {
    if (String(hidden[i]) === id) { found = true; continue }
    next.push(hidden[i])
  }

  if (!found) next.push(id)
  return next
}

// Google's "I am working from home" markers arrive as all-day events, so
// without this they eat a line of every single day while describing no
// commitment at all.
var NOISY_EVENT_TYPES = ["workingLocation"]

function isNoisyEventType(event) {
  var type = event && event.eventType
  if (!type) return false
  return NOISY_EVENT_TYPES.indexOf(String(type)) !== -1
}

function isDeclined(event) {
  return !!event && String(event.responseStatus || "") === "declined"
}

function isOutOfOffice(event) {
  return !!event && String(event.eventType || "") === "outOfOffice"
}

// Only https is ever launched. A meeting link is supplied by whoever sent the
// invitation, so treating it as trusted input would be a mistake.
function safeUrl(url) {
  var text = String(url || "").trim()
  if (text.indexOf("https://") !== 0) return ""
  if (/[\s"'<>]/.test(text)) return ""
  return text
}

// Turn the QML file URL of a bundled script into something a person can paste.
// Derived rather than hardcoded: `omarchy plugin add` uses the manifest id, but
// a hand-cloned checkout can live anywhere, and a wrong path in the one message
// a new user sees is worse than no message.
function commandPathFromUrl(fileUrl, home) {
  var text = String(fileUrl || "")
  if (text.indexOf("file://") === 0) text = text.substring(7)
  if (home && text.indexOf(home + "/") === 0) text = "~" + text.substring(home.length)
  return text
}

function meetingUrlFor(event) {
  return event ? safeUrl(event.meetingUrl) : ""
}

// The event's own page, used when there is nothing to join. Older files and
// third-party writers have no such field, which is why this is never assumed.
function eventUrlFor(event) {
  return event ? safeUrl(event.eventUrl) : ""
}

// How long before the start, and after the end, a meeting still counts as
// joinable. A Join button on next Tuesday's meeting is noise that dilutes the
// one that matters, so the affordance only appears around the actual time.
var JOIN_LEAD_MINUTES = 15
var JOIN_GRACE_MINUTES = 15

function isJoinableNow(event, nowMs, todayKey) {
  if (!meetingUrlFor(event)) return false

  // An all-day event has no useful clock window, so it stays joinable for the
  // whole day it belongs to.
  if (event.allDay) return event.dateKey === todayKey

  var startMs = Date.parse(event.start)
  var endMs = Date.parse(event.end)
  if (isNaN(startMs)) return false
  if (isNaN(endMs) || endMs < startMs) endMs = startMs

  var opensAt = startMs - JOIN_LEAD_MINUTES * 60 * 1000
  var closesAt = endMs + JOIN_GRACE_MINUTES * 60 * 1000
  return nowMs >= opensAt && nowMs <= closesAt
}

// `options` is optional so older callers keep working: no options means only
// the calendar filter applies.
function visibleEvents(events, hidden, options) {
  if (!events || !events.length) return []

  var opts = options || {}
  var dropNoisy = opts.hideWorkingLocation !== false
  var dropDeclined = opts.hideDeclined === true

  var visible = []
  for (var i = 0; i < events.length; i++) {
    var event = events[i]
    if (isCalendarHidden(hidden, event.calendarId)) continue
    if (dropNoisy && isNoisyEventType(event)) continue
    if (dropDeclined && isDeclined(event)) continue
    visible.push(event)
  }
  return visible
}

// ---- The next thing coming up.

var MINUTE_MS = 60 * 1000
var HOUR_MS = 60 * MINUTE_MS
var DAY_MS = 24 * HOUR_MS

// All-day events are deliberately excluded. They start at midnight, so a
// countdown to one either reads as hours in the past or as tomorrow, and
// neither tells you anything you wanted to know.
function nextEvent(events, nowMs) {
  var best = null
  var bestMs = null

  for (var i = 0; i < (events || []).length; i++) {
    var event = events[i]
    if (!event || event.allDay) continue

    var startMs = Date.parse(event.start)
    if (isNaN(startMs) || startMs < nowMs) continue

    if (bestMs === null || startMs < bestMs) {
      bestMs = startMs
      best = event
    }
  }

  return best
}

// The popup's "what is next" line is scoped to today on purpose. Something
// eighteen hours out is tomorrow, and answering "what is next" with tomorrow
// is noise when the day's agenda is listed right below it.
function nextEventToday(events, nowMs, todayKey) {
  var todays = []
  for (var i = 0; i < (events || []).length; i++) {
    if (events[i] && events[i].dateKey === todayKey) todays.push(events[i])
  }
  return nextEvent(todays, nowMs)
}

// Returns null past a day out, which is the caller's signal to show nothing
// rather than a countdown nobody is acting on.
//
// Not a translated string but two phrasings, because Persian puts the "from
// now" at the end rather than the front: "۱۰ دقیقه دیگر", never a word-for-
// word "in 10min".
function formatCountdown(deltaMs, options) {
  if (deltaMs === null || isNaN(deltaMs) || deltaMs < 0 || deltaMs >= DAY_MS) return null

  var opts = options || {}
  var calendar = normalizeCalendar(opts.calendar)
  var persian = resolveBoolean(opts.persianDigits, usesPersianDigitsByDefault(calendar))
  var jalali = isJalali(calendar)

  if (deltaMs < MINUTE_MS) return text(calendar, "countdownNow")

  var minutes = Math.floor(deltaMs / MINUTE_MS)
  var phrase

  if (minutes < 60) {
    phrase = jalali ? minutes + " دقیقه دیگر" : "in " + minutes + "min"
  } else {
    var hours = Math.floor(minutes / 60)
    var rest = minutes % 60
    if (jalali) {
      phrase = rest === 0
        ? hours + " ساعت دیگر"
        : hours + " ساعت و " + rest + " دقیقه دیگر"
    } else {
      phrase = rest === 0 ? "in " + hours + "h" : "in " + hours + "h " + rest + "min"
    }
  }

  return persian ? toPersianDigits(phrase) : phrase
}

var MAX_ANNOUNCE_TITLE = 28

// A bar label is a fixed budget of horizontal space shared with every other
// widget, so a long event title has to give.
function truncateTitle(title, limit) {
  var text = String(title === undefined || title === null ? "" : title)
  var max = limit || MAX_ANNOUNCE_TITLE
  if (text.length <= max) return text
  return text.substring(0, max - 1).replace(/\s+$/, "") + "…"
}

// The clock is kept rather than replaced. Giving it up was a real cost for a
// widget whose whole job used to be telling the time, and there is room for
// both.
function announceLabel(clockText, title, countdown, limit) {
  if (!countdown) return clockText
  var shown = truncateTitle(title, limit)
  if (!shown) return clockText
  return clockText + "  ·  " + shown + " " + countdown
}

// How long until an event starts, or null when it cannot be read.
function millisUntil(event, nowMs) {
  if (!event) return null
  var startMs = Date.parse(event.start)
  if (isNaN(startMs)) return null
  return startMs - nowMs
}

// The bar label only gives up the clock when something is close enough to
// act on. Further out it stays a clock, which is what it is most of the day.
function shouldAnnounce(event, nowMs, leadMinutes) {
  var delta = millisUntil(event, nowMs)
  if (delta === null || delta < 0) return false
  return delta <= leadMinutes * MINUTE_MS
}

function eventColors(index, key, limit) {
  var events = eventsForDateKey(index, key)
  var colors = []
  for (var i = 0; i < events.length; i++) {
    var color = events[i].color
    if (!color || colors.indexOf(color) !== -1) continue
    colors.push(color)
    if (limit > 0 && colors.length >= limit) break
  }
  return colors
}

// "missing" means we have nothing to show and should say so rather than
// render an empty calendar that looks like a quiet week.
function syncState(doc, nowMs, intervalSeconds) {
  if (!doc || !doc.syncedAt) return "missing"

  var syncedMs = Date.parse(doc.syncedAt)
  if (isNaN(syncedMs)) return "missing"

  var thresholdMs = intervalSeconds * STALE_INTERVAL_MULTIPLIER * 1000
  return (nowMs - syncedMs) > thresholdMs ? "stale" : "ok"
}

if (typeof module !== "undefined") {
  module.exports = {
    // Jalali arithmetic
    toJalali: toJalali,
    toGregorian: toGregorian,
    jalaliFromDate: jalaliFromDate,
    dateFromJalali: dateFromJalali,
    isLeapJalaliYear: isLeapJalaliYear,
    jalaliMonthLength: jalaliMonthLength,
    jalaliDaysInYear: jalaliDaysInYear,
    jalaliDayOfYear: jalaliDayOfYear,
    jalaliWeek: jalaliWeek,
    JALALI_MONTHS: JALALI_MONTHS,
    WEEKDAYS: WEEKDAYS,
    WEEKDAYS_SHORT: WEEKDAYS_SHORT,

    // Gregorian arithmetic
    isGregorianLeapYear: isGregorianLeapYear,
    gregorianMonthLength: gregorianMonthLength,
    gregorianDaysInYear: gregorianDaysInYear,
    gregorianDayOfYear: gregorianDayOfYear,
    gregorianFromDate: gregorianFromDate,
    dateFromGregorian: dateFromGregorian,
    isoWeek: isoWeek,
    GREGORIAN_MONTHS: GREGORIAN_MONTHS,
    GREGORIAN_WEEKDAYS: GREGORIAN_WEEKDAYS,

    // Choosing between them
    JALALI: JALALI,
    GREGORIAN: GREGORIAN,
    normalizeCalendar: normalizeCalendar,
    isJalali: isJalali,
    otherCalendar: otherCalendar,
    fromDate: fromDate,
    toDate: toDate,
    monthLength: monthLength,
    daysInYear: daysInYear,
    dayOfYear: dayOfYear,
    weekOfYear: weekOfYear,
    defaultWeekStart: defaultWeekStart,
    usesPersianDigitsByDefault: usesPersianDigitsByDefault,
    isRightToLeftByDefault: isRightToLeftByDefault,
    resolveBoolean: resolveBoolean,
    calendarNames: calendarNames,
    monthName: monthName,
    weekdayName: weekdayName,
    weekdayShortName: weekdayShortName,
    text: text,
    stringKeys: stringKeys,
    format: format,
    toPersianDigits: toPersianDigits,
    toLatinDigits: toLatinDigits,
    SATURDAY: SATURDAY,
    FRIDAY: FRIDAY,
    THURSDAY: THURSDAY,
    birthYearInCalendar: birthYearInCalendar,
    birthYearToStorage: birthYearToStorage,

    // Widget model
    dateKey: dateKey,
    keyForDate: keyForDate,
    dateFromKey: dateFromKey,
    normalizedWeekStart: normalizedWeekStart,
    weekStartSettingName: weekStartSettingName,
    toggledWeekStart: toggledWeekStart,
    weekdayOrder: weekdayOrder,
    isWeekendDay: isWeekendDay,
    yearProgress: yearProgress,
    yearProgressPercent: yearProgressPercent,
    parseAge: parseAge,
    parseBirthYear: parseBirthYear,
    ageFromBirthYear: ageFromBirthYear,
    parseLifeExpectancy: parseLifeExpectancy,
    lifeProgress: lifeProgress,
    lifeProgressPercent: lifeProgressPercent,
    monthGrid: monthGrid,
    stepMonth: stepMonth,
    clockFormats: clockFormats,
    clockFormatRing: clockFormatRing,
    nextClockFormat: nextClockFormat,
    indexEventsByDate: indexEventsByDate,
    calendarsInDocument: calendarsInDocument,
    nextEvent: nextEvent,
    nextEventToday: nextEventToday,
    formatCountdown: formatCountdown,
    truncateTitle: truncateTitle,
    announceLabel: announceLabel,
    millisUntil: millisUntil,
    shouldAnnounce: shouldAnnounce,
    isCalendarHidden: isCalendarHidden,
    toggleHiddenCalendar: toggleHiddenCalendar,
    visibleEvents: visibleEvents,
    isNoisyEventType: isNoisyEventType,
    isDeclined: isDeclined,
    isOutOfOffice: isOutOfOffice,
    safeUrl: safeUrl,
    commandPathFromUrl: commandPathFromUrl,
    meetingUrlFor: meetingUrlFor,
    eventUrlFor: eventUrlFor,
    isJoinableNow: isJoinableNow,
    eventsForDateKey: eventsForDateKey,
    eventColors: eventColors,
    syncState: syncState
  }
}
