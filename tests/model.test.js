const test = require('node:test')
const assert = require('node:assert')
const Model = require('../Model.js')

const EVENTS = [
  { id: 'a', dateKey: '2026-08-10', title: 'Standup', color: '#f83a22', start: '2026-08-10T09:00:00-05:00' },
  { id: 'b', dateKey: '2026-08-10', title: 'Lunch', color: '#7bd148', start: '2026-08-10T12:00:00-05:00' },
  { id: 'c', dateKey: '2026-08-10', title: 'Retro', color: '#f83a22', start: '2026-08-10T16:00:00-05:00' },
  { id: 'd', dateKey: '2026-08-12', title: 'Dentist', color: '#ffad46', start: '2026-08-12T10:00:00-05:00' }
]

test('indexEventsByDate groups by dateKey', () => {
  const index = Model.indexEventsByDate(EVENTS)
  assert.equal(index['2026-08-10'].length, 3)
  assert.equal(index['2026-08-12'].length, 1)
  assert.equal(index['2026-08-11'], undefined)
})

test('indexEventsByDate tolerates an empty list', () => {
  assert.deepEqual(Model.indexEventsByDate([]), {})
})

test('indexEventsByDate tolerates null', () => {
  assert.deepEqual(Model.indexEventsByDate(null), {})
})

test('eventsForDateKey returns an empty array for an unknown day', () => {
  const index = Model.indexEventsByDate(EVENTS)
  assert.deepEqual(Model.eventsForDateKey(index, '2026-01-01'), [])
})

test('eventColors dedupes and preserves first-seen order', () => {
  const index = Model.indexEventsByDate(EVENTS)
  assert.deepEqual(Model.eventColors(index, '2026-08-10', 5), ['#f83a22', '#7bd148'])
})

test('eventColors respects the limit', () => {
  const index = Model.indexEventsByDate(EVENTS)
  assert.deepEqual(Model.eventColors(index, '2026-08-10', 1), ['#f83a22'])
})

// monthGrid takes a Jalali year and a 1-based Jalali month, and returns an
// array of 6 week objects, each { week, days }. 2026-08-10 is 1405-05-19,
// which is Mordad, the fifth month.
const MORDAD = [1405, 5]

test('monthGrid is always six rows of seven days', () => {
  const weeks = Model.monthGrid(MORDAD[0], MORDAD[1], Model.SATURDAY, '2026-08-10')
  assert.equal(weeks.length, 6)
  const cells = weeks.flatMap(week => week.days)
  assert.equal(cells.length, 42)
  assert.ok(cells.every(cell => cell.hasEvent === false))
  assert.ok(cells.every(cell => Array.isArray(cell.dots) && cell.dots.length === 0))
})

test('monthGrid marks days that have events', () => {
  const index = Model.indexEventsByDate(EVENTS)
  const cells = Model.monthGrid(MORDAD[0], MORDAD[1], Model.SATURDAY, '2026-08-10', index)
    .flatMap(week => week.days)
  const tenth = cells.find(cell => cell.key === '2026-08-10')
  const eleventh = cells.find(cell => cell.key === '2026-08-11')
  assert.equal(tenth.hasEvent, true)
  assert.deepEqual(tenth.dots, ['#f83a22', '#7bd148'])
  assert.equal(eleventh.hasEvent, false)
})

// The cell keeps its Gregorian identity alongside the Jalali one: the key is
// what events are filed under, and losing it would decouple the grid from the
// only data it renders.
test('monthGrid cells carry both calendars', () => {
  const cells = Model.monthGrid(MORDAD[0], MORDAD[1], Model.SATURDAY, '2026-08-10')
    .flatMap(week => week.days)
  const tenth = cells.find(cell => cell.key === '2026-08-10')
  assert.equal(tenth.day, 10)
  assert.equal(tenth.month, 7)
  assert.equal(tenth.year, 2026)
  assert.equal(tenth.jy, 1405)
  assert.equal(tenth.jm, 5)
  assert.equal(tenth.jd, 19)
  assert.equal(tenth.inMonth, true)
  assert.equal(tenth.today, true)
})

