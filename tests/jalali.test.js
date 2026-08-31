const test = require('node:test')
const assert = require('node:assert')
const Model = require('../Model.js')

// ---- Conversion.
//
// The anchors are dates with an independent public record, not values this
// implementation produced: Nowruz of a handful of years, the 22 Bahman of
// 1357, and the last day of a leap year. An algorithm that agrees with itself
// proves nothing.

const ANCHORS = [
  [1357, 11, 22, 1979, 2, 11],
  [1398, 1, 1, 2019, 3, 21],
  [1399, 12, 30, 2021, 3, 20],
  [1400, 1, 1, 2021, 3, 21],
  [1403, 1, 1, 2024, 3, 20],
  [1404, 1, 1, 2025, 3, 21],
  [1405, 1, 1, 2026, 3, 21],
  [1410, 1, 1, 2031, 3, 21],
  [1300, 1, 1, 1921, 3, 21]
]

test('toGregorian matches known dates', () => {
  for (const [jy, jm, jd, gy, gm, gd] of ANCHORS) {
    assert.deepEqual(Model.toGregorian(jy, jm, jd), { gy, gm, gd },
      `${jy}/${jm}/${jd}`)
  }
})

test('toJalali matches known dates', () => {
  for (const [jy, jm, jd, gy, gm, gd] of ANCHORS) {
    assert.deepEqual(Model.toJalali(gy, gm, gd), { jy, jm, jd },
      `${gy}-${gm}-${gd}`)
  }
})

// Two hundred years, every day, both ways. This is the test that would have
// caught the flooring-versus-truncating division the algorithm depends on:
// a single wrong `div` shifts whole years and still round-trips inside a
// month, so spot checks are not enough.
test('every day from 1900 to 2100 round-trips', () => {
  let cursor = new Date(1900, 0, 1)
  const end = new Date(2100, 0, 1)
  let days = 0

  while (cursor < end) {
    const j = Model.jalaliFromDate(cursor)
    assert.ok(j.jm >= 1 && j.jm <= 12, `month out of range at ${cursor.toDateString()}`)
    assert.ok(j.jd >= 1 && j.jd <= 31, `day out of range at ${cursor.toDateString()}`)

    const back = Model.dateFromJalali(j.jy, j.jm, j.jd)
    assert.equal(back.getFullYear(), cursor.getFullYear())
    assert.equal(back.getMonth(), cursor.getMonth())
    assert.equal(back.getDate(), cursor.getDate())

    days += 1
    cursor = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + 1)
  }

  assert.equal(days, 73049)
})

// ---- Month and year lengths.

test('the first six months are 31 days and the next five are 30', () => {
  for (let m = 1; m <= 6; m++) assert.equal(Model.jalaliMonthLength(1405, m), 31)
  for (let m = 7; m <= 11; m++) assert.equal(Model.jalaliMonthLength(1405, m), 30)
})

test('Esfand is 30 days in a leap year and 29 otherwise', () => {
  assert.equal(Model.jalaliMonthLength(1403, 12), 30)
  assert.equal(Model.jalaliMonthLength(1404, 12), 29)
})

test('jalaliMonthLength refuses a month that does not exist', () => {
  assert.equal(Model.jalaliMonthLength(1405, 0), 0)
  assert.equal(Model.jalaliMonthLength(1405, 13), 0)
})

test('the known leap years in this century are leap', () => {
  // Every year in the 33-year cycle that carries an Esfand 30.
  const leap = [1399, 1403, 1408, 1412, 1416, 1420, 1424, 1428, 1432]
  for (const year of leap) assert.equal(Model.isLeapJalaliYear(year), true, String(year))
  for (const year of [1400, 1401, 1402, 1404, 1405, 1406, 1407]) {
    assert.equal(Model.isLeapJalaliYear(year), false, String(year))
  }
})

test('month lengths add up to the year length', () => {
  for (let jy = 1300; jy <= 1500; jy++) {
    let total = 0
    for (let m = 1; m <= 12; m++) total += Model.jalaliMonthLength(jy, m)
    assert.equal(total, Model.jalaliDaysInYear(jy), String(jy))
  }
})

test('jalaliDayOfYear counts from Farvardin 1', () => {
  assert.equal(Model.jalaliDayOfYear(1405, 1, 1), 1)
  assert.equal(Model.jalaliDayOfYear(1405, 7, 1), 187)
  assert.equal(Model.jalaliDayOfYear(1404, 12, 29), 365)
  assert.equal(Model.jalaliDayOfYear(1403, 12, 30), 366)
})

// ---- Weeks. Week 1 is the week holding Farvardin 1, weeks run Saturday to
//      Friday, and the count restarts at Nowruz. Not ISO: no four-day rule,
//      and the first week is usually a partial one.

test('the week counter restarts at Nowruz', () => {
  assert.equal(Model.jalaliWeek(1405, 1, 1), 1)
  assert.equal(Model.jalaliWeek(1404, 1, 1), 1)
})

test('the week number changes on Saturdays and on no other day', () => {
  // Started in 1399, whose Nowruz falls on a Friday: the year that makes a
  // naive count produce a one-day week 1 and a one-day week 54.
  let cursor = Model.dateFromJalali(1399, 1, 1)
  let previous = null

  for (let i = 0; i < 800; i++) {
    const j = Model.jalaliFromDate(cursor)
    const week = Model.jalaliWeek(j.jy, j.jm, j.jd)

    if (previous !== null) {
      if (cursor.getDay() === Model.SATURDAY) {
        assert.notEqual(week, previous, `${j.jy}/${j.jm}/${j.jd} did not open a new week`)
      } else {
        assert.equal(week, previous, `${j.jy}/${j.jm}/${j.jd} changed week mid-week`)
      }
    }

    previous = week
    cursor = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + 1)
  }
})

