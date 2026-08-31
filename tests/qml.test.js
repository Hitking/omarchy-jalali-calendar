const test = require('node:test')
const assert = require('node:assert')
const fs = require('node:fs')
const path = require('node:path')
const Model = require('../Model.js')

// QML is not type-checked and a missing binding fails quietly: a label that
// resolves to nothing renders as an empty string, and a call into a function
// that no longer exists is a runtime error nobody sees until they open the
// panel on the day that code path runs. These tests read the .qml files as
// text and hold them against Model.js, which is the one thing a linter here
// cannot do and a screenshot only catches for the screen you happened to open.

const ROOT = path.join(__dirname, '..')
const QML_FILES = ['Panel.qml', 'SettingsView.qml', 'BarWidget.qml']

const sources = Object.fromEntries(
  QML_FILES.map(name => [name, fs.readFileSync(path.join(ROOT, name), 'utf8')])
)

function matchAll(text, pattern) {
  return [...text.matchAll(pattern)].map(match => match[1])
}

test('every string key the QML asks for exists in both tables', () => {
  const known = new Set(Model.stringKeys(Model.JALALI))

  for (const [name, source] of Object.entries(sources)) {
    for (const key of matchAll(source, /\broot\.t\("([^"]+)"\)/g)) {
      assert.ok(known.has(key), `${name} asks for a string "${key}" that no table has`)
      assert.notEqual(Model.text(Model.JALALI, key), '', `${key} is blank in Jalali`)
      assert.notEqual(Model.text(Model.GREGORIAN, key), '', `${key} is blank in Gregorian`)
    }
  }
})

test('the panel and the settings page actually use the table', () => {
  // A guard on the guard: if the extraction regex ever stops matching, the
  // test above would pass by finding nothing to check.
  const used = matchAll(sources['Panel.qml'], /\broot\.t\("([^"]+)"\)/g)
  const settings = matchAll(sources['SettingsView.qml'], /\broot\.t\("([^"]+)"\)/g)
  assert.ok(used.length > 15, `Panel.qml resolved ${used.length} strings`)
  assert.ok(settings.length > 20, `SettingsView.qml resolved ${settings.length} strings`)
})

test('no Persian string is left hardcoded in the QML', () => {
  // Anything in Persian script sitting in a .qml file is a label that will
  // not turn English when the calendar is switched to Gregorian.
  const persian = /[؀-ۿ]/
  for (const [name, source] of Object.entries(sources)) {
    source.split('\n').forEach((line, index) => {
      const code = line.replace(/\/\/.*$/, '')
      if (!persian.test(code)) return
      assert.ok(
        // Resolved through the table, so it turns English with the calendar.
        /root\.t\(/.test(code) || /Model\.text\(/.test(code)
          // Or it is a numeral form rather than a word, and follows the digit
          // setting instead: "٪" against "%" is that same switch.
          || /persianDigits/.test(code),
        `${name}:${index + 1} hardcodes Persian text: ${line.trim()}`
      )
    })
  }
})

test('every Model function the QML calls is defined in Model.js', () => {
  const model = fs.readFileSync(path.join(ROOT, 'Model.js'), 'utf8')
  const defined = new Set([
    ...matchAll(model, /^function\s+([A-Za-z_$][\w$]*)\s*\(/gm),
    ...matchAll(model, /^var\s+([A-Za-z_$][\w$]*)\s*=/gm)
  ])

  for (const [name, source] of Object.entries(sources)) {
    // The import line is `import "Model.js" as Model`, and prose about
    // Model.js in a comment is not a call either. Only whole-line comments
    // are stripped, so a "https://" inside code survives.
    const body = source.replace(/^import .*$/gm, '').replace(/^\s*\/\/.*$/gm, '')
    for (const member of matchAll(body, /\bModel\.([A-Za-z_$][\w$]*)/g)) {
      assert.ok(defined.has(member), `${name} calls Model.${member}, which does not exist`)
    }
  }
})

test('the QML never reaches for a calendar-specific helper directly', () => {
  // The whole point of the dispatch layer is that the panel does not branch
  // on the calendar. A direct jalali* or gregorian* call from QML is that
  // branch creeping back in.
  for (const [name, source] of Object.entries(sources)) {
    // The import line is `import "Model.js" as Model`, and prose about
    // Model.js in a comment is not a call either. Only whole-line comments
    // are stripped, so a "https://" inside code survives.
    const body = source.replace(/^import .*$/gm, '').replace(/^\s*\/\/.*$/gm, '')
    for (const member of matchAll(body, /\bModel\.([A-Za-z_$][\w$]*)/g)) {
      assert.ok(
        !/^(jalali|gregorian)[A-Z]/.test(member) && member !== 'isoWeek',
        `${name} calls Model.${member} directly instead of going through the dispatch layer`
      )
    }
  }
})

test('the bundled font files are present and referenced', () => {
  for (const face of ['Vazirmatn-Regular.ttf', 'Vazirmatn-Bold.ttf']) {
    const file = path.join(ROOT, 'fonts', face)
    assert.ok(fs.existsSync(file), `fonts/${face} is missing`)
    assert.ok(fs.statSync(file).size > 50000, `fonts/${face} looks truncated`)
    assert.ok(
      sources['BarWidget.qml'].includes(face) || sources['Panel.qml'].includes(face),
      `nothing loads fonts/${face}`
    )
  }
  // Redistributing the font is what the licence permits; shipping it without
  // the licence is what it does not.
  assert.ok(fs.existsSync(path.join(ROOT, 'fonts', 'OFL.txt')), 'fonts/OFL.txt is missing')
})

test('the manifest defaults name a calendar the model accepts', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(ROOT, 'manifest.json'), 'utf8'))
  const defaults = manifest.barWidget.defaults
  assert.equal(Model.normalizeCalendar(defaults.calendar), defaults.calendar)

  const schema = manifest.barWidget.schema.find(entry => entry.key === 'calendar')
  for (const option of schema.options) {
    assert.equal(Model.normalizeCalendar(option.value), option.value,
      `the manifest offers "${option.value}", which the model does not recognise`)
  }

  // A default format the formatter cannot parse would render as the literal
  // pattern in the bar, which is the first thing anybody sees.
  const now = new Date(2026, 7, 31, 14, 5)
  for (const key of ['format', 'formatAlt']) {
    const rendered = Model.format(now, defaults[key], { calendar: defaults.calendar })
    assert.ok(rendered.length > 0 && rendered !== defaults[key],
      `the default ${key} did not render`)
  }
})
