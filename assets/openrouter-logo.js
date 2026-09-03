// Official OpenRouter glyph (from openrouter.ai brand assets) as a data URI,
// tinted at runtime to the exact theme foreground color — so the bar pill
// renders identically to text widgets like the weather/clock (which paint
// with barForeground). JS resource because QML Image needs a URL, and data
// URIs re-render instantly on theme change.
var PATH = "M303.9475,17.19926c42.79734,0,77.48933,34.69327,77.48933,77.48933s-34.69199,77.48933-77.48933,77.48933l76.86166,76.86244c9.76367,9.76313,2.84903,26.45667-10.95697,26.45667h-220.88335c-71.32686,0-129.14889-57.82202-129.14889-129.14889S77.64197,17.19926,148.96884,17.19926h154.97866ZM148.96884,68.85881c-42.79607,0-77.48933,34.69327-77.48933,77.48933s34.69327,77.48933,77.48933,77.48933,77.48933-34.69327,77.48933-77.48933-34.69327-77.48933-77.48933-77.48933Z"

function uri(color) {
  var svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 401.4 293.7">'
    + '<path fill="' + color + '" d="' + PATH + '"/></svg>'
  return "data:image/svg+xml;utf8," + encodeURIComponent(svg)
}