test('no Jalali year is ever numbered past 53 weeks', () => {
  for (let jy = 1350; jy <= 1450; jy++) {
    let highest = 0
    let cursor = Model.dateFromJalali(jy, 1, 1)
    for (let i = 0; i < Model.jalaliDaysInYear(jy); i++) {
      const j = Model.jalaliFromDate(cursor)
      highest = Math.max(highest, Model.jalaliWeek(j.jy, j.jm, j.jd))
      cursor = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + 1)
    }
    assert.ok(highest === 52 || highest === 53, `${jy} reaches week ${highest}`)
  }
})

// ---- Names.

test('month and weekday names are the Persian ones', () => {
  assert.equal(Model.monthName(Model.JALALI, 1), 'فروردین')
  assert.equal(Model.monthName(Model.JALALI, 12), 'اسفند')
  assert.equal(Model.monthName(Model.JALALI, 0), '')
  assert.equal(Model.monthName(Model.JALALI, 13), '')

  // Indexed by JS Date.getDay(), so 6 is Saturday and 0 is Sunday.
  assert.equal(Model.weekdayName(Model.JALALI, Model.SATURDAY), 'شنبه')
  assert.equal(Model.weekdayName(Model.JALALI, 0), 'یکشنبه')
  assert.equal(Model.weekdayName(Model.JALALI, Model.FRIDAY), 'جمعه')
  assert.equal(Model.weekdayShortName(Model.JALALI, Model.SATURDAY), 'ش')
})

test('the weekday tables are indexed the way a JS Date reports its day', () => {
  const cursor = new Date(2026, 7, 31) // a Monday
  assert.equal(cursor.getDay(), 1)
  assert.equal(Model.weekdayName(Model.JALALI, cursor.getDay()), 'دوشنبه')
})

// ---- Digits.

test('toPersianDigits converts only the digits', () => {
  assert.equal(Model.toPersianDigits('1405/06/09'), '۱۴۰۵/۰۶/۰۹')
  assert.equal(Model.toPersianDigits('W12 x'), 'W۱۲ x')
  assert.equal(Model.toPersianDigits(1405), '۱۴۰۵')
  assert.equal(Model.toPersianDigits(null), '')
})

test('toLatinDigits accepts both Persian and Arabic-Indic digits', () => {
  assert.equal(Model.toLatinDigits('۱۳۵۸'), '1358')
  assert.equal(Model.toLatinDigits('١٣٥٨'), '1358')
  assert.equal(Model.toLatinDigits('1358'), '1358')
  assert.equal(Model.toLatinDigits(null), '')
})

test('a birth year typed in Persian digits parses', () => {
  assert.equal(Model.parseBirthYear('۱۳۵۸', 1405), 1358)
  assert.equal(Model.parseBirthYear('1358', 1405), 1358)
  assert.equal(Model.parseBirthYear('۱۴۰۶', 1405), 0, 'a year in the future is not a birth year')
  assert.equal(Model.parseBirthYear('۱۲۰۰', 1405), 0, 'and neither is one 200 years back')
  assert.equal(Model.parseLifeExpectancy('۸۵'), 85)
})

// ---- Formatting.

const NOON = new Date(2026, 7, 31, 14, 5, 9) // 1405/06/09, a Monday

test('format renders the Qt tokens against the Jalali calendar', () => {
  assert.equal(Model.format(NOON, 'yyyy/MM/dd'), '۱۴۰۵/۰۶/۰۹')
  assert.equal(Model.format(NOON, 'dddd d MMMM yyyy'), 'دوشنبه ۹ شهریور ۱۴۰۵')
  assert.equal(Model.format(NOON, 'ddd'), 'د')
  assert.equal(Model.format(NOON, 'yy'), '۰۵')
  assert.equal(Model.format(NOON, 'M/d'), '۶/۹')
})

test('format renders time separately from the calendar', () => {
  assert.equal(Model.format(NOON, 'HH:mm:ss'), '۱۴:۰۵:۰۹')
  assert.equal(Model.format(NOON, 'h:mm AP'), '۲:۰۵ ب.ظ')
  assert.equal(Model.format(new Date(2026, 7, 31, 0, 5), 'h:mm AP'), '۱۲:۰۵ ق.ظ')
  assert.equal(Model.format(new Date(2026, 7, 31, 12, 0), 'h:mm AP'), '۱۲:۰۰ ب.ظ')
})

test('format can be asked for Latin digits', () => {
  assert.equal(Model.format(NOON, 'yyyy/MM/dd', { persianDigits: false }), '1405/06/09')
  assert.equal(Model.format(NOON, 'dddd d MMMM', { persianDigits: false }), 'دوشنبه 9 شهریور')
})

test('format treats a quoted run as a literal', () => {
  assert.equal(Model.format(NOON, "'هفته'ww"), 'هفته۲۴')
  assert.equal(Model.format(NOON, "'d' d"), 'd ۹')
  // Two quotes are a literal quote, inside a run and outside one.
  assert.equal(Model.format(NOON, "''yy"), "'۰۵")
  assert.equal(Model.format(NOON, "'it''s' d"), "it's ۹")
})

test('format leaves unknown characters alone', () => {
  assert.equal(Model.format(NOON, '— '), '— ')
  assert.equal(Model.format(NOON, ''), '')
  assert.equal(Model.format(NOON, null), '')
})

test('format spans a newline, which is what the vertical bar is built from', () => {
  assert.equal(Model.format(NOON, 'HH\n—\nmm'), '۱۴\n—\n۰۵')
})
