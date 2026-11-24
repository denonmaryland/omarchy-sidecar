// node tests/run.js — the pure helpers, and a static check that every text
// sink in Bar.qml is plain text (plugins.md: markup-safety for dynamic text).
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const M = require("../BarModel.js")
const T = require("../Tokens.js")

const markup = '<img src="https://example.invalid/tracker"><b>x</b>'

// Markup-shaped input passes through untouched (it is drawn as plain text),
// only bounded and stripped of control characters.
assert.strictEqual(M.steadyTitle(markup), markup)
assert.strictEqual(M.cleanName(markup), markup.slice(0, 32))
assert.strictEqual(M.cleanText("a\u0000b\nc", 10), "a b c")
assert.strictEqual(M.cleanText(markup, 200), markup)

// Spinner glyphs at the front of a title are dropped.
assert.strictEqual(M.steadyTitle("⠋ claude"), "claude")
assert.strictEqual(M.steadyTitle("* build"), "build")
assert.strictEqual(M.steadyTitle("plain title"), "plain title")
assert.strictEqual(M.steadyTitle(undefined), "")

// Names in the state file: numeric keys and strings only, cleaned.
assert.deepStrictEqual(M.cleanNames({ "1": "  Mail  ", "x": "no", "2": 5, "3": "   " , "12345": "too long key"}), { "1": "Mail" })
assert.deepStrictEqual(M.cleanNames(null), {})

// Theme mode.
assert.strictEqual(M.themeMode('mode = "light"\naccent = "#fff"'), "light")
assert.strictEqual(M.themeMode('accent = "#fff"\nmode = "dark" # comment'), "dark")
assert.strictEqual(M.themeMode('accent = "#fff"'), "")

// Monitor names.
assert.strictEqual(M.safeMonitorName("eDP-1"), "eDP-1")
assert.strictEqual(M.safeMonitorName('x") os.exit() --'), "")

// Kinds and hosting.
assert.strictEqual(M.panelKind("omarchy.audio"), "audio")
assert.strictEqual(M.panelKind("someone.audio"), "audio")
assert.strictEqual(M.panelKind("omarchy.monitor"), "other")
const layout = {
  left: ["omarchy.menu", { id: "omarchy.workspaces" }],
  center: [{ id: "omarchy.clock" }],
  right: [{ id: "omarchy.tray" }, { id: "omarchy.network" }, { id: "omarchy.audio" }, { id: "omarchy.audio" },
          { id: "omarchy.monitor" }, { id: "custom", exec: "date" }],
  tray: [{ id: "omarchy.tailscale" }]
}
const hosted = M.hostedEntries(layout, function(id) { return id !== "omarchy.agents" })
assert.deepStrictEqual(hosted.map(M.entryId),
  ["omarchy.network", "omarchy.audio", "omarchy.monitor", "omarchy.tailscale", "omarchy.bluetooth", "omarchy.power"])
// A clone of a stock panel stands in for it.
assert.deepStrictEqual(M.hostedEntries({ right: [{ id: "me.audio" }] }, () => true).map(M.entryId),
  ["me.audio", "omarchy.agents", "omarchy.network", "omarchy.bluetooth", "omarchy.power"])
assert.deepStrictEqual(M.hostedEntries(null, () => false), [])

// Panel slot choice: an open copy, else the focused screen's copy.
const a = { name: "a" }, b = { name: "b" }
assert.strictEqual(M.pickPanelSlot([{ slot: a, screenName: "A" }, { slot: b, screenName: "B" }], "B"), b)
assert.strictEqual(M.pickPanelSlot([{ slot: a, screenName: "A", opened: true }, { slot: b, screenName: "B" }], "B"), a)
assert.strictEqual(M.pickPanelSlot([], "B"), null)

// Both palettes carry the same tokens.
assert.deepStrictEqual(Object.keys(T.light).sort(), Object.keys(T.dark).sort())

// Static: the only Text in Bar.qml is the Label component, which is PlainText;
// TextInput does not render rich text.
const qml = fs.readFileSync(path.join(__dirname, "..", "Bar.qml"), "utf8")
const texts = qml.match(/\bText\s*\{/g) || []
assert.strictEqual(texts.length, 1, "expected one Text element (the Label component)")
assert.ok(/component Label: Text \{\s*\n\s*textFormat: Text\.PlainText/.test(qml), "Label must be PlainText")
assert.ok(!/\.\.\//.test(qml.replace(/\/\/.*$/gm, "")), "no imports from outside the plugin")

// Every string key the bar reads exists in en.json.
const en = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "i18n", "en.json"), "utf8"))
const keys = new Set((qml.match(/\b(?:tr|strings\.tn?)\("([^"]+)"/g) || []).map(k => k.replace(/.*\("/, "").replace(/"$/, "")))
for (const k of keys) if (!k.endsWith(".")) assert.ok(k in en, "missing i18n key " + k)
for (const k of ["page.terminal", "page.browser", "page.files"]) assert.ok(k in en)

console.log("ok")