test('monthGrid pads the first row with the tail of the previous month', () => {
  // Mordad 1405 opens on a Thursday, which under a Saturday-start week is
  // the sixth column, so five days of Tir lead the grid in.
  const first = Model.monthGrid(1405, 5, Model.SATURDAY, '')[0].days
  const leading = first.filter(cell => !cell.inMonth)
  assert.equal(leading.length, 5)
  assert.ok(leading.every(cell => cell.jm === 4 && cell.jy === 1405))
  assert.equal(first[0].weekday, Model.SATURDAY)
  assert.equal(first[5].jd, 1)
  assert.equal(first[5].jm, 5)
})

test('monthGrid opens every row on the configured week start', () => {
  for (const start of [Model.SATURDAY, 0, 1]) {
    for (const week of Model.monthGrid(1405, 5, start, '')) {
      assert.equal(week.days[0].weekday, start)
    }
  }
})

test('monthGrid covers every day of a 31-day month', () => {
  const days = Model.monthGrid(1405, 1, Model.SATURDAY, '')
    .flatMap(week => week.days)
    .filter(cell => cell.inMonth)
    .map(cell => cell.jd)
  assert.deepEqual(days, Array.from({ length: 31 }, (_, i) => i + 1))
})

test('monthGrid covers a 30-day Esfand in a leap year and a 29-day one otherwise', () => {
  const leap = Model.monthGrid(1403, 12, Model.SATURDAY, '').flatMap(w => w.days).filter(c => c.inMonth)
  const plain = Model.monthGrid(1404, 12, Model.SATURDAY, '').flatMap(w => w.days).filter(c => c.inMonth)
  assert.equal(leap.length, 30)
  assert.equal(plain.length, 29)
})

test('monthGrid marks Friday as the weekend, and Thursday only when asked', () => {
  const cells = Model.monthGrid(1405, 5, Model.SATURDAY, '').flatMap(w => w.days)
  const friday = cells.find(cell => cell.weekday === Model.FRIDAY)
  const thursday = cells.find(cell => cell.weekday === Model.THURSDAY)
  assert.equal(friday.weekend, true)
  assert.equal(thursday.weekend, false)

  const withThursday = Model.monthGrid(1405, 5, Model.SATURDAY, '', null, { thursdayWeekend: true })
    .flatMap(w => w.days)
  assert.equal(withThursday.find(cell => cell.weekday === Model.THURSDAY).weekend, true)
  assert.equal(withThursday.find(cell => cell.weekday === Model.SATURDAY).weekend, false)
})

test('stepMonth rolls over Esfand into Farvardin of the next year', () => {
  assert.deepEqual(Model.stepMonth(1405, 12, 1), { year: 1406, month: 1 })
  assert.deepEqual(Model.stepMonth(1405, 1, -1), { year: 1404, month: 12 })
  assert.deepEqual(Model.stepMonth(1405, 6, 12), { year: 1406, month: 6 })
  assert.deepEqual(Model.stepMonth(1405, 6, -12), { year: 1404, month: 6 })
})

test('week start defaults to Saturday and toggles against Monday', () => {
  assert.equal(Model.normalizedWeekStart(null, null), Model.SATURDAY)
  assert.equal(Model.normalizedWeekStart('', null), Model.SATURDAY)
  assert.equal(Model.normalizedWeekStart('saturday', null), 6)
  assert.equal(Model.normalizedWeekStart('mon', null), 1)
  assert.equal(Model.toggledWeekStart(Model.SATURDAY), 1)
  assert.equal(Model.toggledWeekStart(1), Model.SATURDAY)
  assert.equal(Model.weekStartSettingName(Model.SATURDAY), 'saturday')
})

