// Solid Glass tokens for the sidebar, after DeepLethe's Solid Glass
// (https://github.com/deeplethe/solid-glass, MIT): neutral grey panes whose
// finish is at the edge, one clear state for hovered and chosen, and one solid
// ink for what asks to be pressed. Colour is kept for what it means.
//
// Colours are #AARRGGBB, as QML reads them.

var dark = {
  page: "#ff0d0d0d",
  foreground: "#fffafafa",
  mutedFg: "#ffa4a4a4",
  popover: "#f51b1b1b",
  window: "#ff1d1d1d",
  card: "#ff242424",
  // The finish.
  rim: "#29ffffff",
  edge: "#0fffffff",
  popoverEdge: "#0fffffff",
  shade: "#99000000",
  // Clear glass, and the one state.
  control: "#12ffffff",
  controlRim: "#1cffffff",
  state: "#12ffffff",
  stateRim: "#1cffffff",
  stateEdge: "#0fffffff",
  stateArmed: "#1cffffff",
  hover: "#14ffffff",
  hoverFaint: "#0affffff",
  // Grooves.
  well: "#38000000",
  wellShade: "#61000000",
  wellRim: "#17ffffff",
  border: "#1cffffff",
  // The ink.
  primary: "#ffebebeb",
  primaryFg: "#ff121212",
  primaryRim: "#ffffffff",
  primaryUnder: "#38000000"
}

var light = {
  page: "#ffe4e6eb",
  foreground: "#ff0d0d0d",
  mutedFg: "#ff5b5b5b",
  popover: "#f5f9fafc",
  window: "#ffeff1f5",
  card: "#ffeff1f5",
  rim: "#e6ffffff",
  edge: "#1a3b4253",
  popoverEdge: "#383b4253",
  shade: "#471f2d4c",
  control: "#8cffffff",
  controlRim: "#ccffffff",
  state: "#17292e38",
  stateRim: "#d9ffffff",
  stateEdge: "#21292e38",
  stateArmed: "#42292e38",
  hover: "#1a292e38",
  hoverFaint: "#0e292e38",
  well: "#121f2d4c",
  wellShade: "#241f2d4c",
  wellRim: "#d9ffffff",
  border: "#21292e38",
  primary: "#ff161616",
  primaryFg: "#fffafafa",
  primaryRim: "#4cffffff",
  primaryUnder: "#73000000"
}

// ---- following the theme's tone --------------------------------------------------
// The panes stay grey, but lean toward the theme's hue (chroma capped, so a
// loud theme never colours them). A dark theme whose page is lifted above the
// usual near-black lifts the sidebar's page with it.
function srgbToLinear(x) { return x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4) }
function linearToSrgb(x) { x = Math.max(0, Math.min(1, x)); return x <= 0.0031308 ? 12.92 * x : 1.055 * Math.pow(x, 1 / 2.4) - 0.055 }
function hexToRgb(hex) {
  var m = /^#?([0-9a-fA-F]{6})$/.exec(String(hex || "").trim())
  if (!m) return null
  var n = parseInt(m[1], 16)
  return [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255]
}
function toOklch(rgb) {
  var r = srgbToLinear(rgb[0]), g = srgbToLinear(rgb[1]), b = srgbToLinear(rgb[2])
  var l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  var m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  var s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
  var L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
  var A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
  var B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
  return [L, Math.sqrt(A * A + B * B), (Math.atan2(B, A) * 180 / Math.PI + 360) % 360]
}
function oklchHex(L, C, H, alpha) {
  var a = C * Math.cos(H * Math.PI / 180), b = C * Math.sin(H * Math.PI / 180)
  var l = Math.pow(L + 0.3963377774 * a + 0.2158037573 * b, 3)
  var m = Math.pow(L - 0.1055613458 * a - 0.0638541728 * b, 3)
  var s = Math.pow(L - 0.0894841775 * a - 1.2914855480 * b, 3)
  var rgb = [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
             -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
             -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s]
  function h2(x) { var v = Math.round(x * 255).toString(16); return v.length < 2 ? "0" + v : v }
  return "#" + h2(alpha === undefined ? 1 : alpha) + rgb.map(function(c) { return h2(linearToSrgb(c)) }).join("")
}
// A theme's colors.toml value, e.g. tomlColor(text, "background").
function tomlColor(toml, key) {
  var m = new RegExp("^\\s*" + key + "\\s*=\\s*[\"']?(#?[0-9a-fA-F]{6})[\"']?", "m").exec(String(toml || ""))
  return m ? (m[1][0] === "#" ? m[1] : "#" + m[1]) : ""
}
// The base tokens, leaning toward the theme. background: the theme's window
// colour; page: its dark_background. Either may be empty.
function tinted(base, isLight, background, page) {
  var bg = hexToRgb(background)
  if (!bg) return base
  var t = toOklch(bg)
  var chroma = t[1] < 0.004 ? 0 : Math.min(t[1], 0.022), hue = t[2]
  var lift = 0
  var pg = hexToRgb(page)
  if (!isLight && pg) lift = Math.max(0, Math.min(0.08, toOklch(pg)[0] - 0.16))
  if (chroma === 0 && lift === 0) return base
  var out = {}
  for (var k in base) out[k] = base[k]
  function surface(key, k2) {
    var rgb = hexToRgb("#" + String(base[key]).slice(3))
    if (!rgb) return
    var alpha = parseInt(String(base[key]).slice(1, 3), 16) / 255
    var L = toOklch(rgb)[0] + (isLight ? 0 : lift)
    out[key] = oklchHex(L, chroma * k2, hue, alpha)
  }
  surface("page", 1.6); surface("window", 1); surface("card", 1); surface("popover", 1)
  return out
}

if (typeof module !== "undefined") module.exports = { dark: dark, light: light, tinted: tinted, tomlColor: tomlColor, toOklch: toOklch, oklchHex: oklchHex }
