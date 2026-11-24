// Pure helpers for Bar.qml. No QML imports, so `node tests/run.js` can load
// this file as it is.

function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function entrySettings(entry) {
  if (!isPlainObject(entry)) return {}
  var copy = {}
  for (var key in entry) {
    if (key === "id") continue
    copy[key] = entry[key]
  }
  return copy
}

function entryId(entry) {
  if (typeof entry === "string") return entry
  if (isPlainObject(entry)) {
    var id = entry["id"]
    if (id !== undefined && id !== null && String(id) !== "") return String(id)
  }
  return ""
}

// A custom module (a command or a QML file named in shell.json) is drawn by
// the stock bar only; the sidebar has no place for one.
function customModuleType(entry) {
  var settings = entrySettings(entry)
  var type = String(settings.type || "")
  if (type) return type
  if (settings.exec) return "command"
  if (settings.source) return "qml"
  return ""
}

// The part of a widget id after its last dot: "omarchy.audio" -> "audio".
function widgetKind(id) {
  var name = String(id || "")
  return name.slice(name.lastIndexOf(".") + 1)
}

// The kinds of widget a sidebar row opens the panel of.
var panelKinds = ["agents", "network", "audio", "bluetooth", "power"]

function panelKind(id) {
  var kind = widgetKind(id)
  return panelKinds.indexOf(kind) !== -1 ? kind : "other"
}

// Widgets the sidebar draws itself or has no place for. They are not loaded.
var unhostedKinds = ["workspaces", "clock", "weather", "tray", "indicators", "keyboard-layout",
  "system-update", "menu", "spacer", "dropbox"]

// The layout entries to keep loaded (invisibly) for their panels and IPC, in
// bar order, one per id. Any of the five row kinds the layout lacks is added
// as the stock widget, when the shell has it, so every row opens something.
function hostedEntries(layout, hasWidget) {
  var sections = ["left", "centerBegin", "center", "centerEnd", "right", "tray"]
  var seen = {}, kinds = {}, out = []
  var cfg = isPlainObject(layout) ? layout : {}
  for (var s = 0; s < sections.length; s++) {
    var entries = cfg[sections[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      if (!id || seen[id] || customModuleType(entries[i])) continue
      if (unhostedKinds.indexOf(widgetKind(id)) !== -1) continue
      var kind = panelKind(id)
      // One widget per row kind: the first one in the layout wins.
      if (kind !== "other" && kinds[kind]) continue
      seen[id] = true
      if (kind !== "other") kinds[kind] = true
      out.push(entries[i])
    }
  }
  for (var k = 0; k < panelKinds.length; k++) {
    var stock = "omarchy." + panelKinds[k]
    if (!kinds[panelKinds[k]] && !seen[stock] && (typeof hasWidget !== "function" || hasWidget(stock)))
      out.push({ id: stock })
  }
  return out
}

// A bar surface is built per monitor, so a panel hotkey has several live
// copies of the same widget to route to. An open copy wins first, then the
// focused monitor's copy. Candidates are `{ slot, screenName, opened }`.
function pickPanelSlot(candidates, focusedScreen) {
  var rows = Array.isArray(candidates) ? candidates : []
  var pool = rows.filter(function(row) { return row && row.opened === true })
  if (pool.length === 0) pool = rows.filter(function(row) { return !!row })
  var focused = String(focusedScreen || "")
  if (focused) {
    var onFocused = pool.filter(function(row) { return row.screenName === focused })
    if (onFocused.length > 0) pool = onFocused
  }
  return pool.length > 0 ? pool[0].slot : null
}

// Agents and terminals spin a glyph at the front of their title several
// times a second. Dropped, so a busy window does not make the sidebar redraw
// for as long as it works.
function steadyTitle(title) {
  return String(title === undefined || title === null ? "" : title)
    .replace(/^[⠀-⣿◐-◓◴-◷✢✳✶✻✽∙·*|\/\\-]\s+/, "")
}

// A workspace name as kept: one line, trimmed, at most 32 characters.
function cleanName(name) {
  return String(name === undefined || name === null ? "" : name).replace(/\s+/g, " ").trim().slice(0, 32)
}

// Text from Pipewire or /proc: no control characters, trimmed, bounded.
function cleanText(value, max) {
  return String(value === undefined || value === null ? "" : value).replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, max)
}

// The names a state file may carry: { "<workspace id>": "Name" }.
function cleanNames(raw) {
  var names = {}
  if (!isPlainObject(raw)) return names
  for (var key in raw) {
    if (!/^[0-9]{1,4}$/.test(key) || typeof raw[key] !== "string") continue
    var clean = cleanName(raw[key])
    if (clean !== "") names[key] = clean
  }
  return names
}

// The theme's mode from its colors.toml (`mode = "light"`), or "" when it
// does not say.
function themeMode(toml) {
  var match = /^\s*mode\s*=\s*["']?(light|dark)["']?\s*(#.*)?$/m.exec(String(toml || ""))
  return match ? match[1] : ""
}

// A Hyprland monitor name, safe inside a quoted Lua string.
function safeMonitorName(name) {
  var value = String(name || "")
  return /^[A-Za-z0-9_.-]{1,64}$/.test(value) ? value : ""
}

if (typeof module !== "undefined") {
  module.exports = {
    isPlainObject: isPlainObject,
    entrySettings: entrySettings,
    entryId: entryId,
    customModuleType: customModuleType,
    widgetKind: widgetKind,
    panelKind: panelKind,
    hostedEntries: hostedEntries,
    pickPanelSlot: pickPanelSlot,
    steadyTitle: steadyTitle,
    cleanName: cleanName,
    cleanText: cleanText,
    cleanNames: cleanNames,
    themeMode: themeMode,
    safeMonitorName: safeMonitorName
  }
}