test('weekdayOrder starts where it is told and wraps', () => {
  assert.deepEqual(Model.weekdayOrder(Model.SATURDAY), [6, 0, 1, 2, 3, 4, 5])
  assert.deepEqual(Model.weekdayOrder(1), [1, 2, 3, 4, 5, 6, 0])
})

test('yearProgress is measured on the Jalali year, so it empties at Nowruz', () => {
  assert.equal(Model.yearProgressPercent(1405, 1, 1), 0)
  assert.equal(Model.yearProgressPercent(1405, 12, 29), 100)
  assert.equal(Model.yearProgressPercent(1405, 7, 1), 51)
})

test('syncState reports missing when there is no document', () => {
  assert.equal(Model.syncState(null, Date.parse('2026-08-10T12:00:00Z'), 300), 'missing')
})

test('syncState reports missing when syncedAt is absent', () => {
  assert.equal(Model.syncState({}, Date.parse('2026-08-10T12:00:00Z'), 300), 'missing')
})

test('syncState reports ok for a recent sync', () => {
  const doc = { syncedAt: '2026-08-10T11:58:00Z' }
  assert.equal(Model.syncState(doc, Date.parse('2026-08-10T12:00:00Z'), 300), 'ok')
})

test('syncState tolerates one missed run', () => {
  // 300s interval, staleness threshold is 4x that, so 15 minutes is still ok.
  const doc = { syncedAt: '2026-08-10T11:48:00Z' }
  assert.equal(Model.syncState(doc, Date.parse('2026-08-10T12:00:00Z'), 300), 'ok')
})

test('syncState reports stale past the threshold', () => {
  const doc = { syncedAt: '2026-08-10T10:00:00Z' }
  assert.equal(Model.syncState(doc, Date.parse('2026-08-10T12:00:00Z'), 300), 'stale')
})

test('syncState reports missing for an unparseable syncedAt', () => {
  const doc = { syncedAt: 'not a date' }
  assert.equal(Model.syncState(doc, Date.parse('2026-08-10T12:00:00Z'), 300), 'missing')
})

test('dateFromKey builds a local date, not a UTC one', () => {
  const d = Model.dateFromKey('2026-08-10', null)
  assert.equal(d.getFullYear(), 2026)
  assert.equal(d.getMonth(), 7)
  assert.equal(d.getDate(), 10)
})

test('dateFromKey returns the fallback for a malformed key', () => {
  const fallback = new Date(2000, 0, 1)
  assert.equal(Model.dateFromKey('nope', fallback), fallback)
  assert.equal(Model.dateFromKey('', fallback), fallback)
  assert.equal(Model.dateFromKey(null, fallback), fallback)
  assert.equal(Model.dateFromKey('2026-08', fallback), fallback)
})

test('dateFromKey returns the fallback for non-numeric parts', () => {
  const fallback = new Date(2000, 0, 1)
  assert.equal(Model.dateFromKey('yyyy-mm-dd', fallback), fallback)
})

const DOC = {
  version: 1,
  events: [
    { id: 'a', calendarId: 'work@x', calendarName: 'Destify', color: '#ffad46', dateKey: '2026-08-10' },
    { id: 'b', calendarId: 'moon@x', calendarName: 'Phases of the Moon', color: '#fad165', dateKey: '2026-08-10' },
    { id: 'c', calendarId: 'work@x', calendarName: 'Destify', color: '#ffad46', dateKey: '2026-08-11' }
  ]
}

test('calendarsInDocument lists each calendar once, sorted by name', () => {
  assert.deepEqual(Model.calendarsInDocument(DOC), [
    { id: 'work@x', name: 'Destify', color: '#ffad46' },
    { id: 'moon@x', name: 'Phases of the Moon', color: '#fad165' }
  ])
})

test('calendarsInDocument tolerates a null document', () => {
  assert.deepEqual(Model.calendarsInDocument(null), [])
  assert.deepEqual(Model.calendarsInDocument({}), [])
})

