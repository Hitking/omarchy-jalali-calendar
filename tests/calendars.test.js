const test = require('node:test')
const assert = require('node:assert')
const Model = require('../Model.js')

// 2026-08-31 is a Monday. In Jalali it is 1405/06/09, in Gregorian 2026/08/31.
// Every test below uses that one instant, so what changes between the two
// columns is only ever the calendar.
const NOON = new Date(2026, 7, 31, 14, 5, 9)
const G = { calendar: Model.GREGORIAN }
const J = { calendar: Model.JALALI }

test('normalizeCalendar accepts what a hand-edited config might hold', () => {
  assert.equal(Model.normalizeCalendar('gregorian'), Model.GREGORIAN)
  assert.equal(Model.normalizeCalendar('Gregorian'), Model.GREGORIAN)
  assert.equal(Model.normalizeCalendar(' miladi '), Model.GREGORIAN)
  assert.equal(Model.normalizeCalendar('jalali'), Model.JALALI)

  // Anything unrecognised is the calendar this plugin is for, not an error.
  assert.equal(Model.normalizeCalendar(''), Model.JALALI)
  assert.equal(Model.normalizeCalendar(null), Model.JALALI)
  assert.equal(Model.normalizeCalendar('nonsense'), Model.JALALI)
})

test('otherCalendar flips, and flipping twice returns', () => {
  assert.equal(Model.otherCalendar(Model.JALALI), Model.GREGORIAN)
  assert.equal(Model.otherCalendar(Model.GREGORIAN), Model.JALALI)
  assert.equal(Model.otherCalendar(Model.otherCalendar(Model.JALALI)), Model.JALALI)
})

test('the same instant names a different day in each calendar', () => {
  assert.deepEqual(Model.fromDate(Model.JALALI, NOON), { year: 1405, month: 6, day: 9 })
  assert.deepEqual(Model.fromDate(Model.GREGORIAN, NOON), { year: 2026, month: 8, day: 31 })
})

test('toDate is the inverse of fromDate in both', () => {
  for (const calendar of [Model.JALALI, Model.GREGORIAN]) {
    const civil = Model.fromDate(calendar, NOON)
    const back = Model.toDate(calendar, civil.year, civil.month, civil.day)
    assert.equal(back.getFullYear(), 2026)
    assert.equal(back.getMonth(), 7)
    assert.equal(back.getDate(), 31)
  }
})

test('month lengths and year lengths follow the calendar', () => {
  assert.equal(Model.monthLength(Model.JALALI, 1403, 12), 30)
  assert.equal(Model.monthLength(Model.GREGORIAN, 2024, 2), 29)
  assert.equal(Model.monthLength(Model.GREGORIAN, 2026, 2), 28)
  assert.equal(Model.daysInYear(Model.JALALI, 1403), 366)
  assert.equal(Model.daysInYear(Model.GREGORIAN, 2024), 366)
  assert.equal(Model.daysInYear(Model.GREGORIAN, 2026), 365)
})

// Two genuinely different definitions, not one with the names swapped: the
// Jalali count restarts at Nowruz and runs Saturday to Friday with no
// four-day rule, ISO restarts in January and runs Monday to Sunday with one.
test('week numbering is the calendar\'s own, not a relabelling', () => {
  assert.equal(Model.weekOfYear(Model.JALALI, 1405, 6, 9), 24)
  assert.equal(Model.weekOfYear(Model.GREGORIAN, 2026, 8, 31), 36)
})

test('the week opens and the weekend falls where the calendar says', () => {
  assert.equal(Model.defaultWeekStart(Model.JALALI), Model.SATURDAY)
  assert.equal(Model.defaultWeekStart(Model.GREGORIAN), 1)

  assert.equal(Model.isWeekendDay(Model.JALALI, Model.FRIDAY), true)
  assert.equal(Model.isWeekendDay(Model.JALALI, 0), false, 'Sunday is a working day in Iran')
  assert.equal(Model.isWeekendDay(Model.JALALI, Model.SATURDAY), false)

  assert.equal(Model.isWeekendDay(Model.GREGORIAN, 0), true)
  assert.equal(Model.isWeekendDay(Model.GREGORIAN, Model.SATURDAY), true)
  assert.equal(Model.isWeekendDay(Model.GREGORIAN, Model.FRIDAY), false)
})

