const test = require('node:test')
const assert = require('node:assert')
const Model = require('../Model.js')

// Connecting an account from the settings page is a QML text field, a
// process, and one JSON object coming back. Only the middle part is QML;
// these tests cover everything either side of it, because the failure modes
// here are the ones a user meets on their first five minutes with the plugin
// and the ones nobody can reproduce on purpose: a refused password, a server
// that answers with a traceback, a helper that will not run at all.

test('a request carries the three fields the helper asks for', () => {
  const request = Model.connectRequest({
    url: '  https://mail.example.com/  ',
    username: ' me@example.com ',
    password: 'hunter2',
    verifyTls: true
  })
  assert.deepEqual(request, {
    url: 'https://mail.example.com/',
    username: 'me@example.com',
    password: 'hunter2',
    verifyTls: true
  })
})

test('a password keeps the spaces it was given', () => {
  // A trailing space is a legal part of a password. Trimming it fails the
  // login with nothing on screen to explain why the password that works in
  // webmail does not work here.
  const request = Model.connectRequest({ url: 'u', username: 'n', password: ' s p ace ' })
  assert.equal(request.password, ' s p ace ')
})

test('verifyTls is on unless it was turned off', () => {
  assert.equal(Model.connectRequest({}).verifyTls, true)
  assert.equal(Model.connectRequest({ verifyTls: false }).verifyTls, false)
})

test('a missing field is named before anything is run', () => {
  const problem = fields => Model.connectRequestProblem(Model.connectRequest(fields), false)

  assert.equal(problem({}), 'urlRequired')
  assert.equal(problem({ url: 'https://mail/' }), 'usernameRequired')
  assert.equal(problem({ url: 'https://mail/', username: 'me' }), 'passwordRequired')
  assert.equal(problem({ url: 'https://mail/', username: 'me', password: 'x' }), '')
})

test('a blank password is fine when one is already stored', () => {
  // The panel cannot show a password it never had, so the field is blank when
  // the user is only correcting the URL.
  const request = Model.connectRequest({ url: 'https://mail/', username: 'me' })
  assert.equal(Model.connectRequestProblem(request, true), '')
  assert.equal(Model.connectRequestProblem(request, false), 'passwordRequired')
})

test('every problem key names a string both calendars have', () => {
  for (const key of ['urlRequired', 'usernameRequired', 'passwordRequired']) {
    assert.notEqual(Model.text(Model.JALALI, key), '', `${key} is blank in Jalali`)
    assert.notEqual(Model.text(Model.GREGORIAN, key), '', `${key} is blank in Gregorian`)
  }
})

test('a successful reply reports how many calendars were found', () => {
  const outcome = Model.connectOutcome(JSON.stringify({
    ok: true,
    calendars: [{ name: 'Personal' }, { name: 'Work' }],
    timer: 'enabled',
    firstSync: 'ok'
  }), 0)

  assert.equal(outcome.ok, true)
  assert.equal(outcome.key, 'connectedCount')
  assert.equal(outcome.value, '2')
})

test('a connection whose timer never started still says so', () => {
  // Connected and never updating again is not a success worth a green tick.
  const outcome = Model.connectOutcome(JSON.stringify({
    ok: true,
    calendars: [{ name: 'Personal' }],
    timer: 'not enabled: Failed to connect to bus',
    firstSync: 'ok'
  }), 0)

  assert.equal(outcome.ok, true)
  assert.equal(outcome.key, 'timerWarning')
  assert.match(outcome.value, /Failed to connect to bus/)
})

test('a failed first sync is reported over a bare success', () => {
  const outcome = Model.connectOutcome(JSON.stringify({
    ok: true, calendars: [{ name: 'A' }], timer: 'enabled', firstSync: 'failed (exit 1)'
  }), 0)
  assert.equal(outcome.key, 'firstSyncWarning')
})

test('a refused password gets its own sentence', () => {
  const outcome = Model.connectOutcome(JSON.stringify({
    ok: false, stage: 'credentials', error: '401 Unauthorized'
  }), 1)

  assert.equal(outcome.ok, false)
  assert.equal(outcome.key, 'credentialsRefused')
  assert.equal(outcome.value, '401 Unauthorized')
})

test('any other failure stage reads as a plain failure with its reason', () => {
  const outcome = Model.connectOutcome(JSON.stringify({
    ok: false, stage: 'config', error: 'cannot write /etc/nope: Permission denied'
  }), 1)

  assert.equal(outcome.key, 'connectFailed')
  assert.match(outcome.value, /Permission denied/)
})

