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

if (typeof module !== "undefined") module.exports = { dark: dark, light: light }
