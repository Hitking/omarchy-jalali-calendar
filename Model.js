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

function monthName(jm) {
  var index = Math.round(Number(jm)) - 1
  return JALALI_MONTHS[index] || ""
}

function weekdayName(weekday) {
  return WEEKDAYS[((Math.round(Number(weekday)) % 7) + 7) % 7] || ""
}

function weekdayShortName(weekday) {
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

// ---- Bidirectional text.
//
// A Latin run inside a Persian paragraph is reordered by the bidi algorithm
// unless it is isolated, and the damage is not cosmetic: a leading "~/" is
// weak-directional, so it migrates to the far end and the one command a new
// user is told to paste comes out as "config/.../setup./~". An isolate says
// "this run has its own direction" without changing the paragraph around it.
var LTR_ISOLATE = "\u2066"
var POP_ISOLATE = "\u2069"

function ltrIsolate(text) {
  var value = String(text === undefined || text === null ? "" : text)
  return value === "" ? "" : LTR_ISOLATE + value + POP_ISOLATE
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

// ---- Formatting.
//
// Qt's format tokens, so a format string written for the upstream clock keeps
// meaning what it meant -- MMMM is still the month name, it is just a Jalali
// one now. Implemented here rather than handed to Qt.formatDateTime because
// Qt has no Jalali calendar and would answer in Gregorian.

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
    case "yyyy": return String(parts.jy)
    case "yy": return pad2(parts.jy % 100)
    case "MMMM": return monthName(parts.jm)
    // Persian month names have no accepted abbreviation, so the short form is
    // the long one. Inventing "فرو" would only make the grid harder to read.
    case "MMM": return monthName(parts.jm)
    case "MM": return pad2(parts.jm)
    case "M": return String(parts.jm)
    case "dddd": return weekdayName(parts.weekday)
    case "ddd": return weekdayShortName(parts.weekday)
    case "dd": return pad2(parts.jd)
    case "d": return String(parts.jd)
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
    case "A": return parts.hours < 12 ? "ق.ظ" : "ب.ظ"
    case "ap":
    case "a": return parts.hours < 12 ? "ق.ظ" : "ب.ظ"
    default: return token
  }
}

function dateParts(date) {
  var jalali = jalaliFromDate(date)
  if (!jalali) return null
  var hours = date.getHours()
  return {
    jy: jalali.jy,
    jm: jalali.jm,
    jd: jalali.jd,
    weekday: date.getDay(),
    hours: hours,
    hours12: (hours % 12) === 0 ? 12 : (hours % 12),
    minutes: date.getMinutes(),
    seconds: date.getSeconds(),
    week: jalaliWeek(jalali.jy, jalali.jm, jalali.jd)
  }
}

// Single quotes escape a literal run, and '' is a literal quote, both inside
// and outside a run -- Qt's rules, so "'هفته'ww" and "''yy" keep working.
function format(date, pattern, persianDigits) {
  var parts = dateParts(date)
  if (!parts) return ""

  var text = String(pattern === undefined || pattern === null ? "" : pattern)
  var out = ""
  var i = 0

  while (i < text.length) {
    var ch = text.charAt(i)

    if (ch === "'") {
      if (text.charAt(i + 1) === "'") { out += "'"; i += 2; continue }
      i += 1
      while (i < text.length) {
        if (text.charAt(i) === "'") {
          if (text.charAt(i + 1) === "'") { out += "'"; i += 2; continue }
          i += 1
          break
        }
        out += text.charAt(i)
        i += 1
      }
      continue
    }

    var matched = ""
    for (var t = 0; t < TOKENS.length; t++) {
      var token = TOKENS[t]
      if (text.substr(i, token.length) === token) { matched = token; break }
    }

    if (matched === "") { out += ch; i += 1; continue }
    out += tokenValue(matched, parts)
    i += matched.length
  }

  return persianDigits === false ? out : toPersianDigits(out)
}

// ============================================================================
// Section 2 -- The widget's own model
// ============================================================================

var MS_PER_DAY = 86400000

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
var CLOCK_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "HH:mm",
  "h:mm AP",
  "d MMMM HH:mm",
  "d MMMM h:mm AP",
  "dddd d MMMM yyyy",
  "yyyy/MM/dd HH:mm"
]

// Vertical bars have room for a few stacked lines and nothing else, so the
// ring stays short. AM/PM costs a fourth line, which is why only the plain
// time carries it here.
var VERTICAL_CLOCK_FORMATS = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\nyy",
  "HH\nmm"
]

function clockFormats(vertical) {
  return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice()
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

// Configured week start, falling back to Saturday. Unlike the upstream clock
// this does not defer to Qt's locale: a Jalali calendar whose week started on
// Monday because the desktop is in en_US would be wrong in the one way this
// widget exists to fix.
function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value)
  if (configured !== null) return configured
  var fallbackStart = coerceWeekStart(fallback)
  return fallbackStart === null ? SATURDAY : fallbackStart
}

function weekStartSettingName(index) {
  return WEEKDAY_NAMES[normalizedWeekStart(index, SATURDAY)]
}

// Saturday is the Iranian week; Monday is the one people who also live in a
// work calendar with the rest of the world reach for. Those are the two worth
// a one-click toggle, and a calendar configured to anything else is shown as
// it is and lands on Saturday the first time it is toggled.
function toggledWeekStart(index) {
  return normalizedWeekStart(index, SATURDAY) === SATURDAY ? 1 : SATURDAY
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, SATURDAY)
  var out = []
  for (var i = 0; i < 7; i++) out.push((start + i) % 7)
  return out
}