test('Thursday is an option under Jalali and ignored under Gregorian', () => {
  const opts = { thursdayWeekend: true }
  assert.equal(Model.isWeekendDay(Model.JALALI, Model.THURSDAY, opts), true)
  assert.equal(Model.isWeekendDay(Model.JALALI, Model.THURSDAY), false)
  assert.equal(Model.isWeekendDay(Model.GREGORIAN, Model.THURSDAY, opts), false)
})

test('digits and reading direction default off the calendar', () => {
  assert.equal(Model.usesPersianDigitsByDefault(Model.JALALI), true)
  assert.equal(Model.usesPersianDigitsByDefault(Model.GREGORIAN), false)
  assert.equal(Model.isRightToLeftByDefault(Model.JALALI), true)
  assert.equal(Model.isRightToLeftByDefault(Model.GREGORIAN), false)
})

// An unset setting follows the calendar so a switch moves everything that
// ought to move; an explicit choice survives the switch, because a deliberate
// setting is not something a display toggle gets to undo.
test('resolveBoolean lets the calendar decide only when nothing was chosen', () => {
  assert.equal(Model.resolveBoolean(undefined, true), true)
  assert.equal(Model.resolveBoolean(null, false), false)
  assert.equal(Model.resolveBoolean(true, false), true)
  assert.equal(Model.resolveBoolean(false, true), false)
  // shell.json is hand-edited, and a quoted boolean is what that produces.
  assert.equal(Model.resolveBoolean('true', false), true)
  assert.equal(Model.resolveBoolean('false', true), false)
})

test('format resolves the same tokens against either calendar', () => {
  assert.equal(Model.format(NOON, 'dddd d MMMM yyyy', J), 'دوشنبه ۹ شهریور ۱۴۰۵')
  assert.equal(Model.format(NOON, 'dddd d MMMM yyyy', G), 'Monday 31 August 2026')
  assert.equal(Model.format(NOON, 'ddd d MMM', G), 'MON 31 Aug')
  assert.equal(Model.format(NOON, "'W'ww", G), 'W36')
  assert.equal(Model.format(NOON, "'W'ww", J), 'W۲۴')
})

test('the meridiem is written the way each calendar writes it', () => {
  assert.equal(Model.format(NOON, 'h:mm AP', J), '۲:۰۵ ب.ظ')
  assert.equal(Model.format(NOON, 'h:mm AP', G), '2:05 PM')
  assert.equal(Model.format(new Date(2026, 7, 31, 9, 0), 'h:mm AP', G), '9:00 AM')
})

// Model.js stays locale-free so it stays testable. Gregorian month and day
// names come from Qt's locale in the panel and arrive here as an override,
// which is how a French desktop keeps reading French.
test('locale names override the built-in ones', () => {
  const names = {
    months: ['janvier', 'février', 'mars', 'avril', 'mai', 'juin',
             'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'],
    weekdays: ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi']
  }
  assert.equal(
    Model.format(NOON, 'dddd d MMMM', { calendar: Model.GREGORIAN, names: names }),
    'lundi 31 août')
})

test('an override of the wrong length is ignored rather than trusted', () => {
  const short = { months: ['Jan', 'Feb'], weekdays: ['Sun'] }
  assert.equal(
    Model.format(NOON, 'dddd d MMMM', { calendar: Model.GREGORIAN, names: short }),
    'Monday 31 August')
})

test('digits can be forced against the calendar in both directions', () => {
  assert.equal(Model.format(NOON, 'yyyy', { calendar: Model.JALALI, persianDigits: false }), '1405')
  assert.equal(Model.format(NOON, 'yyyy', { calendar: Model.GREGORIAN, persianDigits: true }), '۲۰۲۶')
})

test('the format ring is the one that belongs to the calendar', () => {
  const jalali = Model.clockFormats(false, Model.JALALI)
  const gregorian = Model.clockFormats(false, Model.GREGORIAN)
  assert.ok(jalali.indexOf('yyyy/MM/dd HH:mm') !== -1, 'Jalali dates are written with slashes')
  assert.ok(gregorian.indexOf('yyyy-MM-dd HH:mm') !== -1, 'ISO 8601 is a Gregorian form')
  assert.ok(gregorian.indexOf("d MMMM 'W'ww yyyy") !== -1, 'the built-in clock offered a W preset')
  assert.notDeepEqual(jalali, gregorian)
  assert.equal(Model.clockFormats(true, Model.JALALI).length, 4)
})