test('toggleHiddenCalendar adds then removes', () => {
  const once = Model.toggleHiddenCalendar([], 'moon@x')
  assert.deepEqual(once, ['moon@x'])
  assert.deepEqual(Model.toggleHiddenCalendar(once, 'moon@x'), [])
})

test('toggleHiddenCalendar does not mutate its input', () => {
  const before = ['moon@x']
  Model.toggleHiddenCalendar(before, 'work@x')
  assert.deepEqual(before, ['moon@x'])
})

test('toggleHiddenCalendar tolerates a null list', () => {
  assert.deepEqual(Model.toggleHiddenCalendar(null, 'moon@x'), ['moon@x'])
})

test('visibleEvents drops hidden calendars only', () => {
  const visible = Model.visibleEvents(DOC.events, ['moon@x'])
  assert.equal(visible.length, 2)
  assert.ok(visible.every(e => e.calendarId === 'work@x'))
})

test('visibleEvents returns everything when nothing is hidden', () => {
  assert.equal(Model.visibleEvents(DOC.events, []).length, 3)
  assert.equal(Model.visibleEvents(DOC.events, null).length, 3)
})

test('isCalendarHidden matches by id', () => {
  assert.equal(Model.isCalendarHidden(['moon@x'], 'moon@x'), true)
  assert.equal(Model.isCalendarHidden(['moon@x'], 'work@x'), false)
  assert.equal(Model.isCalendarHidden([], 'work@x'), false)
})

const NOW = Date.parse('2026-08-10T09:00:00-05:00')
const at = (iso, extra = {}) => ({ id: iso, title: 'X', start: iso, allDay: false, ...extra })

test('nextEvent picks the soonest future event', () => {
  const events = [
    at('2026-08-10T18:00:00-05:00', { title: 'Later' }),
    at('2026-08-10T10:00:00-05:00', { title: 'Soon' }),
    at('2026-08-10T08:00:00-05:00', { title: 'Past' })
  ]
  assert.equal(Model.nextEvent(events, NOW).title, 'Soon')
})

test('nextEvent ignores events already started', () => {
  assert.equal(Model.nextEvent([at('2026-08-10T08:59:00-05:00')], NOW), null)
})

test('nextEvent ignores all-day events', () => {
  const events = [at('2026-08-10T00:00:00-05:00', { allDay: true }), at('2026-08-10T23:00:00-05:00', { title: 'Real' })]
  assert.equal(Model.nextEvent(events, NOW).title, 'Real')
})

test('nextEvent ignores unparseable starts', () => {
  assert.equal(Model.nextEvent([at('not a date')], NOW), null)
})

test('nextEvent returns null on an empty or null list', () => {
  assert.equal(Model.nextEvent([], NOW), null)
  assert.equal(Model.nextEvent(null, NOW), null)
})

test('formatCountdown renders minutes, hours and now, in Persian', () => {
  assert.equal(Model.formatCountdown(30 * 1000), 'هم\u200cاکنون')
  assert.equal(Model.formatCountdown(10 * 60 * 1000), '۱۰ دقیقه دیگر')
  assert.equal(Model.formatCountdown(60 * 60 * 1000), '۱ ساعت دیگر')
  assert.equal(Model.formatCountdown(72 * 60 * 1000), '۱ ساعت و ۱۲ دقیقه دیگر')
})

test('formatCountdown can be asked for Latin digits', () => {
  assert.equal(Model.formatCountdown(10 * 60 * 1000, false), '10 دقیقه دیگر')
  assert.equal(Model.formatCountdown(72 * 60 * 1000, false), '1 ساعت و 12 دقیقه دیگر')
})

test('formatCountdown gives up past a day and on bad input', () => {
  assert.equal(Model.formatCountdown(25 * 60 * 60 * 1000), null)
  assert.equal(Model.formatCountdown(-1), null)
  assert.equal(Model.formatCountdown(null), null)
  assert.equal(Model.formatCountdown(NaN), null)
})