// Friday is the weekend. Thursday is optional because whether it is a working
// day is a real disagreement in Iran rather than a preference: banks and
// schools are shut, plenty of private offices are not.
function isWeekendDay(weekday, thursdayOff) {
  var day = ((Math.round(Number(weekday)) % 7) + 7) % 7
  if (day === FRIDAY) return true
  return thursdayOff === true && day === THURSDAY
}

// ---- Year progress, measured on the Jalali year: Farvardin 1 reads 0% and
//      Esfand 29 reads 100%, which is what a year ending at Nowruz means.

function yearProgress(jy, jm, jd) {
  var total = jalaliDaysInYear(jy)
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, (jalaliDayOfYear(jy, jm, jd) - 1) / total))
}

function yearProgressPercent(jy, jm, jd) {
  return Math.round(yearProgress(jy, jm, jd) * 100)
}

// Memento mori. The default span is a round number rather than anything from
// an actuarial table: the point of the bar is the reminder, not the
// arithmetic, and whoever wants a different number can say so.
var DEFAULT_LIFE_EXPECTANCY = 90

// A birth year rather than an age, so the bar keeps counting on its own
// instead of going stale the moment it is entered. A Jalali year, because it
// is the year an Iranian knows their own birth by. 0 means "not set", which
// is also what a blank, malformed, future, or implausibly distant year means.
// Persian digits are accepted: the field is typed into with a Persian
// keyboard as often as not.
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
// all of 1405, whichever side of your birthday today falls.
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

// ---- The month grid.
//
// Six rows of seven days, always. A fixed grid keeps the popup exactly the
// same height in every month, so stepping through the year never makes the
// panel jump under the pointer. Six is also always enough: the longest Jalali
// month is 31 days and the most leading blanks a row can carry is six.
//
// `jm` is 1-12, the way Jalali months are written everywhere. Only the cell
// keys stay Gregorian, because that is what the events are filed under.
function monthGrid(jy, jm, weekStart, todayKey, eventIndex, options) {
  var opts = options || {}
  var start = normalizedWeekStart(weekStart, SATURDAY)
  var first = dateFromJalali(jy, jm, 1)
  if (!first) return []

  var leading = (first.getDay() - start + 7) % 7
  var cursor = new Date(first.getFullYear(), first.getMonth(), first.getDate() - leading)
  var today = String(todayKey || "")
  var weeks = []

  for (var w = 0; w < 6; w++) {
    var days = []
    var saturday = null

    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getFullYear()
      var cellMonth = cursor.getMonth()
      var cellDay = cursor.getDate()
      var weekday = cursor.getDay()
      var jalali = toJalali(cellYear, cellMonth + 1, cellDay)
      var key = dateKey(cellYear, cellMonth, cellDay)

      if (weekday === SATURDAY) saturday = jalali

      days.push({
        key: key,
        jy: jalali.jy,
        jm: jalali.jm,
        jd: jalali.jd,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: jalali.jm === Number(jm) && jalali.jy === Number(jy),
        weekend: isWeekendDay(weekday, opts.thursdayWeekend),
        today: key === today,
        hasEvent: eventIndex ? !!eventIndex[key] : false,
        dots: eventIndex ? eventColors(eventIndex, key, 3) : []
      })

      cursor.setDate(cursor.getDate() + 1)
    }

    // Number every row by the Jalali week owning its Saturday. For a
    // Saturday-start grid that is the row's own first cell, which is the
    // definition; for any other start the row straddles two weeks and the
    // Saturday is the only anchor that stays stable as the grid is stepped.
    var anchor = saturday || days[0]
    weeks.push({
      week: jalaliWeek(anchor.jy, anchor.jm, anchor.jd),
      days: days
    })
  }

  return weeks
}

// Jalali month arithmetic, so stepping from Esfand lands on Farvardin of the
// next year rather than on a Gregorian month that happens to overlap it.
function stepMonth(jy, jm, delta) {
  var index = (Math.round(Number(jy)) * 12) + (Math.round(Number(jm)) - 1) + Math.round(Number(delta))
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
// Persian puts the "from now" at the end rather than the front, so these are
// built as "۱۰ دقیقه دیگر" and not as a translated "in 10min".
function formatCountdown(deltaMs, persianDigits) {
  if (deltaMs === null || isNaN(deltaMs) || deltaMs < 0 || deltaMs >= DAY_MS) return null

  var digits = persianDigits !== false
  if (deltaMs < MINUTE_MS) return "هم‌اکنون"

  var minutes = Math.floor(deltaMs / MINUTE_MS)
  var text
  if (minutes < 60) {
    text = minutes + " دقیقه دیگر"
  } else {
    var hours = Math.floor(minutes / 60)
    var rest = minutes % 60
    text = rest === 0
      ? hours + " ساعت دیگر"
      : hours + " ساعت و " + rest + " دقیقه دیگر"
  }

  return digits ? toPersianDigits(text) : text
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
  // The title is isolated because it is not ours: an invitation written in
  // Latin script, dropped unisolated between a Persian clock and a Persian
  // countdown, drags the countdown to the wrong side of the label.
  return clockText + "  ·  " + ltrIsolate(shown) + " " + countdown
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
    monthName: monthName,
    weekdayName: weekdayName,
    weekdayShortName: weekdayShortName,
    toPersianDigits: toPersianDigits,
    toLatinDigits: toLatinDigits,
    ltrIsolate: ltrIsolate,
    format: format,
    JALALI_MONTHS: JALALI_MONTHS,
    WEEKDAYS: WEEKDAYS,
    WEEKDAYS_SHORT: WEEKDAYS_SHORT,
    SATURDAY: SATURDAY,
    FRIDAY: FRIDAY,
    THURSDAY: THURSDAY,

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