test('the interface language follows the calendar', () => {
  assert.equal(Model.text(Model.JALALI, 'join'), 'پیوستن')
  assert.equal(Model.text(Model.GREGORIAN, 'join'), 'Join')
  assert.equal(Model.text(Model.GREGORIAN, 'nothingScheduled'), 'Nothing scheduled')
  assert.equal(Model.text(Model.JALALI, 'noSuchKey'), '')
})

// Every key one table has, the other must have too. A missing one renders as
// an empty label -- a blank button rather than a crash -- so nothing else
// would catch it.
test('the two string tables carry exactly the same keys', () => {
  assert.deepEqual(Model.stringKeys(Model.JALALI), Model.stringKeys(Model.GREGORIAN))
  assert.ok(Model.stringKeys(Model.JALALI).length > 40, 'the tables are not empty')
})

test('every string in both tables is non-empty', () => {
  for (const calendar of [Model.JALALI, Model.GREGORIAN]) {
    for (const key of Model.stringKeys(calendar)) {
      assert.notEqual(Model.text(calendar, key), '', `${calendar} has a blank ${key}`)
    }
  }
})

// The grid is where a half-finished switch would show first: a Gregorian
// month laid out on Jalali week boundaries, or vice versa.
test('the grid is laid out in the calendar it was asked for', () => {
  const jalali = Model.monthGrid(Model.JALALI, 1405, 6, Model.SATURDAY, '2026-08-31', {})
  const gregorian = Model.monthGrid(Model.GREGORIAN, 2026, 8, 1, '2026-08-31', {})

  assert.equal(jalali[0].days[0].weekday, Model.SATURDAY)
  assert.equal(gregorian[0].days[0].weekday, 1)

  assert.deepEqual(jalali.map(w => w.week), [23, 24, 25, 26, 27, 28])
  assert.deepEqual(gregorian.map(w => w.week), [31, 32, 33, 34, 35, 36])

  // The same real day, found by the same key, in both grids.
  const inJalali = jalali.flatMap(w => w.days).find(d => d.key === '2026-08-31')
  const inGregorian = gregorian.flatMap(w => w.days).find(d => d.key === '2026-08-31')
  assert.equal(inJalali.civilDay, 9)
  assert.equal(inGregorian.civilDay, 31)
  assert.ok(inJalali.today && inGregorian.today)
  assert.ok(inJalali.inMonth && inGregorian.inMonth)
})

// This is the property the whole design rests on. Events are filed under
// Gregorian keys and the calendar is only a way of naming days, so switching
// it must not move a single event.
test('switching the calendar never moves an event', () => {
  const events = [
    { id: 'a', dateKey: '2026-08-31', color: '#f83a22', calendarId: 'w' },
    { id: 'b', dateKey: '2026-09-01', color: '#7bd148', calendarId: 'w' }
  ]
  const index = Model.indexEventsByDate(events)

  const jalali = Model.monthGrid(Model.JALALI, 1405, 6, Model.SATURDAY, '', index)
  const gregorian = Model.monthGrid(Model.GREGORIAN, 2026, 8, 1, '', index)

  const marked = grid => grid.flatMap(w => w.days).filter(d => d.hasEvent).map(d => d.key).sort()
  assert.deepEqual(marked(jalali), ['2026-08-31', '2026-09-01'])
  assert.deepEqual(marked(gregorian), ['2026-08-31', '2026-09-01'])
})

// Stored Gregorian, entered and shown in whichever calendar is on screen, so
// flipping the calendar does not turn 1358 into "not set".
test('a birth year survives a calendar switch', () => {
  const stored = Model.birthYearToStorage(1358, Model.JALALI)
  assert.equal(stored, 1979)
  assert.equal(Model.birthYearInCalendar(stored, Model.JALALI), 1358)
  assert.equal(Model.birthYearInCalendar(stored, Model.GREGORIAN), 1979)

  // And the age comes out the same either way, which is the only number the
  // bar actually draws.
  assert.equal(Model.ageFromBirthYear(1358, 1405), 47)
  assert.equal(Model.ageFromBirthYear(1979, 2026), 47)
})

test('an unset birth year stays unset through the conversion', () => {
  assert.equal(Model.birthYearToStorage(0, Model.JALALI), 0)
  assert.equal(Model.birthYearInCalendar(0, Model.JALALI), 0)
  assert.equal(Model.birthYearInCalendar(null, Model.GREGORIAN), 0)
})