test('shouldAnnounce only fires inside the lead window', () => {
  const soon = at('2026-08-10T09:10:00-05:00')
  const far = at('2026-08-10T12:00:00-05:00')
  assert.equal(Model.shouldAnnounce(soon, NOW, 15), true)
  assert.equal(Model.shouldAnnounce(soon, NOW, 5), false)
  assert.equal(Model.shouldAnnounce(far, NOW, 15), false)
  assert.equal(Model.shouldAnnounce(null, NOW, 15), false)
})

test('millisUntil is null for an unreadable start', () => {
  assert.equal(Model.millisUntil(at('nope'), NOW), null)
  assert.equal(Model.millisUntil(null, NOW), null)
})

test('nextEventToday ignores events on other days', () => {
  const events = [
    at('2026-08-11T09:00:00-05:00', { title: 'Tomorrow' }),
    at('2026-08-10T18:00:00-05:00', { title: 'Tonight' })
  ]
  events[0].dateKey = '2026-08-11'
  events[1].dateKey = '2026-08-10'
  assert.equal(Model.nextEventToday(events, NOW, '2026-08-10').title, 'Tonight')
})

test('nextEventToday returns null once the day is done', () => {
  const tomorrow = at('2026-08-11T09:00:00-05:00')
  tomorrow.dateKey = '2026-08-11'
  assert.equal(Model.nextEventToday([tomorrow], NOW, '2026-08-10'), null)
})

test('announceLabel keeps the clock and appends the event', () => {
  assert.equal(
    Model.announceLabel('دوشنبه ۱۵:۴۶', 'Standup', '۱۰ دقیقه دیگر'),
    'دوشنبه ۱۵:۴۶  ·  Standup ۱۰ دقیقه دیگر'
  )
})

test('announceLabel returns the clock alone when nothing is announced', () => {
  assert.equal(Model.announceLabel('دوشنبه ۱۵:۴۶', 'Standup', ''), 'دوشنبه ۱۵:۴۶')
  assert.equal(Model.announceLabel('دوشنبه ۱۵:۴۶', 'Standup', null), 'دوشنبه ۱۵:۴۶')
})

test('announceLabel falls back to the clock when the title is empty', () => {
  assert.equal(Model.announceLabel('دوشنبه ۱۵:۴۶', '', '۱۰ دقیقه دیگر'), 'دوشنبه ۱۵:۴۶')
})

test('truncateTitle only cuts what is too long', () => {
  assert.equal(Model.truncateTitle('Standup', 28), 'Standup')
  assert.equal(Model.truncateTitle('a'.repeat(40), 10), 'a'.repeat(9) + '…')
})

test('truncateTitle cuts mid-word rather than hunting for a boundary', () => {
  assert.equal(Model.truncateTitle('Design process solution here', 12), 'Design proc…')
})

test('truncateTitle does not leave a dangling space before the ellipsis', () => {
  // The cut lands exactly on the space after "Design".
  assert.equal(Model.truncateTitle('Design process', 8), 'Design…')
})

test('truncateTitle tolerates null', () => {
  assert.equal(Model.truncateTitle(null, 10), '')
})

const TYPED = [
  { id: 'a', calendarId: 'w', dateKey: '2026-08-10', eventType: 'default', responseStatus: 'accepted' },
  { id: 'b', calendarId: 'w', dateKey: '2026-08-10', eventType: 'workingLocation', responseStatus: '' },
  { id: 'c', calendarId: 'w', dateKey: '2026-08-10', eventType: 'default', responseStatus: 'declined' },
  { id: 'd', calendarId: 'w', dateKey: '2026-08-10', eventType: 'outOfOffice', responseStatus: '' }
]

test('visibleEvents hides workingLocation by default', () => {
  const ids = Model.visibleEvents(TYPED, []).map(e => e.id)
  assert.deepEqual(ids, ['a', 'c', 'd'])
})