test('a traceback instead of JSON does not throw', () => {
  const outcome = Model.connectOutcome(
    'Traceback (most recent call last):\n  File "x", line 1\nValueError: nope', 1)
  assert.equal(outcome.ok, false)
  assert.equal(outcome.key, 'connectCrashed')
})

test('an empty reply is told apart from a crashed one', () => {
  // Exit zero and nothing on stdout is a different bug from a helper that
  // could not run, and the two need different things looked at.
  assert.equal(Model.connectOutcome('', 0).key, 'connectUnreadable')
  assert.equal(Model.connectOutcome('', 127).key, 'connectCrashed')
})

test('the JSON object is found even behind a warning line', () => {
  // Python writes warnings to stderr, but a stray print from a hook or a
  // sitecustomize lands on stdout ahead of the result.
  const outcome = Model.connectOutcome(
    'warning: locale not set\n' + JSON.stringify({ ok: true, calendars: [1], timer: 'enabled', firstSync: 'ok' }),
    0)
  assert.equal(outcome.ok, true)
  assert.equal(outcome.value, '1')
})

test('every outcome key names a string both calendars have', () => {
  const replies = [
    [JSON.stringify({ ok: true, calendars: [1], timer: 'enabled', firstSync: 'ok' }), 0],
    [JSON.stringify({ ok: true, calendars: [1], timer: 'not enabled: x', firstSync: 'ok' }), 0],
    [JSON.stringify({ ok: true, calendars: [1], timer: 'enabled', firstSync: 'failed' }), 0],
    [JSON.stringify({ ok: false, stage: 'credentials', error: 'x' }), 1],
    [JSON.stringify({ ok: false, stage: 'config', error: 'x' }), 1],
    ['', 0],
    ['', 1]
  ]

  for (const [raw, code] of replies) {
    const { key } = Model.connectOutcome(raw, code)
    assert.notEqual(Model.text(Model.JALALI, key), '', `${key} is blank in Jalali`)
    assert.notEqual(Model.text(Model.GREGORIAN, key), '', `${key} is blank in Gregorian`)
  }
})

// ---- Reading the config file back, which is what prefills the form.

test('the caldav block is read with every field present', () => {
  const settings = Model.caldavSettings({
    source: 'caldav',
    caldav: { url: 'https://mail.example.com/', username: 'me@example.com', verifyTls: false }
  })
  assert.deepEqual(settings, {
    url: 'https://mail.example.com/',
    username: 'me@example.com',
    verifyTls: false,
    passwordFile: ''
  })
})

test('a config with no caldav block still renders a form', () => {
  // A Google-only config is the common case for anyone who set up before
  // CalDAV existed, and the settings page has to open for them too.
  const settings = Model.caldavSettings({ source: 'google', profile: '/home/me/.config/gws' })
  assert.equal(settings.url, '')
  assert.equal(settings.verifyTls, true)
})

test('garbage in the config file is not a crash', () => {
  assert.equal(Model.parseConfigDocument('{ not json'), null)
  assert.equal(Model.parseConfigDocument(''), null)
  assert.equal(Model.parseConfigDocument('[]'), null)
  assert.deepEqual(Model.caldavSettings(Model.parseConfigDocument('{ not json')).url, '')
})

test('the source decides which tab opens', () => {
  assert.equal(Model.normalizeSource('caldav'), Model.SOURCE_CALDAV)
  assert.equal(Model.normalizeSource('CalDAV'), Model.SOURCE_CALDAV)
  // Absent means Google, which is what the sync itself defaults to, so the
  // panel and the sync agree about a config file that says nothing.
  assert.equal(Model.normalizeSource(''), Model.SOURCE_GOOGLE)
  assert.equal(Model.normalizeSource(undefined), Model.SOURCE_GOOGLE)
})

test('the account form opens on CalDAV when nothing is configured', () => {
  // The tab and the sync's own default are different questions. A config
  // file that says nothing means Google to the sync (that is what it has
  // always meant), but a first-time user needs the form they can finish
  // without a terminal.
  assert.equal(Model.preferredProvider(null), Model.SOURCE_CALDAV)
  assert.equal(Model.preferredProvider({}), Model.SOURCE_CALDAV)
  assert.equal(Model.normalizeSource(''), Model.SOURCE_GOOGLE)
})

test('an existing setup opens on the tab it is already using', () => {
  assert.equal(Model.preferredProvider({ source: 'caldav' }), Model.SOURCE_CALDAV)
  assert.equal(Model.preferredProvider({ source: 'google' }), Model.SOURCE_GOOGLE)
  // Written by sync/setup-google before `source` existed as a key.
  assert.equal(
    Model.preferredProvider({ gwsPath: '/usr/bin/gws', profile: '/home/me/.config/gws' }),
    Model.SOURCE_GOOGLE)
})
