import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Wayland
import QtQml
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "BarModel.js" as BarModel
import "Tokens.js" as Tokens

// Sidecar, a bar for Omarchy, styled after Solid Glass.
//
// Collapsed it is a 56px rail drawn straight on the page: no pane, no frame,
// no shader. Resting the pointer on it (or `omarchy-shell sidecar expand`)
// opens a 264px sidebar that floats over the windows as a card;
// pinning makes that sidebar part of the page and pushes the windows over.
//
// The panels (network, audio, bluetooth, power, agents) are the bar widgets
// listed in shell.json, or the stock ones when the layout has none. They are
// loaded here at zero size and never drawn, parked on the row or cell that
// opens them, so their IPC targets keep working and their cards stand off
// the right place.
Item {
  id: root

  // The plugin's own strings (i18n/<language>.json).
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  function tr(key) { return strings.t(key) }

  // ---- injected by the omarchy-shell host ---------------------------------
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var barWidgetRegistry: fallbackBarWidgetRegistry
  property var pluginRegistry: null
  property var barConfig: ({})
  property var shell: null
  property var manifest: null
  QtObject {
    id: fallbackBarWidgetRegistry
    property var widgets: ({})
    property int revision: 0
    function metadataFor(id) { return null }
  }

  // ---- geometry -------------------------------------------------------------
  readonly property int railWidth: 56
  // The sidebar's width is the owner's: dragged by its right edge, kept in
  // sidecar.json. dragWidth is the width under the pointer during a drag.
  readonly property int defaultWidth: 264
  readonly property int minWidth: 216
  readonly property int maxWidth: 440
  // Dragged left of this, letting go folds the sidebar back to the rail.
  readonly property int foldBelow: 150
  property int savedWidth: defaultWidth
  property int dragWidth: -1
  property bool resizing: false
  property bool resizeFold: false
  // Pinned, every width change makes Hyprland lay all the windows out
  // again, so the reserved width is applied on release and the drag only
  // moves a guide line. Floating, the card follows the pointer.
  readonly property bool liveReserve: false
  readonly property int wideWidth: dragWidth > 0 && (liveReserve || !pinned) ? dragWidth : savedWidth
  readonly property int cardInset: 8
  // Room to the right of the floating card for its shadow.
  readonly property int shadowRoom: 48

  // ---- the bar contract the widgets, panels and host read --------------------
  readonly property string position: "left"
  readonly property bool vertical: true
  readonly property int barSize: railWidth
  readonly property int crossSize: railWidth
  readonly property int frameThickness: 0
  readonly property int floatingEdgeGap: 0
  function edgeThickness(edge) { return edge === "left" ? railWidth : 0 }
  readonly property color shellSurface: sg.page

  // How far the bar reaches into a screen: where its visible edge is. Stock
  // panels (KeyboardPanel) stand their card off this line, so a card opened
  // from the sidebar sits beside the sidebar rather than under it.
  function barSizeFor(screenName) {
    if (pinned) return wideWidth
    if (floatOpen && floatScreen === String(screenName || "")) return wideWidth + cardInset
    return railWidth
  }
  // What the bar reserves on each screen, for toasts and other plugins.
  readonly property var screenBarSizes: {
    var sizes = ({})
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) sizes[screens[i].name] = pinned ? wideWidth : railWidth
    return sizes
  }

  // ---- the look ---------------------------------------------------------------
  // Light or dark follows the Omarchy theme: its colors.toml says `mode`, and
  // a theme that does not is read by the lightness of its background.
  property string themeMode: ""
  FileView {
    path: Commons.Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var toml = text()
      root.themeMode = BarModel.themeMode(toml)
      root.themeBackground = Tokens.tomlColor(toml, "background")
      root.themePage = Tokens.tomlColor(toml, "dark_background")
    }
    onLoadFailed: { root.themeMode = ""; root.themeBackground = ""; root.themePage = "" }
  }
  property string themeBackground: ""
  property string themePage: ""
  readonly property bool lightTheme: themeMode !== "" ? themeMode === "light" : Commons.Color.background.hslLightness > 0.6
  readonly property var tokens: Tokens.tinted(lightTheme ? Tokens.light : Tokens.dark, lightTheme, themeBackground, themePage)
  // Geist when it is installed, else the shell's own face.
  readonly property var installedFamilies: Qt.fontFamilies()
  readonly property bool hasGeist: installedFamilies.indexOf("Geist") !== -1
  property string fontFamily: hasGeist ? "Geist" : Style.font.family
  readonly property string mono: installedFamilies.indexOf("Geist Mono") !== -1 ? "Geist Mono" : Style.font.family
  property color themeForeground: sg.foreground
  property color foreground: themeForeground
  property color barForeground: themeForeground
  property bool foregroundAnimationEnabled: true
  property color background: sg.page
  property color urgent: Commons.Color.bar.active
  readonly property bool transparent: false
  property bool centerSectionRevealHeld: false
  property bool centerHoverRevealSuppressed: false
  function setCenterHoverRevealSuppressed(value) { centerHoverRevealSuppressed = !!value }
  property bool barHidden: false
  property var screensaverWindows: ({})
  property bool screensaverUp: false
  readonly property bool barParked: barHidden || screensaverUp
  readonly property bool barHovered: pointerInside
  property var barDragSource: null
  property var activePopout: null
  property var clickTargets: []
  property var moduleSlots: []
  readonly property var layoutConfig: barConfig && BarModel.isPlainObject(barConfig.layout) ? barConfig.layout : ({})
  readonly property string home: Quickshell.env("HOME")

  // Solid Glass tokens, and the few greys the design sets between them.
  readonly property QtObject sg: QtObject {
    readonly property color page: root.tokens.page
    readonly property color foreground: root.tokens.foreground
    readonly property color mutedFg: root.tokens.mutedFg
    readonly property color popover: root.tokens.popover
    readonly property color rim: root.tokens.rim
    readonly property color edge: root.tokens.edge
    readonly property color popoverEdge: root.tokens.popoverEdge
    readonly property color shade: root.tokens.shade
    readonly property color control: root.tokens.control
    readonly property color controlRim: root.tokens.controlRim
    readonly property color state: root.tokens.state
    readonly property color stateRim: root.tokens.stateRim
    readonly property color stateEdge: root.tokens.stateEdge
    readonly property color stateArmed: root.tokens.stateArmed
    readonly property color hover: root.tokens.hover
    readonly property color hoverFaint: root.tokens.hoverFaint
    readonly property color well: root.tokens.well
    readonly property color wellShade: root.tokens.wellShade
    readonly property color wellRim: root.tokens.wellRim
    readonly property color border: root.tokens.border
    readonly property color primary: root.tokens.primary
    readonly property color primaryFg: root.tokens.primaryFg
    readonly property color primaryRim: root.tokens.primaryRim
    readonly property color primaryUnder: root.tokens.primaryUnder
  }
  function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }
  readonly property color cFg: sg.foreground
  readonly property color cMuted: sg.mutedFg
  readonly property color cLabel: mix(sg.foreground, sg.mutedFg, 0.44)
  readonly property color cTitle: mix(sg.foreground, sg.mutedFg, 0.71)
  readonly property color cDim: Qt.rgba(sg.mutedFg.r, sg.mutedFg.g, sg.mutedFg.b, 0.8)
  readonly property color cFaint: Qt.rgba(sg.mutedFg.r, sg.mutedFg.g, sg.mutedFg.b, 0.6)

  // ---- state ------------------------------------------------------------------
  // Pinned: part of the page, 264px reserved. Persisted in sidecar.json.
  property bool pinned: false
  // Floating: open as a card over the windows on one screen.
  property bool floatOpen: false
  property string floatScreen: ""
  // Opened by IPC rather than by the pointer: it stays until Escape, another
  // IPC call, or the pointer has come in and gone out again.
  property bool held: false
  property bool heldVisited: false
  property bool focusPrimed: false
  property bool pointerInside: false
  property string pointerScreen: ""
  property point dwellOrigin: Qt.point(-100, -100)
  // A panel card opened from the sidebar is up (stock panels report it
  // through requestPopout / releasePopout).
  readonly property bool panelOpen: !!activePopout

  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    if (monitor && monitor.name) return String(monitor.name)
    return Quickshell.screens.length > 0 ? String(Quickshell.screens[0].name) : ""
  }
  function expand(screenName, hold) {
    if (pinned) return
    floatScreen = screenName || focusedScreenName()
    held = !!hold
    heldVisited = false
    focusPrimed = false
    floatOpen = true
    if (held) focusPrimeTimer.restart()
  }
  function collapse() {
    floatOpen = false
    held = false
    if (!pinned) endRename()
    dwellTimer.stop()
    leaveTimer.stop()
  }
  function setPinned(value) {
    value = !!value
    if (pinned === value) return
    pinned = value
    if (value) collapse()
    saveState()
  }
  function toggle() {
    if (pinned) setPinned(false)
    else if (floatOpen) collapse()
    else expand("", true)
  }
  function stateName() { return pinned ? "pinned" : floatOpen ? "expanded" : "collapsed" }

  // Workspace names, yours: { "<workspace id>": "Name" }, kept in sidecar.json.
  // A workspace without one reads "Workspace N".
  property var wsNames: ({})
  // The workspace whose row is being renamed (-1 none), and on which screen.
  property int renamingWs: -1
  property string renamingScreen: ""
  function wsName(id) { var n = wsNames[String(id)]; return typeof n === "string" ? n : "" }
  function wsTitle(id) { var n = wsName(id); return n !== "" ? n : tr("workspace.numbered").arg(wsLabel(id)) }
  function cleanName(name) { return BarModel.cleanName(name) }
  function setWsName(id, name) {
    id = Number(id)
    if (!(id > 0)) return ""
    var clean = cleanName(name)
    if (clean === wsName(id)) return clean
    var next = {}
    for (var key in wsNames) if (key !== String(id)) next[key] = wsNames[key]
    if (clean !== "") next[String(id)] = clean
    wsNames = next
    saveState()
    return clean
  }
  function beginRename(id, screenName) {
    if (!(id > 0)) return
    leaveTimer.stop()
    renamingScreen = screenName || focusedScreenName()
    renamingWs = id
  }
  function endRename() { renamingWs = -1; renamingScreen = "" }

  // ---- resizing ---------------------------------------------------------------
  function clampWidth(value) {
    var w = Math.round(Number(value))
    if (!isFinite(w)) return defaultWidth
    return Math.max(minWidth, Math.min(maxWidth, w))
  }
  // From IPC: clamp, apply, save.
  function applyWidth(value) {
    var w = clampWidth(value)
    if (w !== savedWidth) { savedWidth = w; saveState() }
    return w
  }
  function beginResize() {
    resizing = true
    resizeFold = false
    dragWidth = -1
    leaveTimer.stop()
  }
  // raw: where the pointer puts the sidebar's right edge, as a width.
  function resizeTo(raw) {
    if (!resizing) return
    if (raw < foldBelow) { resizeFold = true; dragWidth = minWidth; return }
    var w = clampWidth(raw)
    if (Math.abs(w - defaultWidth) <= 8) w = defaultWidth
    resizeFold = false
    dragWidth = w
  }
  // commit false: the drag was cancelled, nothing changes.
  function endResize(commit) {
    if (!resizing) return
    var w = dragWidth
    var fold = resizeFold
    if (commit && !fold && w > 0 && w !== savedWidth) { savedWidth = w; saveState() }
    dragWidth = -1
    resizeFold = false
    resizing = false
    if (commit && fold) {
      // Folded away: the saved width stays for the next time it opens.
      if (pinned) setPinned(false)
      else collapse()
      return
    }
    if (floatOpen && !pointerInside && (!held || heldVisited)) leaveTimer.restart()
  }

  function pointerChanged(screenName, inside) {
    if (inside) {
      pointerInside = true
      pointerScreen = screenName
      leaveTimer.stop()
      if (held) heldVisited = true
      if (!pinned && !floatOpen) dwellTimer.restart()
    } else if (pointerScreen === screenName) {
      pointerInside = false
      dwellTimer.stop()
      if (floatOpen && (!held || heldVisited)) leaveTimer.restart()
    }
  }
  // "Rests": the dwell starts over while the pointer is still travelling.
  function pointerMoved(pos) {
    if (pinned || floatOpen) return
    if (Math.abs(pos.x - dwellOrigin.x) + Math.abs(pos.y - dwellOrigin.y) < 4) return
    dwellOrigin = pos
    dwellTimer.restart()
  }
  Timer {
    id: dwellTimer
    interval: 200
    onTriggered: if (root.pointerInside && !root.pinned && !root.panelOpen) root.expand(root.pointerScreen, false)
  }
  Timer {
    id: leaveTimer
    interval: 260
    // A card opened from the sidebar covers the screen with its overlay and
    // so takes the pointer; the sidebar waits for it to close.
    onTriggered: if (!root.pointerInside && !root.panelOpen && !root.resizing && root.renamingWs < 0) root.collapse()
  }
  // Take the keyboard for a moment, then share it (as PanelHost does), so
  // Escape reaches a sidebar opened from the keyboard.
  Timer { id: focusPrimeTimer; interval: 75; onTriggered: root.focusPrimed = true }
  onPanelOpenChanged: if (!panelOpen && floatOpen && !pointerInside && (!held || heldVisited)) leaveTimer.restart()

  FileView {
    id: stateFile
    path: root.home + "/.config/omarchy/sidecar.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var next = JSON.parse(text())
        if (next && next.version === 1) {
          var want = next.pinned === true
          if (want !== root.pinned) { root.pinned = want; if (want) root.collapse() }
          // Missing or not a number: the default. Out of range: the nearest limit.
          root.savedWidth = next.width === undefined || next.width === null ? root.defaultWidth : root.clampWidth(next.width)
          var names = BarModel.cleanNames(next.names)
          if (JSON.stringify(names) !== JSON.stringify(root.wsNames)) root.wsNames = names
        }
      } catch (e) {}
    }
  }
  function saveState() { stateFile.setText(JSON.stringify({ version: 1, pinned: root.pinned, width: root.savedWidth, names: root.wsNames }, null, 2) + "\n") }

  ShellIpc {
    target: "sidecar"
    function toggle(): string { root.toggle(); return root.stateName() }
    function expand(): string { root.expand("", true); return root.stateName() }
    function collapse(): string { root.setPinned(false); root.collapse(); return root.stateName() }
    function pin(): string { root.setPinned(!root.pinned); return root.stateName() }
    function unpin(): string { root.setPinned(false); return root.stateName() }
    function state(): string { return root.stateName() }
    // The sidebar's width in px; setWidth clamps to 216..440, applies and saves.
    function width(): string { return String(root.wideWidth) }
    function setWidth(px: int): string { return String(root.applyWidth(px)) }
    // Name a workspace by its Hyprland id; an empty name takes the name off.
    // rename opens the row's name field as a double-click does.
    function name(id: int, name: string): string { return root.setWsName(id, name) }
    function names(): string { return JSON.stringify(root.wsNames) }
    // Go to a pinned app's page (terminal, browser, files), opening the app
    // if the page is empty; `another` opens one more window there.
    function page(key: string): string { return root.openPage(String(key), false) }
    function another(key: string): string { return root.openPage(String(key), true) }
    function rename(id: int): string {
      if (!root.pinned && !root.floatOpen) root.expand("", true)
      root.beginRename(id, root.pinned ? "" : root.floatScreen)
      return root.renamingWs > 0 ? "ok" : "none"
    }
    // Open or close one of the panels the rows open: agents, network, audio,
    // bluetooth, power.
    function panel(kind: string): string { return root.togglePanel(String(kind)) ? "ok" : "none" }
    // What is making sound: [{ app, workspace, address, muted }].
    function sound(): string { return root.soundReport() }
    // Mute or unmute the streams of one window (a Hyprland address), as a
    // click on its speaker does. Answers muted, unmuted or none.
    function muteWindow(address: string): string { return root.toggleWindowSound(String(address)) }
  }

  // ---- actions ------------------------------------------------------------------
  function run(command) { if (command) Util.execDetached(command) }
  function openMenu(route) { run("omarchy-shell shell toggle omarchy.menu " + Util.shellQuote(JSON.stringify({ menu: route }))) }
  function openSearch() { openMenu("root") }
  function openApps() { run("omarchy-shell omarchy.dock apps") }
  // The stock notification service puts its last few notifications back on
  // screen. (A real inbox is future work.)
  function openInbox() { run("omarchy-shell notifications showHistory") }
  // Pages: each pinned app has a workspace of its own, named after it, that
  // holds only that app's windows. `many`: the row offers another window.
  readonly property var pages: [
    { key: "terminal", name: "Terminal", icon: "terminal", many: true, match: /(foot|alacritty|kitty|ghostty|wezterm|konsole)/i },
    { key: "browser", name: "Browser", icon: "globe", many: false, match: /(brave|chrom|firefox|zen|librewolf|vivaldi|epiphany)/i },
    { key: "files", name: "Files", icon: "folder", many: false, match: /(nautilus|thunar|dolphin|nemo|pcmanfm)/i }
  ]
  // The plugin's own folder: bin/ holds its two helpers.
  readonly property string pluginDir: {
    var dir = manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
    if (dir === "") dir = decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, ""))
    return dir.replace(/\/+$/, "")
  }
  readonly property string helperDir: pluginDir + "/bin/"
  function pageNamed(name) {
    for (var i = 0; i < pages.length; i++) if (pages[i].name === name) return pages[i]
    return null
  }
  function pageFor(appClass) {
    for (var i = 0; i < pages.length; i++) if (pages[i].match.test(String(appClass || ""))) return pages[i]
    return null
  }
  function pageWs(name) {
    var all = Hyprland.workspaces.values
    for (var i = 0; i < all.length; i++) if (String(all[i].name) === name) return all[i]
    return null
  }
  function launchCommand(key) {
    return key === "terminal" ? "omarchy-launch-terminal" : key === "browser" ? "omarchy-launch-browser"
      : key === "files" ? "omarchy launch nautilus" : ""
  }
  // Go to the app's page; an empty page (or `another`) opens a window there.
  function openPage(key, another) {
    var page = null
    for (var i = 0; i < pages.length; i++) if (pages[i].key === key) page = pages[i]
    if (!page) return "none"
    var ws = pageWs(page.name)
    var has = !!ws && ws.toplevels.values.length > 0
    var command = Util.shellQuote(helperDir + "quiet-dispatch") + " " + Util.shellQuote("hl.dsp.focus({ workspace = \"name:" + page.name + "\" })")
    if (!has || another) command += " && " + launchCommand(page.key)
    run(command)
    return !has || another ? "opened" : "shown"
  }
  // The numbered workspace last shown: where a stray window on a page goes.
  property int lastNumberedWs: 1
  readonly property int focusedWsId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  onFocusedWsIdChanged: if (focusedWsId > 0) lastNumberedWs = focusedWsId
  // A tiled window of another app opened on a page: it goes to its own page
  // if it has one, else back to the numbered workspace you came from.
  function guardPage(address, wsName, appClass) {
    var page = pageNamed(String(wsName))
    if (!page || page.match.test(String(appClass || ""))) return
    var a = String(address || "").replace(/^0x/, "")
    if (!/^[0-9a-fA-F]+$/.test(a)) return
    var other = pageFor(appClass)
    run(Util.shellQuote(helperDir + "page-guard") + " " + a + " " + Util.shellQuote(other ? "name:" + other.name : String(lastNumberedWs)))
  }
  // Through quiet-dispatch so the pointer stays on the row that was clicked
  // instead of being carried to the window that takes focus.
  function dispatch(expression) { run(Util.shellQuote(helperDir + "quiet-dispatch") + " " + Util.shellQuote(expression)) }
  function focusWindow(address) {
    var a = String(address || "").replace(/^0x/, "")
    if (/^[0-9a-fA-F]+$/.test(a)) dispatch("hl.dsp.focus({ window = \"address:0x" + a + "\" })")
  }

  // ---- live values ----------------------------------------------------------------
  SystemClock { id: clock; precision: SystemClock.Minutes }
  readonly property var locale: Qt.locale(Commons.I18n.formatLocale)
  // "h:mm AP" as one format: on its own, "h" is the 24-hour hour.
  readonly property var timeParts: locale.toString(clock.date, "h:mm AP").split(" ")
  readonly property string timeText: timeParts[0] || ""
  readonly property string ampmText: timeParts.length > 1 ? timeParts[timeParts.length - 1] : ""
  readonly property string dateText: locale.toString(clock.date, "ddd, MMM d")

  property string hostName: ""
  FileView {
    path: "/etc/hostname"
    printErrors: false
    onLoaded: root.hostName = String(text()).trim().slice(0, 40)
  }

  // Sound: the default output.
  readonly property var sink: Pipewire.defaultAudioSink
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }
  readonly property real volume: sink && sink.audio ? Math.max(0, Math.min(1, sink.audio.volume)) : 0
  readonly property bool muted: !sink || !sink.audio || sink.audio.muted
  property real volumeWheel: 0
  function nudgeVolume(delta) {
    var wheel = Util.wheelSteps(volumeWheel, delta)
    volumeWheel = wheel.remainder
    if (wheel.steps === 0 || !sink || !sink.audio) return
    sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + wheel.steps * 0.05))
  }
  readonly property string soundText: !sink ? tr("sound.noOutput") : muted ? tr("sound.muted")
    : tr("percent").arg(Commons.I18n.formatNumber(Math.round(volume * 100)))

  // ---- sound sources: which window each running playback stream belongs to ----
  // Running is read from the stream's links: PwNode has no state of its own in
  // Quickshell, but a link is Active only while the stream is delivering
  // buffers and drops to Paused when the app corks or pauses it. A stream
  // that keeps running while it plays silence still counts.
  readonly property var soundNodes: {
    var all = Pipewire.nodes.values, out = []
    for (var i = 0; i < all.length; i++) {
      var n = all[i]
      if (n && n.isStream && n.isSink === true && n.audio && String(n.name || "").indexOf("omarchy_speaker_tuning") !== 0) out.push(n)
    }
    return out
  }
  readonly property var soundLinks: {
    var all = Pipewire.linkGroups.values, out = []
    for (var i = 0; i < all.length; i++)
      if (all[i] && all[i].source && root.soundNodes.indexOf(all[i].source) !== -1) out.push(all[i])
    return out
  }
  PwObjectTracker { objects: root.soundNodes }
  PwObjectTracker { objects: root.soundLinks }
  readonly property var soundLive: {
    var out = []
    for (var i = 0; i < soundLinks.length; i++) {
      var g = soundLinks[i]
      if (g.state === PwLinkState.Active && g.source.ready && out.indexOf(g.source) === -1) out.push(g.source)
    }
    return out
  }
  // Everything Pipewire and /proc say is untrusted: ids are digits or
  // nothing, names are trimmed, bounded and only ever drawn as plain text.
  function soundClean(value, max) { return BarModel.cleanText(value, max) }
  // "p<pid>" for a stream that names its process (everything that plays
  // through pipewire-pulse), "c<client id>" for a native client, whose pid
  // only the client object knows.
  function soundKey(node) {
    var p = node && node.ready ? node.properties : null
    if (!p) return ""
    var pid = String(p["application.process.id"] || "")
    if (/^[0-9]{1,9}$/.test(pid)) return "p" + pid
    var client = String(p["client.id"] || "")
    return /^[0-9]{1,9}$/.test(client) ? "c" + client : ""
  }
  readonly property string soundKeys: {
    var keys = []
    for (var i = 0; i < soundLive.length; i++) {
      var key = soundKey(soundLive[i])
      if (key !== "" && keys.indexOf(key) === -1) keys.push(key)
    }
    keys.sort()
    return keys.join(" ")
  }
  // key -> the stream's pid and its parents, nearest first. Browsers and
  // Electron apps play from a child of the process that owns the window.
  property var soundChains: ({})
  property var soundAsked: []
  property bool soundProbeAgain: false
  // The keys arrive as arguments, never inside the script text.
  readonly property string soundProbeScript: "for k in \"$@\"; do\n"
    + "  case \"$k\" in p|c|*[!0-9pc]*) continue ;; esac\n"
    + "  case \"$k\" in\n"
    + "    p*) pid=${k#p} ;;\n"
    + "    c*) pid=$(pw-cli info \"${k#c}\" 2>/dev/null | sed -n 's/.*pipewire\\.sec\\.pid = \"\\([0-9]*\\)\".*/\\1/p' | head -n 1) ;;\n"
    + "    *) continue ;;\n"
    + "  esac\n"
    + "  line=$k; n=0\n"
    + "  while [ $n -lt 8 ]; do\n"
    + "    case \"$pid\" in ''|*[!0-9]*) break ;; esac\n"
    + "    [ \"$pid\" -gt 1 ] || break\n"
    + "    line=\"$line $pid\"\n"
    + "    read -r stat 2>/dev/null < \"/proc/$pid/stat\" || break\n"
    + "    stat=${stat##*) }; stat=${stat#* }; pid=${stat%% *}\n"
    + "    n=$((n + 1))\n"
    + "  done\n"
    + "  echo \"$line\"\n"
    + "done\n"
  onSoundKeysChanged: probeSound()
  // Runs once when a stream that has not been seen starts; never on a timer.
  function probeSound() {
    var keys = soundKeys === "" ? [] : soundKeys.split(" ")
    var kept = {}, missing = []
    for (var i = 0; i < keys.length; i++) {
      if (soundChains[keys[i]]) kept[keys[i]] = soundChains[keys[i]]
      else missing.push(keys[i])
    }
    if (Object.keys(kept).length !== Object.keys(soundChains).length) soundChains = kept
    if (missing.length === 0) return
    if (soundProbe.running) { soundProbeAgain = true; return }
    Hyprland.refreshToplevels()
    soundAsked = missing.slice(0, 16)
    soundProbe.command = ["sh", "-c", soundProbeScript, "sh"].concat(soundAsked)
    soundProbe.running = true
  }
  function readSoundChains(text) {
    var next = {}, k
    for (k in soundChains) next[k] = soundChains[k]
    for (var a = 0; a < soundAsked.length; a++) next[soundAsked[a]] = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length && i < 32; i++) {
      var fields = lines[i].trim().split(/\s+/)
      if (!/^[pc][0-9]{1,9}$/.test(fields[0]) || soundAsked.indexOf(fields[0]) === -1) continue
      var pids = []
      for (var j = 1; j < fields.length && j <= 9; j++) if (/^[0-9]{1,9}$/.test(fields[j])) pids.push(parseInt(fields[j], 10))
      next[fields[0]] = pids
    }
    soundChains = next
    soundAsked = []
    if (soundProbeAgain) { soundProbeAgain = false; probeSound() }
  }
  Process {
    id: soundProbe
    stdout: StdioCollector { onStreamFinished: root.readSoundChains(text) }
  }
  function soundNameMatch(cls, names) {
    if (cls.length < 3) return false
    for (var i = 0; i < names.length; i++) {
      var name = names[i]
      if (name.length >= 3 && (cls === name || cls.indexOf(name) !== -1 || name.indexOf(cls) !== -1)) return true
    }
    return false
  }
  // One entry per stream and window it maps to; a stream no window claims is
  // kept with no address. Muted streams stay in, flagged.
  readonly property var soundSources: {
    var out = []
    if (soundLive.length === 0) return out
    var tops = Hyprland.toplevels.values, wins = []
    for (var i = 0; i < tops.length; i++) {
      var t = tops[i]
      if (!t || !t.workspace) continue
      var ipc = t.lastIpcObject || ({})
      wins.push({ top: t, pid: Number(ipc.pid) || 0, ws: t.workspace.id,
        cls: String(ipc["class"] || (t.wayland ? t.wayland.appId : "") || "").toLowerCase() })
    }
    for (var s = 0; s < soundLive.length; s++) {
      var node = soundLive[s], p = node.properties || ({})
      var app = soundClean(p["application.name"] || node.description || node.name, 40)
      var bin = soundClean(p["application.process.binary"], 40).toLowerCase()
      var media = soundClean(p["media.name"], 120)
      var key = soundKey(node)
      var chain = soundChains[key] || (key.charAt(0) === "p" ? [parseInt(key.slice(1), 10)] : [])
      var hits = []
      for (var c = 0; c < chain.length && hits.length === 0; c++)
        hits = wins.filter(function(w) { return w.pid > 1 && w.pid === chain[c] })
      if (hits.length === 0) hits = wins.filter(function(w) { return root.soundNameMatch(w.cls, [bin, app.toLowerCase()]) })
      // One process, several windows: the one whose title carries the media
      // name, or all of them when none does.
      if (hits.length > 1 && media.length >= 3) {
        var needle = media.toLowerCase()
        var titled = hits.filter(function(w) { return String(w.top.title || "").toLowerCase().indexOf(needle) !== -1 })
        if (titled.length > 0) hits = titled
      }
      var muted = node.audio.muted === true
      if (hits.length === 0) out.push({ id: node.id, app: app, media: media, muted: muted, address: "", ws: 0 })
      for (var h = 0; h < hits.length; h++)
        out.push({ id: node.id, app: app, media: media, muted: muted, address: String(hits[h].top.address || ""), ws: hits[h].ws })
    }
    return out
  }
  // address -> what plays in that window; workspace id -> what plays on it.
  // muted is true only when every stream there is muted.
  function soundIndex(field) {
    var map = {}
    for (var i = 0; i < soundSources.length; i++) {
      var src = soundSources[i], at = src[field]
      if (!at) continue
      var seen = map[at]
      if (!seen) map[at] = { app: src.app, media: src.media, muted: src.muted }
      else if (seen.muted && !src.muted) map[at] = { app: src.app, media: src.media, muted: false }
    }
    return map
  }
  readonly property var soundByWindow: soundIndex("address")
  readonly property var soundByWorkspace: soundIndex("ws")
  // What the Sound row names: the first stream that is not muted.
  readonly property var soundLead: {
    for (var i = 0; i < soundSources.length; i++) if (!soundSources[i].muted) return soundSources[i]
    return null
  }
  readonly property string soundSourceText: !soundLead ? ""
    : soundLead.ws > 0 ? soundLead.app + " · " + wsTitle(soundLead.ws) : soundLead.app
  // Mutes or unmutes the streams of one window, never the output itself.
  function toggleWindowSound(address) {
    var at = String(address || "").replace(/^0x/, ""), ids = [], anyLoud = false
    if (at === "") return "none"
    for (var i = 0; i < soundSources.length; i++)
      if (soundSources[i].address === at) { ids.push(soundSources[i].id); if (!soundSources[i].muted) anyLoud = true }
    var done = 0
    for (var n = 0; n < soundNodes.length; n++)
      if (ids.indexOf(soundNodes[n].id) !== -1 && soundNodes[n].audio) { soundNodes[n].audio.muted = anyLoud; done++ }
    return done === 0 ? "none" : anyLoud ? "muted" : "unmuted"
  }
  // No titles or media names: this goes to a terminal and into logs.
  function soundReport() {
    return JSON.stringify(soundSources.map(function(src) {
      return { app: src.app, workspace: src.ws, address: src.address === "" ? "" : "0x" + src.address, muted: src.muted }
    }))
  }

  // Network: the connected Wi-Fi network, or the wire.
  readonly property var netDevices: Networking.devices ? Networking.devices.values : []
  // "ssid" (with networkName), "connected", "wired", "off" or "none".
  property string networkName: ""
  readonly property string networkState: {
    var wired = false, wifi = null
    for (var i = 0; i < netDevices.length; i++) {
      var d = netDevices[i]
      if (!d) continue
      if (d.type === DeviceType.Wifi && (!wifi || d.connected)) wifi = d
      else if (d.type === DeviceType.Wired && d.connected) wired = true
    }
    if (wifi && wifi.connected) {
      var nets = wifi.networks ? wifi.networks.values : []
      for (var k = 0; k < nets.length; k++) if (nets[k] && nets[k].connected && String(nets[k].name || "") !== "") return "ssid:" + BarModel.cleanText(nets[k].name, 64)
      return "connected"
    }
    if (wired) return "wired"
    if (!Networking.wifiEnabled) return "off"
    return "none"
  }
  readonly property string networkText: networkState.indexOf("ssid:") === 0 ? networkState.slice(5)
    : networkState === "connected" ? tr("network.connected") : networkState === "wired" ? tr("network.wired")
    : networkState === "off" ? tr("state.off") : tr("network.none")
  readonly property bool networkUp: networkState !== "off" && networkState !== "none"

  // Bluetooth: what is connected.
  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property var btDevices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property string bluetoothText: {
    if (!btAdapter) return tr("bluetooth.none")
    if (!btAdapter.enabled) return tr("state.off")
    var names = []
    for (var i = 0; i < btDevices.length; i++)
      if (btDevices[i] && btDevices[i].connected) names.push(BarModel.cleanText(btDevices[i].name || btDevices[i].deviceName, 48) || tr("bluetooth.device"))
    if (names.length === 0) return tr("state.on")
    return names.length === 1 ? names[0] : tr("bluetooth.more").arg(names[0]).arg(Commons.I18n.formatNumber(names.length - 1))
  }

  // Battery.
  readonly property var battery: UPower.displayDevice
  readonly property bool batteryPresent: !!(battery && battery.isPresent)
  readonly property int batteryPercent: batteryPresent ? Math.round(Math.max(0, Math.min(1, battery.percentage)) * 100) : 0
  readonly property bool charging: batteryPresent && !UPower.onBattery
  readonly property string batteryText: !batteryPresent ? tr("battery.ac") : tr("percent").arg(Commons.I18n.formatNumber(batteryPercent))

  // Workspaces. Omarchy 4.5 numbers each monitor's workspaces in a block of
  // ten and records the blocks in monitor-workspaces (see the stock workspaces widget).
  readonly property int wsSlots: 10
  property var blocks: ({})
  readonly property bool perMonitor: Object.keys(blocks).length > 0
  function readBlocks(text) {
    var next = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      var block = parseInt(fields[0], 10)
      if (fields.length >= 3 && fields[1] !== "" && !isNaN(block)) next[fields[1]] = block
    }
    blocks = next
  }
  FileView {
    id: blocksFile
    path: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readBlocks(text())
    onLoadFailed: root.readBlocks("")
  }
  function blockOf(id) { return Math.floor((id - 1) / wsSlots) }
  function slotOf(id) { return (id - 1) % wsSlots + 1 }
  function wsLabel(id) {
    if (!(id > 0)) return ""
    var number = perMonitor ? slotOf(id) : id
    return number === 10 ? "0" : String(number)
  }
  // Layout commands call `omarchy-shell omarchy.workspaces refresh`.
  ShellIpc {
    target: "omarchy.workspaces"
    function refresh(): void {
      blocksFile.reload()
      Hyprland.refreshMonitors()
      Hyprland.refreshWorkspaces()
    }
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (root.perMonitor && (name === "workspacev2" || name === "moveworkspacev2" || name === "changeworkspaceid")) {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
      // The screensaver is fullscreen on a special workspace, which does not
      // cover Top-layer surfaces: the rail steps aside for it.
      if (name === "openwindow" || name === "closewindow") {
        var parts = String(event.data).split(",")
        if (name === "openwindow") {
          if (parts[2] === "org.omarchy.screensaver") root.setScreensaverWindow(parts[0], true)
          else root.guardPage(parts[0], parts[1], parts[2])
        } else if (root.screensaverWindows[parts[0]]) {
          root.setScreensaverWindow(parts[0], false)
        }
      }
    }
  }
  function setScreensaverWindow(address, present) {
    var next = Object.assign({}, screensaverWindows)
    if (present) next[address] = true
    else delete next[address]
    screensaverWindows = next
    screensaverUp = Object.keys(next).length > 0
  }
  Process {
    running: true
    command: ["bash", "-c", "hyprctl clients -j | jq -r '.[] | select(.mapped and .class == \"org.omarchy.screensaver\") | .address | ltrimstr(\"0x\")'"]
    stdout: SplitParser { onRead: function(line) { var a = String(line).trim(); if (a) root.setScreensaverWindow(a, true) } }
  }

  // `omarchy toggle bar`: the bar-off flag hides the rail and frees its space.
  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { root.barHidden = String(line).trim() === "yes" } }
  }
  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }
  ShellIpc {
    target: "omarchy.bar"
    function syncHidden(): void { barHiddenProbe.running = true }
  }

  // ---- hosting the panel widgets -------------------------------------------------
  // The layout's widgets the sidebar keeps loaded for their panels and IPC
  // (BarModel.hostedEntries): not the ones it draws itself or has no place for.
  property var hostedEntries: []
  property string hostedKey: ""
  function hasWidget(id) {
    var w = root.barWidgetRegistry ? root.barWidgetRegistry.widgets : null
    return !!w && !!w[Util.canonicalWidgetId(id)]
  }
  function syncHostedEntries() {
    var next = BarModel.hostedEntries(layoutConfig, hasWidget)
    // Only a real change rebuilds the widgets (and closes their panels).
    var key = JSON.stringify(next)
    if (key === hostedKey) return
    hostedKey = key
    hostedEntries = next
  }
  onLayoutConfigChanged: { syncHostedEntries(); schedulePluginBarApiSync() }
  Connections {
    target: root.barWidgetRegistry
    ignoreUnknownSignals: true
    function onRevisionChanged() { root.syncHostedEntries() }
    function onWidgetsChanged() { root.syncHostedEntries() }
  }
  function kindOf(id) { return BarModel.panelKind(id) }

  function findPanelWidget(pluginId) {
    var id = String(pluginId || "")
    if (!id) return null
    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem || slot.moduleName !== id) continue
      var item = slot.activeItem
      if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
      candidates.push({ slot: slot, screenName: slotScreenName(slot), opened: item.opened === true })
    }
    var chosen = BarModel.pickPanelSlot(candidates, focusedScreenName())
    return chosen ? chosen.activeItem : null
  }
  // The hosted widget of a kind ("audio" -> omarchy.audio, or a clone of it).
  function panelIdFor(kind) {
    for (var i = 0; i < moduleSlots.length; i++)
      if (moduleSlots[i] && kindOf(moduleSlots[i].moduleName) === kind) return moduleSlots[i].moduleName
    return ""
  }
  function togglePanel(kind) {
    var item = findPanelWidget(panelIdFor(kind))
    if (!item) return false
    if (item.opened) item.close()
    else item.open()
    return true
  }
  function summonBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item) return false
    item.open()
    return true
  }
  function hideBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item) return false
    item.close()
    return true
  }
  function isBarWidgetOpen(pluginId) {
    var item = findPanelWidget(pluginId)
    return !!item && item.opened === true
  }
  function panelWidgetIdAt(region, index) { return "" }
  function switchPanelFrom(owner, direction) { return false }
  function moduleWidgets(pluginId) {
    var id = String(pluginId || "")
    var items = []
    if (!id) return items
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem && slot.moduleName === id) items.push(slot.activeItem)
    }
    return items
  }
  function targetWindow(target) { return target && target.QsWindow ? target.QsWindow.window : null }
  function targetBelongsToWindow(target, window) { return !!target && !!window && targetWindow(target) === window }
  function slotWindow(slot) { return slot ? (targetWindow(slot.activeItem) || targetWindow(slot)) : null }
  function slotScreenName(slot) {
    var window = slotWindow(slot)
    return window && window.screen ? String(window.screen.name || "") : ""
  }
  // The hosted widgets are never seen, so they have nothing to explain.
  function showTooltip(target, text) {}
  function hideTooltip(target) {}

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
  }
  function releasePopout(owner) { if (activePopout === owner) activePopout = null }
  // Where the open card stands, so a panel taking over from another starts
  // its card there (KeyboardPanel morphs between them). Every row is one
  // section of this bar.
  property var popoutCard: null
  function notePopoutCard(card) {
    popoutCard = card ? { screen: String(card.screen || ""), x: Number(card.x) || 0, y: Number(card.y) || 0,
                          width: Number(card.width) || 0, height: Number(card.height) || 0 } : null
  }
  function popoutCardFor(owner) {
    var card = popoutCard
    return card ? { screen: card.screen, x: card.x, y: card.y, width: card.width, height: card.height } : null
  }
  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }
  function unregisterClickTarget(target) { clickTargets = clickTargets.filter(function(item) { return item !== target }) }
  function registerModuleSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1) return
    var next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }
  function unregisterModuleSlot(slot) { moduleSlots = moduleSlots.filter(function(item) { return item !== slot }) }

  // The facade each third-party widget gets as its `bar` (as the stock bar does).
  property var pluginBarApis: ({})
  readonly property var pluginObjectOwners: new Map()
  property bool pluginBarApiSyncQueued: false
  Component { id: pluginBarApiComponent; PluginBarApi { } }

  function publicLayoutConfig() { return JSON.parse(JSON.stringify(root.layoutConfig || {})) }
  function bindPluginBarApi(api) {
    if (!api) return
    api.foreground = Qt.binding(function() { return root.foreground })
    api.barForeground = Qt.binding(function() { return root.barForeground })
    api.background = Qt.binding(function() { return root.background })
    api.urgent = Qt.binding(function() { return root.urgent })
    api.fontFamily = Qt.binding(function() { return root.fontFamily })
    api.position = Qt.binding(function() { return root.position })
    api.vertical = Qt.binding(function() { return root.vertical })
    api.barSize = Qt.binding(function() { return root.barSize })
    api.transparent = Qt.binding(function() { return root.transparent })
    api.foregroundAnimationEnabled = Qt.binding(function() { return root.foregroundAnimationEnabled })
    api.centerSectionRevealHeld = Qt.binding(function() { return root.centerSectionRevealHeld })
    api._centerHoverRevealSuppressed = Qt.binding(function() { return root.centerHoverRevealSuppressed })
    root.syncPluginBarApiObjects(api)
  }
  function syncPluginBarApiObjects(api, layoutSnapshot) {
    if (!api) return
    api.activePopout = root.pluginOwnsBarObject(api.pluginId, root.activePopout)
      ? root.activePopout : (root.activePopout ? api.foreignPopoutMarker : null)
    api.clickTargets = root.pluginClickTargets(api.pluginId)
    api.layoutConfig = layoutSnapshot !== undefined ? JSON.parse(layoutSnapshot) : root.publicLayoutConfig()
  }
  function pluginObjectRecord(target) { return target ? (pluginObjectOwners.get(target) || null) : null }
  function markPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    if (!key || !target) return false
    var record = root.pluginObjectRecord(target)
    if (record && record.pluginId !== key) return false
    if (!record) {
      record = { target: target, pluginId: key, clickTarget: false, popout: false }
      pluginObjectOwners.set(target, record)
    }
    record[role] = true
    return true
  }
  function unmarkPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    var record = root.pluginObjectRecord(target)
    if (!record || record.pluginId !== key) return
    record[role] = false
    if (!record.clickTarget && !record.popout) pluginObjectOwners.delete(target)
  }
  function pluginOwnsBarObject(pluginId, target) {
    var record = target ? root.pluginObjectRecord(target) : null
    return !!record && record.pluginId === String(pluginId || "")
  }
  function pluginClickTargets(pluginId) {
    var out = []
    for (var i = 0; i < root.clickTargets.length; i++)
      if (root.pluginOwnsBarObject(pluginId, root.clickTargets[i])) out.push(root.clickTargets[i])
    return out
  }
  function schedulePluginBarApiSync() {
    if (pluginBarApiSyncQueued) return
    pluginBarApiSyncQueued = true
    Qt.callLater(root.syncAllPluginBarApiObjects)
  }
  function syncAllPluginBarApiObjects() {
    pluginBarApiSyncQueued = false
    var layoutSnapshot = JSON.stringify(root.layoutConfig || {})
    for (var id in pluginBarApis) if (pluginBarApis[id]) root.syncPluginBarApiObjects(pluginBarApis[id], layoutSnapshot)
  }
  function registerPluginClickTarget(pluginId, target) {
    if (!root.markPluginObject(pluginId, target, "clickTarget")) return
    root.registerClickTarget(target)
  }
  function unregisterPluginClickTarget(pluginId, target) {
    if (!root.pluginOwnsBarObject(pluginId, target)) return
    root.unregisterClickTarget(target)
    root.unmarkPluginObject(pluginId, target, "clickTarget")
  }
  function requestPluginPopout(pluginId, owner) {
    if (!root.markPluginObject(pluginId, owner, "popout")) return
    root.requestPopout(owner)
    root.syncPluginBarApiObjects(pluginBarApis[String(pluginId || "")])
  }
  function releasePluginPopout(pluginId, owner) {
    if (!root.pluginOwnsBarObject(pluginId, owner)) return
    root.releasePopout(owner)
    root.unmarkPluginObject(pluginId, owner, "popout")
    root.syncPluginBarApiObjects(pluginBarApis[String(pluginId || "")])
  }
  function pluginBarApiFor(pluginId, moduleName, registered) {
    var key = String(pluginId || "")
    if (!key) return null
    var pluginShell = null
    if (registered && root.shell && typeof root.shell.pluginShellForId === "function")
      pluginShell = root.shell.pluginShellForId(moduleName)
    else if (root.shell && typeof root.shell.pluginShellForBarEntry === "function")
      pluginShell = root.shell.pluginShellForBarEntry(key, moduleName)
    if (pluginBarApis[key]) {
      pluginBarApis[key].shell = pluginShell
      return pluginBarApis[key]
    }
    var api = pluginBarApiComponent.createObject(null, {
      pluginId: key,
      moduleName: String(moduleName || ""),
      shell: pluginShell,
      _showTooltip: function(target, text) { root.showTooltip(target, text) },
      _hideTooltip: function(target) { root.hideTooltip(target) },
      _registerClickTarget: function(target) { root.registerPluginClickTarget(key, target) },
      _unregisterClickTarget: function(target) { root.unregisterPluginClickTarget(key, target) },
      _requestPopout: function(owner) { root.requestPluginPopout(key, owner) },
      _releasePopout: function(owner) { root.releasePluginPopout(key, owner) },
      _switchPanelFrom: function(owner, direction) { return root.switchPanelFrom(owner, direction) },
      _targetBelongsToWindow: function(target, window) { return root.targetBelongsToWindow(target, window) },
      _moduleWidgets: function(requestedId) {
        return String(requestedId || "") === String(moduleName || "") ? root.moduleWidgets(moduleName) : []
      },
      _run: function(command) { root.run(command) },
      _setCenterHoverRevealSuppressed: function(value) { root.centerHoverRevealSuppressed = !!value }
    })
    if (!api) return null
    root.bindPluginBarApi(api)
    var next = ({})
    for (var id in pluginBarApis) next[id] = pluginBarApis[id]
    next[key] = api
    pluginBarApis = next
    return api
  }
  function pluginBarApiUsed(pluginId) {
    for (var i = 0; i < moduleSlots.length; i++)
      if (moduleSlots[i] && moduleSlots[i].pluginApiId === pluginId) return true
    return false
  }
  function releasePluginObjects(pluginId) {
    var owned = Array.from(pluginObjectOwners.values())
    for (var i = 0; i < owned.length; i++) {
      var record = owned[i]
      if (!record || record.pluginId !== pluginId) continue
      if (record.clickTarget) root.unregisterClickTarget(record.target)
      if (record.popout && root.activePopout === record.target) root.releasePopout(record.target)
      pluginObjectOwners.delete(record.target)
    }
  }
  function prunePluginBarApis() {
    var next = ({})
    for (var id in pluginBarApis) {
      var api = pluginBarApis[id]
      if (root.pluginBarApiUsed(id)) { next[id] = api; continue }
      root.releasePluginObjects(id)
      if (api && typeof api.destroy === "function") api.destroy()
    }
    pluginBarApis = next
  }
  onActivePopoutChanged: schedulePluginBarApiSync()
  onClickTargetsChanged: schedulePluginBarApiSync()
  onModuleSlotsChanged: Qt.callLater(prunePluginBarApis)

  Component.onCompleted: syncHostedEntries()
  Component.onDestruction: {
    for (var id in pluginBarApis) {
      root.releasePluginObjects(id)
      if (pluginBarApis[id] && typeof pluginBarApis[id].destroy === "function") pluginBarApis[id].destroy()
    }
    pluginBarApis = ({})
  }

  // ---- drawing kit -------------------------------------------------------------
  // 24-unit line icons, as drawn in the design file.
  readonly property var icons: ({
    search: "M4 11a7 7 0 1 0 14 0a7 7 0 1 0 -14 0M20 20l-3.5 -3.5",
    inbox: "M22 12h-6l-2 3h-4l-2 -3H2M5.5 5.1L2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2 -2v-6l-3.5 -6.9A2 2 0 0 0 16.8 4H7.2a2 2 0 0 0 -1.7 1.1z",
    agents: "M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M18.4 5.6l-2.1 2.1M7.7 16.3l-2.1 2.1",
    wifi: "M2.5 9a14 14 0 0 1 19 0M5.8 12.6a9.5 9.5 0 0 1 12.4 0M9 16.2a5 5 0 0 1 6 0M11.2 19.5a0.8 0.8 0 1 0 1.6 0a0.8 0.8 0 1 0 -1.6 0",
    sound: "M4 9.5v5h3.5L12 18V6L7.5 9.5zM15.5 9a4.2 4.2 0 0 1 0 6M18.3 6.5a8 8 0 0 1 0 11",
    mute: "M4 9.5v5h3.5L12 18V6L7.5 9.5zM16 9.5l5 5M21 9.5l-5 5",
    bluetooth: "M7 7.5l10 9l-5 4.5V3l5 4.5l-10 9",
    battery: "M5 7.5h11a2.5 2.5 0 0 1 2.5 2.5v4a2.5 2.5 0 0 1 -2.5 2.5h-11a2.5 2.5 0 0 1 -2.5 -2.5v-4a2.5 2.5 0 0 1 2.5 -2.5zM21.5 11v2M6 10.5v3M9 10.5v3M12 10.5v3",
    sidebar: "M6 4h12a3 3 0 0 1 3 3v10a3 3 0 0 1 -3 3h-12a3 3 0 0 1 -3 -3v-10a3 3 0 0 1 3 -3zM9 4v16",
    terminal: "M6 4h12a3 3 0 0 1 3 3v10a3 3 0 0 1 -3 3h-12a3 3 0 0 1 -3 -3v-10a3 3 0 0 1 3 -3zM7 10l3 2.5L7 15M13 15h4",
    globe: "M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18",
    folder: "M3 7a2 2 0 0 1 2 -2h4l2 2.5h8a2 2 0 0 1 2 2V17a2 2 0 0 1 -2 2H5a2 2 0 0 1 -2 -2z",
    plus: "M12 5v14M5 12h14",
    chevron: "M6 9l6 6l6 -6",
    caret: "M7 9h10l-5 7z",
    prompt: "M5 8l4 4l-4 4M12 17h7",
    app: "M6.5 5h11a2.5 2.5 0 0 1 2.5 2.5v9a2.5 2.5 0 0 1 -2.5 2.5h-11a2.5 2.5 0 0 1 -2.5 -2.5v-9a2.5 2.5 0 0 1 2.5 -2.5zM4 9.5h16",
    pin: "M12 17v5M9 3h6l-1 6l3 3v2H7v-2l3 -3z",
    power: "M12 3v8M6.3 7a8 8 0 1 0 11.4 0"
  })
  // Busy windows spin a glyph at the front of their title; dropped, so the
  // sidebar does not redraw for as long as they work (BarModel.steadyTitle).
  function steadyTitle(title) { return BarModel.steadyTitle(title) }
  function windowIcon(appId) {
    var id = String(appId || "").toLowerCase()
    if (/(foot|alacritty|kitty|ghostty|wezterm|terminal|konsole)/.test(id)) return "prompt"
    if (/(brave|chrom|firefox|zen|librewolf|vivaldi|epiphany|browser)/.test(id)) return "globe"
    return "app"
  }

  // The finish at a pane's edge (after Solid Glass): a hairline all round and
  // a line of light along the top that follows the corners. Put one inside a
  // rounded Rectangle; it fills its parent.
  //   kind "pane" a card, "control" small clear glass, "state" the one
  //   state (hovered, chosen, held open), "ink" the solid pane.
  component SolidEdge: Item {
    id: edgeRoot
    property real radius: parent && parent.radius !== undefined ? parent.radius : 0
    property string kind: "pane"
    property bool shown: true
    property color rimColor: kind === "control" ? root.sg.controlRim
      : kind === "state" ? root.sg.stateRim
      : kind === "ink" ? root.sg.primaryRim : root.sg.rim
    property color edgeColor: kind === "state" ? root.sg.stateEdge
      : kind === "ink" ? "transparent" : root.sg.edge
    property color underColor: kind === "ink" ? root.sg.primaryUnder : "transparent"
    anchors.fill: parent
    visible: shown && width > 2 && height > 2
    z: 1000
    readonly property real r: Math.max(0, Math.min(radius, width / 2, height / 2))
    // The outline as an SVG path, at its place and moved one pixel down or
    // up. Built inside the binding: a method called from a binding outlives
    // its context when a plugin reloads.
    readonly property var paths: {
      var w = width, h = height, k = r
      var rr = function(y) {
        if (k <= 0) return "M0," + y + " H" + w + " V" + (y + h) + " H0 Z"
        return "M" + k + "," + y + " H" + (w - k) + " A" + k + "," + k + " 0 0 1 " + w + "," + (y + k)
          + " V" + (y + h - k) + " A" + k + "," + k + " 0 0 1 " + (w - k) + "," + (y + h)
          + " H" + k + " A" + k + "," + k + " 0 0 1 0," + (y + h - k)
          + " V" + (y + k) + " A" + k + "," + k + " 0 0 1 " + k + "," + y + " Z"
      }
      return { top: rr(0) + " " + rr(1), bottom: rr(0) + " " + rr(-1) }
    }
    Rectangle {
      anchors.fill: parent
      radius: edgeRoot.r
      color: "transparent"
      border.width: 1
      border.color: edgeRoot.edgeColor
      visible: edgeRoot.edgeColor.a > 0
    }
    Item {
      width: parent.width
      height: Math.min(parent.height, edgeRoot.r + 2)
      clip: true
      visible: edgeRoot.rimColor.a > 0
      Shape {
        width: edgeRoot.width
        height: edgeRoot.height
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeWidth: -1
          strokeColor: "transparent"
          fillColor: edgeRoot.rimColor
          fillRule: ShapePath.OddEvenFill
          PathSvg { path: edgeRoot.paths.top }
        }
      }
    }
    Item {
      y: parent.height - height
      width: parent.width
      height: Math.min(parent.height, edgeRoot.r + 2)
      clip: true
      visible: edgeRoot.underColor.a > 0
      Shape {
        y: -(edgeRoot.height - parent.height)
        width: edgeRoot.width
        height: edgeRoot.height
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeWidth: -1
          strokeColor: "transparent"
          fillColor: edgeRoot.underColor
          fillRule: ShapePath.OddEvenFill
          PathSvg { path: edgeRoot.paths.bottom }
        }
      }
    }
  }

  component Glyph: Item {
    id: glyph
    property string name: ""
    property color color: root.cMuted
    property real size: 16
    property real stroke: 1.8
    property bool filled: false
    width: size
    height: size
    Shape {
      width: 24
      height: 24
      scale: glyph.size / 24
      transformOrigin: Item.TopLeft
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: glyph.filled ? "transparent" : glyph.color
        strokeWidth: glyph.filled ? -1 : glyph.stroke
        fillColor: glyph.filled ? glyph.color : "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: root.icons[glyph.name] || "" }
      }
    }
  }

  // Every string that comes from outside (titles, network and device names)
  // is drawn as plain text.
  component Label: Text {
    textFormat: Text.PlainText
    color: root.cFg
    font.family: root.fontFamily
    font.pixelSize: 13
    elide: Text.ElideRight
    maximumLineCount: 1
    renderType: Text.NativeRendering
  }

  // A numbered workspace chip: the ink when it is the one shown, an outline
  // when it holds windows, dashed and dim when empty.
  component Chip: Item {
    id: chip
    property real size: 18
    property string text: ""
    property string kind: "solid"
    width: size
    height: size
    Rectangle {
      anchors.fill: parent
      visible: chip.kind !== "dashed"
      radius: Math.round(chip.size / 3)
      color: chip.kind === "ink" ? root.sg.primary : "transparent"
      border.width: chip.kind === "solid" ? 1 : 0
      border.color: root.sg.rim
      SolidEdge { kind: "ink"; shown: chip.kind === "ink" }
    }
    Shape {
      anchors.fill: parent
      visible: chip.kind === "dashed"
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: root.sg.rim
        strokeWidth: 1
        fillColor: "transparent"
        strokeStyle: ShapePath.DashLine
        dashPattern: [2, 2]
        PathRectangle { x: 0.5; y: 0.5; width: chip.size - 1; height: chip.size - 1; radius: Math.round(chip.size / 3) }
      }
    }
    Label {
      anchors.centerIn: parent
      text: chip.text
      elide: Text.ElideNone
      font.family: root.mono
      font.pixelSize: 10
      font.weight: chip.kind === "ink" ? Font.DemiBold : Font.Medium
      color: chip.kind === "ink" ? root.sg.primaryFg : chip.kind === "dashed" ? root.cFaint : root.cMuted
    }
  }

  // A small groove with its level.
  component Track: Item {
    id: track
    property real value: 0
    property bool quiet: false
    height: 6
    width: 72
    Rectangle { anchors.fill: parent; radius: height / 2; color: root.sg.wellShade; border.width: 1; border.color: root.sg.wellRim }
    Rectangle {
      width: Math.round(Math.max(0, Math.min(1, track.value)) * parent.width)
      height: parent.height
      radius: height / 2
      visible: width >= height
      color: track.quiet ? root.cFaint : root.sg.primary
    }
  }

  // One 32px cell of the rail.
  component RailCell: Item {
    id: cell
    property var host: null
    property string icon: ""
    property string tip: ""
    property string tipValue: ""
    property bool armed: false
    // The list draws the armed fill itself (a FlowPill).
    property bool flow: false
    property bool lit: false
    readonly property bool hovered: cellMouse.containsMouse
    default property alias content: cellHolder.data
    // Opens a panel: while a card is up its overlay covers the bar, and
    // passes a click here on (KeyboardPanel's clickTargets), so one click
    // switches cards.
    property bool panelTarget: false
    function triggerPress(button) { if (button === Qt.LeftButton) clicked() }
    Component.onCompleted: if (panelTarget) root.registerClickTarget(cell)
    Component.onDestruction: root.unregisterClickTarget(cell)
    signal clicked()
    signal scrolled(real delta)
    width: 32
    height: 32
    Rectangle {
      anchors.fill: parent
      radius: 9
      visible: cell.armed ? !cell.flow : cellMouse.containsMouse
      color: cell.armed ? root.sg.state : cellMouse.pressed ? root.sg.hover : root.sg.hoverFaint
      SolidEdge { kind: "state"; shown: cell.armed && !cell.flow }
    }
    Glyph {
      anchors.centerIn: parent
      visible: cell.icon !== ""
      name: cell.icon
      size: cell.icon === "sidebar" ? 15 : 16
      color: cell.lit || cellMouse.containsMouse ? root.cFg : root.cMuted
    }
    Item { id: cellHolder; anchors.fill: parent }
    MouseArea {
      id: cellMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: cell.clicked()
      onWheel: function(wheel) { cell.scrolled(wheel.angleDelta.y) }
      onContainsMouseChanged: if (cell.host) { if (containsMouse) cell.host.showTip(cell); else cell.host.hideTip(cell) }
    }
  }

  // The armed fill of a list, as one pill that flows from row to row: the edge
  // facing the move leads and the other follows, so it stretches and settles.
  component FlowPill: Item {
    id: pill
    property bool active: false
    property real targetY: 0
    property real rowHeight: 30
    property real topY: 0
    property real botY: rowHeight
    property bool down: true
    // False until it has a place: it appears where it belongs, then moves.
    property bool settled: false
    function place() {
      if (!active) { settled = false; return }
      down = targetY > topY
      topY = targetY
      botY = targetY + rowHeight
      if (!settled) Qt.callLater(function() { pill.settled = pill.active })
    }
    onTargetYChanged: place()
    onActiveChanged: place()
    Component.onCompleted: place()
    Behavior on topY { enabled: pill.settled; NumberAnimation { duration: Style.duration(pill.down ? 340 : 200); easing.type: Easing.OutCubic } }
    Behavior on botY { enabled: pill.settled; NumberAnimation { duration: Style.duration(pill.down ? 200 : 340); easing.type: Easing.OutCubic } }
    y: topY
    height: Math.max(rowHeight, botY - topY)
    opacity: active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Style.duration(120) } }
    Rectangle {
      anchors.fill: parent
      radius: 9
      color: root.sg.state
      SolidEdge { kind: "state"; shown: true }
    }
  }

  // One 30px row of the sidebar: icon (or chip), label, and what trails it.
  component SideRow: Item {
    id: row
    property string icon: ""
    property string label: ""
    property color labelColor: root.cLabel
    property string chipText: ""
    property string chipKind: "solid"
    property bool armed: false
    // The list draws the armed fill itself (a FlowPill).
    property bool flow: false
    property bool wheelEnabled: false
    // A row with a host and a tip explains itself on hover (win.showTip).
    property var host: null
    property string tip: ""
    property string tipValue: ""
    readonly property bool wideTip: true
    readonly property bool hovered: rowMouse.containsMouse
    // A row whose label can be retyped in place: double-click or right-click
    // asks for it, Enter keeps what was typed, Escape leaves it as it was.
    property bool editable: false
    property bool editing: false
    property string editText: ""
    property string editHint: ""
    default property alias trailing: rowTrail.data
    property bool panelTarget: false
    function triggerPress(button) { if (button === Qt.LeftButton && !editing) clicked() }
    Component.onCompleted: if (panelTarget) root.registerClickTarget(row)
    Component.onDestruction: root.unregisterClickTarget(row)
    signal clicked()
    signal scrolled(real delta)
    signal editRequested()
    signal edited(string text)
    signal editCancelled()
    onEditingChanged: {
      if (!editing) return
      rowEdit.text = editText
      rowEdit.forceActiveFocus()
      rowEdit.selectAll()
    }
    width: parent ? parent.width : 0
    height: 30
    Rectangle {
      anchors.fill: parent
      radius: 9
      visible: row.armed ? !row.flow : rowMouse.containsMouse
      color: row.armed ? root.sg.state : rowMouse.pressed ? root.sg.hover : root.sg.hoverFaint
      SolidEdge { kind: "state"; shown: row.armed && !row.flow }
    }
    Glyph {
      x: 8
      anchors.verticalCenter: parent.verticalCenter
      visible: row.icon !== "" && row.chipText === ""
      name: row.icon
      color: rowMouse.containsMouse ? root.cFg : root.cMuted
    }
    Chip {
      x: 8
      anchors.verticalCenter: parent.verticalCenter
      visible: row.chipText !== ""
      size: 16
      text: row.chipText
      kind: row.chipKind
    }
    Label {
      x: 34
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, rowTrail.x - x - 10)
      text: row.label
      color: row.labelColor
      font.weight: Font.Medium
      visible: !row.editing
    }
    Rectangle {
      visible: row.editing
      x: 28
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, rowTrail.x - x - 4)
      height: 22
      radius: 6
      color: root.sg.well
      border.width: 1
      border.color: root.sg.border
    }
    TextInput {
      id: rowEdit
      x: 34
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, rowTrail.x - x - 10)
      visible: row.editing
      enabled: row.editing
      clip: true
      maximumLength: 32
      selectByMouse: true
      color: root.cFg
      selectionColor: Qt.rgba(root.cFg.r, root.cFg.g, root.cFg.b, 0.22)
      selectedTextColor: root.cFg
      font.family: root.fontFamily
      font.pixelSize: 13
      font.weight: Font.Medium
      renderType: Text.NativeRendering
      onAccepted: row.edited(text)
      Keys.onEscapePressed: row.editCancelled()
      Label {
        visible: rowEdit.text === ""
        text: row.editHint
        color: root.cFaint
        font.weight: Font.Medium
      }
    }
    Row {
      id: rowTrail
      anchors.right: parent.right
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6
      z: 1
    }
    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      enabled: !row.editing
      acceptedButtons: row.editable ? Qt.LeftButton | Qt.RightButton : Qt.LeftButton
      onClicked: function(mouse) {
        if (row.host) row.host.hideTip(row)
        if (mouse.button === Qt.RightButton) row.editRequested()
        else row.clicked()
      }
      onDoubleClicked: function(mouse) { if (row.editable && mouse.button === Qt.LeftButton) row.editRequested() }
      onContainsMouseChanged: if (row.host) { if (containsMouse) row.host.showTip(row); else row.host.hideTip(row) }
      onWheel: function(wheel) {
        if (row.wheelEnabled) row.scrolled(wheel.angleDelta.y)
        else wheel.accepted = false
      }
    }
  }

  // The windows of one workspace or page, as rows under its own row.
  component WindowList: Item {
    id: windowList
    property var windows: []
    property var host: null
    visible: height > 0.5
    width: parent ? parent.width : 0
    height: windows.length > 0 ? windowColumn.height + 4 : 0
    clip: true
    Behavior on height { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
    Rectangle { x: 15; width: 1; height: parent.height; color: root.sg.border }
    Column {
      id: windowColumn
      x: 26
      y: 2
      width: parent.width - 26
      spacing: 1
      Repeater {
        model: windowList.windows
        Item {
          id: windowRow
          required property var modelData
          readonly property bool focused: !!modelData && modelData.activated === true
          readonly property var playing: modelData ? root.soundByWindow[String(modelData.address || "")] || null : null
          readonly property string appId: modelData && modelData.wayland ? String(modelData.wayland.appId || "") : ""
          width: parent.width
          height: 28
          Rectangle {
            anchors.fill: parent
            radius: 9
            visible: windowRow.focused || windowMouse.containsMouse
            color: windowMouse.pressed ? root.sg.hover : root.sg.hoverFaint
          }
          Glyph {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            name: root.windowIcon(windowRow.appId)
            size: 14
            color: windowRow.focused ? root.cFg : root.cMuted
          }
          Label {
            x: 31
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 31 - 6 - (windowSound.visible ? windowSound.width : 0)
            text: windowRow.modelData ? (root.steadyTitle(windowRow.modelData.title) || windowRow.appId || root.tr("window.untitled")) : ""
            color: windowRow.focused ? root.cFg : root.cTitle
          }
          MouseArea {
            id: windowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (windowRow.modelData) root.focusWindow(windowRow.modelData.address)
            onWheel: function(wheel) { wheel.accepted = false }
          }
          // This window is making sound. Over the row's own
          // mouse area, so a click here mutes the app's
          // stream and does not focus the window.
          Item {
            id: windowSound
            readonly property string tip: !windowRow.playing ? "" : windowRow.playing.muted ? root.tr("sound.muted") : root.tr("sound.playing")
            readonly property string tipValue: windowRow.playing ? windowRow.playing.media : ""
            readonly property bool wideTip: true
            visible: !!windowRow.playing
            anchors.right: parent.right
            anchors.rightMargin: 3
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            onVisibleChanged: if (!visible) windowList.host.hideTip(windowSound)
            Component.onDestruction: windowList.host.hideTip(windowSound)
            Rectangle {
              anchors.fill: parent
              radius: 7
              visible: windowSoundMouse.containsMouse
              color: windowSoundMouse.pressed ? root.sg.hover : root.sg.hoverFaint
            }
            Glyph {
              anchors.centerIn: parent
              name: windowRow.playing && windowRow.playing.muted ? "mute" : "sound"
              size: 14
              color: windowRow.playing && windowRow.playing.muted ? root.sg.mutedFg : root.sg.foreground
            }
            MouseArea {
              id: windowSoundMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (windowRow.modelData) root.toggleWindowSound(windowRow.modelData.address)
              onContainsMouseChanged: { if (containsMouse) windowList.host.showTip(windowSound); else windowList.host.hideTip(windowSound) }
              onWheel: function(wheel) { wheel.accepted = false }
            }
          }
        }
      }
    }
  }

  // A 28px button in the sidebar's header and footer.
  component SideButton: Item {
    id: button
    property string icon: ""
    property bool raised: false
    signal clicked()
    width: 28
    height: 28
    Rectangle {
      anchors.fill: parent
      radius: 9
      visible: button.raised || buttonMouse.containsMouse
      color: button.raised ? (buttonMouse.containsMouse ? root.sg.stateArmed : root.sg.control) : buttonMouse.pressed ? root.sg.hover : root.sg.hoverFaint
      SolidEdge { kind: "control"; shown: button.raised }
    }
    Glyph {
      anchors.centerIn: parent
      name: button.icon
      size: 15
      stroke: button.icon === "plus" || button.icon === "search" ? 2 : 1.8
      color: button.raised || buttonMouse.containsMouse ? root.cFg : root.cMuted
    }
    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }
  }

  // A bar widget kept loaded for its panel and IPC, drawn nowhere: zero size,
  // parked at the centre of the cell or row that opens it.
  component HostedSlot: Item {
    id: slot
    required property var modelData
    property var host: null
    readonly property var entry: modelData
    readonly property string region: "hosted"
    readonly property string moduleName: BarModel.entryId(entry)
    readonly property var moduleSettings: BarModel.entrySettings(entry)
    readonly property var registryMetadata: root.barWidgetRegistry.metadataFor(Util.canonicalWidgetId(moduleName))
    readonly property bool firstParty: !!registryMetadata && registryMetadata.firstParty === true
    readonly property var registryComponent: {
      var w = root.barWidgetRegistry.widgets
      var found = w ? w[Util.canonicalWidgetId(slot.moduleName)] : null
      return found ? found.component : null
    }
    readonly property bool registered: registryComponent !== null
    readonly property string pluginApiId: registered ? Util.canonicalWidgetId(moduleName) : "bar-entry:" + moduleName
    readonly property var activeItem: slotLoader.item
    readonly property bool hovered: false
    parent: host ? host.homeFor(moduleName) : null
    width: 0
    height: 0
    clip: true
    opacity: 0
    enabled: false
    // Not just transparent: a widget that animates while merely see-through
    // (a spinner, a ticking island) makes the whole sidebar redraw about ten
    // times a second. Its panels open the same either way.
    visible: false

    Component.onCompleted: root.registerModuleSlot(slot)
    Component.onDestruction: {
      // Qt makes a registry Component the child of the first Loader that
      // shows it, so it would die with this Loader and leave the next bar
      // with a dead panel. Hand it back first.
      slotLoader.sourceComponent = null
      root.unregisterModuleSlot(slot)
    }

    Loader {
      id: slotLoader
      active: slot.registered
      sourceComponent: slot.registered ? slot.registryComponent : null
      anchors.fill: parent
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }
    onActiveItemChanged: Qt.callLater(injectProps)
    onModuleSettingsChanged: injectProps()
    function injectProps() {
      var target = activeItem
      if (!target) return
      if ("bar" in target) target.bar = firstParty ? root : root.pluginBarApiFor(pluginApiId, moduleName, registered)
      if ("moduleName" in target) target.moduleName = moduleName
      if ("settings" in target) target.settings = moduleSettings
    }
  }

  // ---- one window per screen ------------------------------------------------------
  Variants {
    model: Quickshell.screens
    delegate: Component {
      SidebarWindow {}
    }
  }

  component SidebarWindow: PanelWindow {
    id: win
    required property var modelData
    screen: modelData
    readonly property string screenName: screen ? String(screen.name) : ""
    readonly property bool wide: root.pinned || (root.floatOpen && root.floatScreen === screenName)
    readonly property bool floating: wide && !root.pinned
    // Where the visible sidebar ends. Panels stand off this line (PopupPanel
    // reads it while Solid Glass is on); the window itself is always wide
    // enough for the floating card and its shadow.
    readonly property real sidebarEdge: wide ? (root.pinned ? root.wideWidth : root.wideWidth + root.cardInset) : root.railWidth
    // 0 the rail, 1 the sidebar.
    property real t: wide ? 1 : 0
    Behavior on t { NumberAnimation { duration: Style.duration(win.wide ? 200 : 130); easing.type: Easing.OutCubic } }
    // The card's own presence, so pinning and unpinning never flash it.
    property real cardT: floating ? 1 : 0
    Behavior on cardT { NumberAnimation { duration: Style.duration(win.floating ? 200 : 130); easing.type: Easing.OutCubic } }

    visible: !root.barParked
    color: "transparent"
    surfaceFormat.opaque: false
    anchors { top: true; bottom: true; left: true }
    // Sized for the widest sidebar, so a resize drag never resizes the layer
    // surface under the pointer; input only reaches inputArea.
    implicitWidth: root.cardInset + root.maxWidth + root.shadowRoom
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: root.pinned ? root.wideWidth : root.railWidth
    mask: Region { item: inputArea }
    WlrLayershell.namespace: "sidecar"
    WlrLayershell.layer: WlrLayer.Top
    // Only a sidebar opened from the keyboard takes it: one the pointer opened
    // must not pull the keys away from the window being typed in.
    WlrLayershell.keyboardFocus: wide && root.renamingWs > 0 && root.renamingScreen === screenName ? WlrKeyboardFocus.Exclusive
      : !floating || !root.held ? WlrKeyboardFocus.None
      : root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive

    // ---- this screen's workspaces ----
    readonly property var monitor: screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
    readonly property string monitorName: monitor ? String(monitor.name) : ""
    readonly property int shownId: {
      if (root.perMonitor) return monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
      return Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    }
    readonly property int block: {
      if (!root.perMonitor) return 0
      var known = root.blocks[monitorName]
      if (known !== undefined) return known
      return shownId > 0 ? root.blockOf(shownId) : 0
    }
    // A string, so the rows are rebuilt only when the list itself changes.
    readonly property string wsKey: {
      var all = Hyprland.workspaces.values
      var ids, i
      if (!root.perMonitor) {
        ids = [1, 2, 3, 4, 5]
        for (i = 0; i < all.length; i++) {
          var id = all[i].id
          if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
        }
        ids.sort(function(a, b) { return a - b })
        return ids.join(",")
      }
      var base = block * root.wsSlots
      var own = [base + 1, base + 2, base + 3, base + 4, base + 5]
      var guests = []
      for (i = 0; i < all.length; i++) {
        var wid = all[i].id
        if (wid <= 0) continue
        if (root.blockOf(wid) === block) { if (own.indexOf(wid) === -1) own.push(wid) }
        else if (all[i].monitor && all[i].monitor.name === monitorName) guests.push(wid)
      }
      own.sort(function(a, b) { return a - b })
      guests.sort(function(a, b) { return a - b })
      return own.concat(guests).join(",")
    }
    readonly property var wsIds: wsKey.split(",").map(function(part) { return parseInt(part, 10) })
    function focusWorkspace(id) {
      var safeMonitor = BarModel.safeMonitorName(monitorName)
      if (root.perMonitor && safeMonitor !== "" && root.blockOf(id) === block)
        root.dispatch("o.workspaces.focus(" + root.slotOf(id) + ", \"" + safeMonitor + "\")")
      else
        root.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
    }
    property real wsWheel: 0
    property int pendingId: -1
    onShownIdChanged: if (shownId === pendingId) pendingId = -1
    Timer { id: pendingReset; interval: 600; onTriggered: win.pendingId = -1 }
    function scrollWorkspaces(delta) {
      var wheel = Util.wheelSteps(wsWheel, delta)
      wsWheel = wheel.remainder
      if (wheel.steps === 0) return
      var list = wsIds
      var from = pendingId > 0 && list.indexOf(pendingId) !== -1 ? pendingId : shownId
      var index = list.indexOf(from)
      if (index === -1) return
      var next = list[Math.max(0, Math.min(list.length - 1, index - wheel.steps))]
      if (next === from) return
      pendingId = next
      pendingReset.restart()
      focusWorkspace(next)
    }
    function focusEmptyWorkspace() {
      var all = Hyprland.workspaces.values
      for (var i = 0; i < wsIds.length; i++) {
        var busy = false
        for (var k = 0; k < all.length; k++)
          if (all[k].id === wsIds[i] && all[k].toplevels.values.length > 0) { busy = true; break }
        if (!busy) { focusWorkspace(wsIds[i]); return }
      }
    }

    // ---- where the hosted widgets park ----
    function homeFor(id) {
      var kind = root.kindOf(id)
      var s = win.wide && side.item ? side.item : null
      if (s) return kind === "agents" ? s.agentsHome : kind === "network" ? s.networkHome : kind === "audio" ? s.audioHome
        : kind === "bluetooth" ? s.bluetoothHome : kind === "power" ? s.powerHome : s.otherHome
      return kind === "agents" ? railAgentsHome : kind === "network" ? railNetworkHome : kind === "audio" ? railAudioHome
        : kind === "bluetooth" ? railBluetoothHome : kind === "power" ? railPowerHome : railOtherHome
    }

    // ---- tooltips, to the right of the rail ----
    property var tipCell: null
    property real tipY: 0
    function showTip(cell) {
      if (!cell || !cell.tip) return
      tipY = cell.mapToItem(surface, 0, cell.height / 2).y
      tipCell = cell
    }
    function hideTip(cell) { if (tipCell === cell) tipCell = null }
    onWideChanged: tipCell = null
    // Opened from the keyboard: Escape has to land here.
    onFloatingChanged: if (floating && root.held) surface.forceActiveFocus()

    Item {
      id: inputArea
      // Out, it reaches 4px past the edge: the outer half of the resize handle.
      width: win.wide ? win.sidebarEdge + 4 : root.railWidth
      height: win.height
    }

    FocusScope {
      id: surface
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.collapse()

      HoverHandler {
        onHoveredChanged: root.pointerChanged(win.screenName, hovered)
        onPointChanged: if (hovered) root.pointerMoved(point.position)
        Component.onDestruction: if (hovered) root.pointerChanged(win.screenName, false)
      }

      // The page under the rail. In the scrolling layout, columns that have
      // scrolled off to the left are still drawn across the reserved strip,
      // so without this they show through behind the rows.
      Rectangle {
        x: 0
        y: 0
        width: root.pinned ? root.wideWidth : root.railWidth
        height: parent.height
        color: Qt.rgba(root.sg.page.r, root.sg.page.g, root.sg.page.b, 1)
      }

      // The floating card: popover glass, inset from the screen edge. The
      // shadow stays under Hyprland's blur ignore_alpha so only the card is
      // frosted.
      RectangularShadow {
        visible: win.cardT > 0
        x: card.x
        y: card.y + 14
        width: card.width
        height: card.height
        radius: card.radius
        blur: 40
        spread: -12
        color: Qt.rgba(root.sg.shade.r, root.sg.shade.g, root.sg.shade.b, Math.min(0.46, root.sg.shade.a))
        opacity: win.cardT
      }
      Rectangle {
        id: card
        visible: win.cardT > 0
        x: root.cardInset - (1 - win.cardT) * 8
        y: root.cardInset
        width: root.wideWidth
        height: parent.height - root.cardInset * 2
        radius: 20
        color: root.sg.popover
        opacity: win.cardT
        SolidEdge { edgeColor: root.sg.popoverEdge }
      }

      // ---- the rail ----
      Item {
        id: rail
        width: root.railWidth
        height: parent.height
        opacity: 1 - win.t
        visible: opacity > 0
        enabled: !win.wide

        Column {
          anchors.top: parent.top
          anchors.topMargin: 12
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 4

          RailCell {
            host: win
            icon: "search"
            tip: root.tr("search")
            tipValue: "Super Space"
            onClicked: root.openSearch()
          }
          RailCell {
            host: win
            icon: "inbox"
            tip: root.tr("inbox")
            tipValue: root.tr("inbox.hint")
            onClicked: root.openInbox()
          }
          RailCell {
            host: win
            icon: "agents"
            tip: root.tr("agents")
            panelTarget: true
            onClicked: root.togglePanel("agents")
            Item { id: railAgentsHome; anchors.centerIn: parent }
          }
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 20
            height: 1
            color: root.sg.border
          }
          Column {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 2
            bottomPadding: 6
            spacing: 4
            // Outside the column's own layout: it rides over the cells' places.
            Item {
              width: 32
              height: 0
              z: -1
              FlowPill {
                readonly property int at: win.wsIds.indexOf(win.shownId)
                width: 32
                rowHeight: 32
                active: at !== -1
                targetY: at === -1 ? topY : 4 + at * 36
              }
            }
            Repeater {
              model: win.wsIds
              RailCell {
                id: wsCell
                flow: true
                required property int modelData
                readonly property var ws: {
                  var all = Hyprland.workspaces.values
                  for (var i = 0; i < all.length; i++) if (all[i].id === wsCell.modelData) return all[i]
                  return null
                }
                readonly property int count: ws ? ws.toplevels.values.length : 0
                readonly property bool shown: modelData === win.shownId
                host: win
                armed: shown
                // What is making sound on this workspace, if anything.
                readonly property var playing: root.soundByWorkspace[modelData] || null
                tip: root.wsTitle(modelData)
                tipValue: playing ? (playing.muted ? root.tr("sound.mutedFrom") : root.tr("sound.from")).arg(playing.app)
                  : count === 0 ? root.tr("workspace.empty") : strings.tn("workspace.windows", count).arg(Commons.I18n.formatNumber(count))
                onClicked: win.focusWorkspace(modelData)
                onScrolled: function(delta) { win.scrollWorkspaces(delta) }
                Chip {
                  anchors.centerIn: parent
                  size: 18
                  text: root.wsLabel(wsCell.modelData)
                  kind: wsCell.shown ? "ink" : wsCell.count > 0 ? "solid" : "dashed"
                }
                // Two bars on the chip's corner, ringed in the page colour.
                Rectangle {
                  visible: !!wsCell.playing
                  x: 19
                  y: 19
                  width: 12
                  height: 12
                  radius: 4
                  color: Qt.rgba(root.sg.page.r, root.sg.page.g, root.sg.page.b, 1)
                  Rectangle { x: 3; y: 5; width: 2; height: 5; radius: 1; color: wsCell.playing && wsCell.playing.muted ? root.cFaint : root.cFg }
                  Rectangle { x: 7; y: 2; width: 2; height: 8; radius: 1; color: wsCell.playing && wsCell.playing.muted ? root.cFaint : root.cFg }
                }
              }
            }
          }
        }

        Item { id: railOtherHome; x: root.railWidth / 2; y: parent.height / 2 }

        Column {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 10
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 4

          RailCell {
            host: win
            icon: "wifi"
            lit: false
            opacity: root.networkUp ? 1 : 0.55
            tip: root.tr("wifi")
            tipValue: root.networkText
            panelTarget: true
            onClicked: root.togglePanel("network")
            Item { id: railNetworkHome; anchors.centerIn: parent }
          }
          RailCell {
            host: win
            icon: root.muted ? "mute" : "sound"
            tip: root.tr("sound")
            tipValue: root.soundText
            panelTarget: true
            onClicked: root.togglePanel("audio")
            onScrolled: function(delta) { root.nudgeVolume(delta) }
            Item { id: railAudioHome; anchors.centerIn: parent }
          }
          RailCell {
            host: win
            icon: "bluetooth"
            opacity: root.btAdapter && root.btAdapter.enabled ? 1 : 0.55
            tip: root.tr("bluetooth")
            tipValue: root.bluetoothText
            panelTarget: true
            onClicked: root.togglePanel("bluetooth")
            Item { id: railBluetoothHome; anchors.centerIn: parent }
          }
          RailCell {
            id: railBattery
            host: win
            icon: "battery"
            tip: root.tr("battery")
            tipValue: root.charging && root.batteryPresent ? root.tr("battery.charging").arg(root.batteryText) : root.batteryText
            panelTarget: true
            onClicked: root.togglePanel("power")
            Item { id: railPowerHome; anchors.centerIn: parent }
          }
          RailCell {
            host: win
            height: 42
            tip: root.dateText
            onClicked: root.expand(win.screenName, false)
            Column {
              anchors.horizontalCenter: parent.horizontalCenter
              y: 10
              Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.timeText
                elide: Text.ElideNone
                font.pixelSize: 12
                font.weight: Font.DemiBold
                height: 15
                verticalAlignment: Text.AlignVCenter
              }
              Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.ampmText
                elide: Text.ElideNone
                color: root.cDim
                font.pixelSize: 10
                height: 13
                verticalAlignment: Text.AlignVCenter
              }
            }
          }
          RailCell {
            host: win
            icon: "sidebar"
            tip: root.tr("pin")
            onClicked: root.setPinned(true)
          }
        }
      }

      // ---- the sidebar ----
      Loader {
        id: side
        active: win.wide || win.t > 0
        // Pinned it sits on the page with the design's own padding; floating
        // it sits inside the card.
        readonly property real pad: root.cardInset + 9
        x: root.pinned ? 12 : pad - (1 - win.cardT) * 8
        y: root.pinned ? 12 : pad
        width: root.pinned ? root.wideWidth - 22 : root.wideWidth - 18
        height: parent.height - (root.pinned ? 22 : pad * 2)
        // Dimmed while a resize drag is far enough left to fold it away.
        opacity: win.t * (root.resizeFold ? 0.4 : 1)
        enabled: win.wide
        sourceComponent: sideComponent
      }

      // ---- the resize handle: the sidebar's right edge, while it is out ----
      MouseArea {
        id: grip
        // The edge as a width: the floating card starts cardInset in.
        readonly property real edgeInset: root.pinned ? 0 : root.cardInset
        // Where the pointer was on the handle when it went down, and whether
        // it has moved since (a double-click's presses must not resize).
        property real grabOffset: 0
        property real pressX: 0
        property bool moved: false
        function sceneX(mouse) { return mapToItem(surface, mouse.x, 0).x }
        visible: win.wide
        x: win.sidebarEdge - 4
        width: 8
        height: parent.height
        hoverEnabled: true
        preventStealing: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.SizeHorCursor
        onPressed: function(mouse) {
          pressX = sceneX(mouse)
          grabOffset = pressX - win.sidebarEdge
          moved = false
          root.beginResize()
        }
        onPositionChanged: function(mouse) {
          if (!pressed) return
          var px = sceneX(mouse)
          if (!moved && Math.abs(px - pressX) < 3) return
          moved = true
          root.resizeTo(px - grabOffset - edgeInset)
        }
        onReleased: root.endResize(true)
        onCanceled: root.endResize(false)
        onDoubleClicked: { root.endResize(false); root.applyWidth(root.defaultWidth) }
        // The ink line on the edge; pinned, it is the guide for where the
        // edge will be on release (the rail, when letting go would fold it).
        Rectangle {
          readonly property real target: !root.resizing || root.dragWidth <= 0 ? win.sidebarEdge
            : root.resizeFold && root.pinned ? root.railWidth
            : root.dragWidth + grip.edgeInset
          visible: grip.containsMouse || grip.pressed
          x: target - grip.x - 1
          // Floating, it keeps to the card's straight side.
          y: root.pinned ? 0 : root.cardInset + 20
          width: 2
          height: parent.height - y * 2
          color: Qt.rgba(root.sg.primary.r, root.sg.primary.g, root.sg.primary.b, grip.pressed ? 0.6 : 0.35)
        }
      }

      // ---- the rail's tooltip ----
      Item {
        id: tipBox
        // Out, only the rows that ask for it (wideTip) are explained: it
        // stands off the sidebar's edge, or above the row when the sidebar is
        // too wide to leave it room.
        readonly property bool shown: !!win.tipCell && win.tipCell.tip !== "" && (!win.wide || win.tipCell.wideTip === true)
        readonly property bool lifted: win.wide && x < win.sidebarEdge
        visible: opacity > 0
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Style.duration(tipBox.shown ? 120 : 80); easing.type: Easing.OutCubic } }
        x: win.wide ? Math.round(Math.min(win.sidebarEdge + 6, win.width - width - 6)) : root.railWidth - 4
        y: Math.round(Math.max(6, Math.min(win.height - 34, win.tipY - 14 - (lifted ? 30 : 0))))
        width: tipRow.implicitWidth + 20
        height: 28
        RectangularShadow {
          anchors.fill: tipFace
          anchors.topMargin: 6
          radius: tipFace.radius
          blur: 16
          spread: -4
          color: Qt.rgba(root.sg.shade.r, root.sg.shade.g, root.sg.shade.b, Math.min(0.4, root.sg.shade.a))
        }
        Rectangle {
          id: tipFace
          anchors.fill: parent
          radius: 9
          color: root.sg.popover
          SolidEdge { edgeColor: root.sg.popoverEdge }
        }
        Row {
          id: tipRow
          anchors.centerIn: parent
          spacing: 6
          Label {
            text: win.tipCell ? win.tipCell.tip : ""
            elide: Text.ElideNone
            font.pixelSize: 12
            font.weight: Font.Medium
          }
          Label {
            visible: text !== ""
            text: win.tipCell && win.tipCell.tipValue ? "·" : ""
            elide: Text.ElideNone
            color: root.cFaint
            font.pixelSize: 12
          }
          Label {
            visible: text !== ""
            text: win.tipCell ? win.tipCell.tipValue : ""
            width: Math.min(implicitWidth, 190)
            color: root.cDim
            font.pixelSize: 12
          }
        }
      }

      // Not a Repeater: each slot goes to live in its own cell or row.
      Instantiator {
        model: root.hostedEntries
        delegate: HostedSlot { host: win }
      }
    }

    Component {
      id: sideComponent

      Item {
        id: sc
        property alias agentsHome: agentsHomeItem
        property alias networkHome: networkHomeItem
        property alias audioHome: audioHomeItem
        property alias bluetoothHome: bluetoothHomeItem
        property alias powerHome: powerHomeItem
        property alias otherHome: otherHomeItem
        property bool workspacesOpen: true
        property bool pinnedOpen: true
        // The workspace or page block now shown; the pill sits on its row.
        property Item armedBlock: null

        // Header: the machine, search, and the launcher.
        Item {
          id: header
          width: parent.width
          height: 32
          MouseArea {
            x: 0
            width: hostLabel.x + hostLabel.width + 24
            height: parent.height
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openMenu("root")
          }
          Label {
            id: hostLabel
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - 6 - 20 - 8 - 28 - 8 - 28 - 4)
            text: root.hostName
            font.pixelSize: 14
            font.weight: Font.DemiBold
            font.letterSpacing: -0.14
          }
          Glyph {
            x: hostLabel.x + hostLabel.width + 8
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron"
            size: 12
            stroke: 2.2
          }
          SideButton {
            anchors.right: plusButton.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            icon: "search"
            onClicked: root.openSearch()
          }
          SideButton {
            id: plusButton
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            icon: "plus"
            raised: true
            onClicked: root.openApps()
          }
        }

        Column {
          id: nav
          y: header.height + 18
          width: parent.width
          spacing: 1
          SideRow {
            icon: "search"
            label: root.tr("search")
            onClicked: root.openSearch()
            Label {
              anchors.verticalCenter: parent.verticalCenter
              text: "Super Space"
              color: root.cDim
              font.family: root.mono
              font.pixelSize: 11
            }
          }
          SideRow {
            icon: "inbox"
            label: root.tr("inbox")
            host: win
            tip: root.tr("inbox.hint")
            onClicked: root.openInbox()
          }
          SideRow {
            icon: "agents"
            label: root.tr("agents")
            panelTarget: true
            onClicked: root.togglePanel("agents")
            Item { id: agentsHomeItem; width: 0; height: 1; anchors.verticalCenter: parent.verticalCenter }
          }
        }

        // Workspaces and launchers scroll if a workspace holds many windows.
        Flickable {
          id: middle
          anchors.top: nav.bottom
          anchors.topMargin: 18
          anchors.bottom: system.top
          anchors.bottomMargin: 18
          width: parent.width
          clip: true
          contentHeight: middleColumn.height
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          FlowPill {
            width: middleColumn.width
            active: !!sc.armedBlock && sc.armedBlock.shown === true
            targetY: sc.armedBlock && sc.armedBlock.parent ? sc.armedBlock.y + sc.armedBlock.parent.y : topY
          }
          Column {
            id: middleColumn
            width: parent.width
            spacing: 18

            Column {
              width: parent.width
              spacing: 1
              Item {
                width: parent.width
                height: 26
                Row {
                  x: 8
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 4
                  Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.tr("workspaces")
                    elide: Text.ElideNone
                    color: root.cDim
                    font.pixelSize: 12
                    font.weight: Font.Medium
                  }
                  Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "caret"
                    size: 10
                    filled: true
                    color: root.cDim
                    rotation: sc.workspacesOpen ? 0 : -90
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  anchors.rightMargin: 28
                  cursorShape: Qt.PointingHandCursor
                  onClicked: sc.workspacesOpen = !sc.workspacesOpen
                }
                Glyph {
                  id: addWorkspace
                  anchors.right: parent.right
                  anchors.rightMargin: 6
                  anchors.verticalCenter: parent.verticalCenter
                  name: "plus"
                  size: 14
                  stroke: 2
                  color: addMouse.containsMouse ? root.cFg : root.cDim
                  MouseArea {
                    id: addMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.focusEmptyWorkspace()
                  }
                }
              }
              Repeater {
                model: sc.workspacesOpen ? win.wsIds : []
                Column {
                  id: wsBlock
                  required property int modelData
                  readonly property var ws: {
                    var all = Hyprland.workspaces.values
                    for (var i = 0; i < all.length; i++) if (all[i].id === wsBlock.modelData) return all[i]
                    return null
                  }
                  readonly property var windows: ws ? ws.toplevels.values : []
                  readonly property bool shown: modelData === win.shownId
                  readonly property var playing: root.soundByWorkspace[modelData] || null
                  readonly property string wsName: root.wsName(modelData)
                  onShownChanged: if (shown) sc.armedBlock = wsBlock
                  Component.onCompleted: if (shown) sc.armedBlock = wsBlock
                  width: parent.width
                  spacing: 1
                  SideRow {
                    flow: true
                    armed: wsBlock.shown
                    chipText: root.wsLabel(wsBlock.modelData)
                    chipKind: wsBlock.shown ? "ink" : wsBlock.windows.length > 0 ? "solid" : "dashed"
                    label: wsBlock.wsName !== "" ? wsBlock.wsName
                      : wsBlock.windows.length === 0 && !wsBlock.shown ? root.tr("workspace.empty") : root.tr("workspace.numbered").arg(root.wsLabel(wsBlock.modelData))
                    labelColor: wsBlock.shown ? root.cFg : wsBlock.windows.length === 0 ? root.cFaint : root.cLabel
                    wheelEnabled: !middle.interactive
                    onClicked: { if (root.renamingWs > 0) root.endRename(); win.focusWorkspace(wsBlock.modelData) }
                    onScrolled: function(delta) { win.scrollWorkspaces(delta) }
                    editable: true
                    editing: root.renamingWs === wsBlock.modelData && root.renamingScreen === win.screenName
                    editText: wsBlock.wsName
                    editHint: root.tr("workspace.numbered").arg(root.wsLabel(wsBlock.modelData))
                    onEditRequested: root.beginRename(wsBlock.modelData, win.screenName)
                    onEdited: function(text) { root.setWsName(wsBlock.modelData, text); root.endRename() }
                    onEditCancelled: root.endRename()
                    // Sound is coming from a window on this workspace.
                    Glyph {
                      visible: !!wsBlock.playing
                      anchors.verticalCenter: parent.verticalCenter
                      name: wsBlock.playing && wsBlock.playing.muted ? "mute" : "sound"
                      size: 14
                      color: wsBlock.playing && wsBlock.playing.muted ? root.sg.mutedFg : root.sg.foreground
                    }
                    Glyph {
                      visible: wsBlock.shown
                      anchors.verticalCenter: parent.verticalCenter
                      name: "caret"
                      size: 10
                      filled: true
                    }
                    Label {
                      visible: !wsBlock.shown && wsBlock.windows.length > 0
                      anchors.verticalCenter: parent.verticalCenter
                      text: String(wsBlock.windows.length)
                      elide: Text.ElideNone
                      color: root.cDim
                      font.family: root.mono
                      font.pixelSize: 11
                    }
                  }
                  // The shown workspace lists its windows.
                  WindowList { windows: wsBlock.shown ? wsBlock.windows : []; host: win }
                }
              }
            }

            Column {
              width: parent.width
              spacing: 1
              Item {
                width: parent.width
                height: 26
                Row {
                  x: 8
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 4
                  Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.tr("pages")
                    elide: Text.ElideNone
                    color: root.cDim
                    font.pixelSize: 12
                    font.weight: Font.Medium
                  }
                  Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "caret"
                    size: 10
                    filled: true
                    color: root.cDim
                    rotation: sc.pinnedOpen ? 0 : -90
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: sc.pinnedOpen = !sc.pinnedOpen
                }
              }
              Repeater {
                model: sc.pinnedOpen ? root.pages : []
                Column {
                  id: pageBlock
                  required property var modelData
                  readonly property var ws: root.pageWs(modelData.name)
                  readonly property var windows: ws ? ws.toplevels.values : []
                  readonly property bool shown: !!ws && win.shownId === ws.id
                  onShownChanged: if (shown) sc.armedBlock = pageBlock
                  Component.onCompleted: if (shown) sc.armedBlock = pageBlock
                  width: parent.width
                  spacing: 1
                  SideRow {
                    id: pageRow
                    flow: true
                    armed: pageBlock.shown
                    icon: pageBlock.modelData.icon
                    label: root.tr("page." + pageBlock.modelData.key)
                    labelColor: pageBlock.shown ? root.cFg : root.cLabel
                    onClicked: root.openPage(pageBlock.modelData.key, false)
                    Label {
                      visible: !pageBlock.shown && pageBlock.windows.length > 0
                      anchors.verticalCenter: parent.verticalCenter
                      text: String(pageBlock.windows.length)
                      elide: Text.ElideNone
                      color: root.cDim
                      font.family: root.mono
                      font.pixelSize: 11
                    }
                    // One more window on this page.
                    Item {
                      visible: pageBlock.modelData.many && pageBlock.windows.length > 0 && (pageBlock.shown || pageRow.hovered || anotherMouse.containsMouse)
                      anchors.verticalCenter: parent.verticalCenter
                      width: 22
                      height: 22
                      Rectangle {
                        anchors.fill: parent
                        radius: 7
                        visible: anotherMouse.containsMouse
                        color: anotherMouse.pressed ? root.sg.hover : root.sg.hoverFaint
                      }
                      Glyph { anchors.centerIn: parent; name: "plus"; size: 14; color: anotherMouse.containsMouse ? root.cFg : root.cMuted }
                      MouseArea {
                        id: anotherMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openPage(pageBlock.modelData.key, true)
                      }
                    }
                  }
                  WindowList { windows: pageBlock.shown ? pageBlock.windows : []; host: win }
                }
              }
            }
          }
        }
        // Any other hosted widget's card stands off the middle of the sidebar.
        Item { id: otherHomeItem; x: parent.width; y: Math.round(parent.height * 0.45) }

        Column {
          id: system
          anchors.bottom: footer.top
          anchors.bottomMargin: 18
          width: parent.width
          spacing: 1
          SideRow {
            icon: "wifi"
            label: root.tr("wifi")
            panelTarget: true
            onClicked: root.togglePanel("network")
            Label {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, 130)
              text: root.networkText
              color: root.cDim
              font.pixelSize: 12
            }
            Item { id: networkHomeItem; width: 0; height: 1; anchors.verticalCenter: parent.verticalCenter }
          }
          SideRow {
            icon: root.muted ? "mute" : "sound"
            label: root.tr("sound")
            panelTarget: true
            wheelEnabled: true
            // While something plays the row names the app, and its tip the
            // workspace too.
            host: win
            tip: root.soundSourceText !== "" ? root.tr("sound.playing") : ""
            tipValue: root.soundSourceText
            onClicked: root.togglePanel("audio")
            onScrolled: function(delta) { root.nudgeVolume(delta) }
            Label {
              readonly property real room: sc.width - 176
              visible: text !== "" && room >= 30
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, Math.max(0, room))
              text: root.soundLead ? root.soundLead.app : ""
              color: root.cDim
              font.pixelSize: 12
            }
            Track { anchors.verticalCenter: parent.verticalCenter; value: root.volume; quiet: root.muted }
            Item { id: audioHomeItem; width: 0; height: 1; anchors.verticalCenter: parent.verticalCenter }
          }
          SideRow {
            icon: "bluetooth"
            label: root.tr("bluetooth")
            panelTarget: true
            onClicked: root.togglePanel("bluetooth")
            Label {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, 130)
              text: root.bluetoothText
              color: root.cDim
              font.pixelSize: 12
            }
            Item { id: bluetoothHomeItem; width: 0; height: 1; anchors.verticalCenter: parent.verticalCenter }
          }
          SideRow {
            icon: "battery"
            label: root.tr("battery")
            panelTarget: true
            onClicked: root.togglePanel("power")
            Label {
              anchors.verticalCenter: parent.verticalCenter
              text: root.batteryText + (root.charging && root.batteryPresent ? " +" : "")
              elide: Text.ElideNone
              color: root.cDim
              font.family: root.mono
              font.pixelSize: 11
            }
            Item { id: powerHomeItem; width: 0; height: 1; anchors.verticalCenter: parent.verticalCenter }
          }
        }

        Item {
          id: footer
          anchors.bottom: parent.bottom
          width: parent.width
          height: 36
          Column {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 6 - 4 - 28 - 8 - 28 - 8
            Label {
              width: parent.width
              height: 17
              verticalAlignment: Text.AlignVCenter
              text: root.timeText + " " + root.ampmText
              font.weight: Font.DemiBold
              font.letterSpacing: -0.13
            }
            Label {
              width: parent.width
              height: 14
              verticalAlignment: Text.AlignVCenter
              text: root.dateText
              color: root.cDim
              font.pixelSize: 11
            }
          }
          SideButton {
            anchors.right: powerButton.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            // Floating: pin it to the page. Pinned: fold it back to the rail.
            icon: root.pinned ? "sidebar" : "pin"
            onClicked: root.setPinned(!root.pinned)
          }
          SideButton {
            id: powerButton
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            icon: "power"
            onClicked: root.openMenu("system")
          }
        }
      }
    }
  }
}