test('visibleEvents can show workingLocation when asked', () => {
  const ids = Model.visibleEvents(TYPED, [], { hideWorkingLocation: false }).map(e => e.id)
  assert.deepEqual(ids, ['a', 'b', 'c', 'd'])
})

test('visibleEvents hides declined only when asked', () => {
  assert.deepEqual(Model.visibleEvents(TYPED, [], { hideDeclined: true }).map(e => e.id), ['a', 'd'])
  assert.deepEqual(Model.visibleEvents(TYPED, [], { hideDeclined: false }).map(e => e.id), ['a', 'c', 'd'])
})

test('visibleEvents still applies the calendar filter alongside type filters', () => {
  assert.deepEqual(Model.visibleEvents(TYPED, ['w']).map(e => e.id), [])
})

test('visibleEvents with no options behaves as the old two-argument call', () => {
  const plain = [{ id: 'x', calendarId: 'w', dateKey: '2026-08-10' }]
  assert.deepEqual(Model.visibleEvents(plain, []).map(e => e.id), ['x'])
})

test('isDeclined and isOutOfOffice read the right fields', () => {
  assert.equal(Model.isDeclined(TYPED[2]), true)
  assert.equal(Model.isDeclined(TYPED[0]), false)
  assert.equal(Model.isDeclined(null), false)
  assert.equal(Model.isOutOfOffice(TYPED[3]), true)
  assert.equal(Model.isOutOfOffice(TYPED[0]), false)
})

test('safeUrl only lets https through', () => {
  assert.equal(Model.safeUrl('https://meet.google.com/abc'), 'https://meet.google.com/abc')
  assert.equal(Model.safeUrl('http://meet.google.com/abc'), '')
  assert.equal(Model.safeUrl('javascript:alert(1)'), '')
  assert.equal(Model.safeUrl('file:///etc/passwd'), '')
  assert.equal(Model.safeUrl(''), '')
  assert.equal(Model.safeUrl(null), '')
})

test('safeUrl rejects anything that could break out of an argument', () => {
  assert.equal(Model.safeUrl('https://ok.com; rm -rf ~'), '')
  assert.equal(Model.safeUrl('https://ok.com "quoted"'), '')
  assert.equal(Model.safeUrl("https://ok.com'x"), '')
  assert.equal(Model.safeUrl('https://ok.com<script>'), '')
})

test('meetingUrlFor is empty rather than undefined when absent', () => {
  assert.equal(Model.meetingUrlFor({ id: 'x' }), '')
  assert.equal(Model.meetingUrlFor(null), '')
  assert.equal(Model.meetingUrlFor({ meetingUrl: 'https://z.com/1' }), 'https://z.com/1')
})

const meeting = (start, end, extra = {}) => ({
  id: 's', title: 'Standup', allDay: false, dateKey: '2026-08-10',
  start, end, meetingUrl: 'https://meet.google.com/x', ...extra
})
const TKEY = '2026-08-10'

test('isJoinableNow opens 15 minutes before the start', () => {
  const e = meeting('2026-08-10T09:00:00-05:00', '2026-08-10T09:30:00-05:00')
  const at = t => Model.isJoinableNow(e, Date.parse(t), TKEY)
  assert.equal(at('2026-08-10T08:44:00-05:00'), false)
  assert.equal(at('2026-08-10T08:45:00-05:00'), true)
})

test('isJoinableNow stays open during the meeting', () => {
  const e = meeting('2026-08-10T09:00:00-05:00', '2026-08-10T09:30:00-05:00')
  assert.equal(Model.isJoinableNow(e, Date.parse('2026-08-10T09:15:00-05:00'), TKEY), true)
})

test('isJoinableNow keeps a 15 minute grace after the end', () => {
  const e = meeting('2026-08-10T09:00:00-05:00', '2026-08-10T09:30:00-05:00')
  const at = t => Model.isJoinableNow(e, Date.parse(t), TKEY)
  assert.equal(at('2026-08-10T09:45:00-05:00'), true)
  assert.equal(at('2026-08-10T09:46:00-05:00'), false)
})

test('isJoinableNow is false for a meeting on another day', () => {
  const e = meeting('2026-08-14T09:00:00-05:00', '2026-08-14T09:30:00-05:00')
  assert.equal(Model.isJoinableNow(e, Date.parse('2026-08-10T09:00:00-05:00'), TKEY), false)
})

test('isJoinableNow needs a usable link', () => {
  const noLink = meeting('2026-08-10T09:00:00-05:00', '2026-08-10T09:30:00-05:00', { meetingUrl: '' })
  const bad = meeting('2026-08-10T09:00:00-05:00', '2026-08-10T09:30:00-05:00', { meetingUrl: 'javascript:x' })
  const now = Date.parse('2026-08-10T09:05:00-05:00')
  assert.equal(Model.isJoinableNow(noLink, now, TKEY), false)
  assert.equal(Model.isJoinableNow(bad, now, TKEY), false)
})

test('isJoinableNow treats an all-day event as joinable for its whole day', () => {
  const e = meeting('2026-08-10T00:00:00-05:00', '2026-08-11T00:00:00-05:00', { allDay: true })
  assert.equal(Model.isJoinableNow(e, Date.parse('2026-08-10T20:00:00-05:00'), TKEY), true)
  assert.equal(Model.isJoinableNow(e, Date.parse('2026-08-10T20:00:00-05:00'), '2026-08-11'), false)
})

test('isJoinableNow survives an unreadable or inverted time range', () => {
  const bad = meeting('nope', 'nope')
  assert.equal(Model.isJoinableNow(bad, Date.parse('2026-08-10T09:00:00-05:00'), TKEY), false)
  const inverted = meeting('2026-08-10T09:00:00-05:00', '2026-08-10T08:00:00-05:00')
  assert.equal(Model.isJoinableNow(inverted, Date.parse('2026-08-10T09:05:00-05:00'), TKEY), true)
})

test('eventUrlFor mirrors meetingUrlFor and is https only', () => {
  assert.equal(Model.eventUrlFor({ eventUrl: 'https://calendar.google.com/e' }), 'https://calendar.google.com/e')
  assert.equal(Model.eventUrlFor({ eventUrl: 'http://calendar.google.com/e' }), '')
  assert.equal(Model.eventUrlFor({}), '')
  assert.equal(Model.eventUrlFor(null), '')
})

test('commandPathFromUrl strips the file scheme and shortens home', () => {
  assert.equal(
    Model.commandPathFromUrl('file:///home/tmn/.config/omarchy/plugins/masoud.jalali-calendar/sync/setup', '/home/tmn'),
    '~/.config/omarchy/plugins/masoud.jalali-calendar/sync/setup'
  )
})

test('commandPathFromUrl leaves a path outside home alone', () => {
  assert.equal(
    Model.commandPathFromUrl('file:///opt/omarchy-jalali-calendar/sync/setup', '/home/tmn'),
    '/opt/omarchy-jalali-calendar/sync/setup'
  )
})

test('commandPathFromUrl tolerates a missing home or url', () => {
  assert.equal(Model.commandPathFromUrl('file:///srv/x/sync/setup', ''), '/srv/x/sync/setup')
  assert.equal(Model.commandPathFromUrl('', '/home/tmn'), '')
  assert.equal(Model.commandPathFromUrl(null, null), '')
})

test('commandPathFromUrl does not shorten a home-lookalike prefix', () => {
  // /home/tmn2 must not become ~2
  assert.equal(
    Model.commandPathFromUrl('file:///home/tmn2/plugin/sync/setup', '/home/tmn'),
    '/home/tmn2/plugin/sync/setup'
  )
})
