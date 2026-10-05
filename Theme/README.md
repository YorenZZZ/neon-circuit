# Theme artwork

`svg/` contains 56 editable design states. `registry-svg/` contains the 12
installation variants shared by the window resize cursor IDs. The variants
omit contextual grey edge guides because several AppKit configurations share
one system cursor registration. `registry-mapping.json` records the 50 keys
actually replaced and the two preserved native keys.

The compiled theme is `../Resources/NEON-CIRCUIT.cape`, a binary property list
with embedded original PNG strips at 1× and 2× resolution, logical sizes,
hotspots, and frame timings. It contains no captured Apple cursor images.
Its logical canvas is 32×32 points. Animated B11 has 24 vertically stacked
frames. Native Wait and Empty are deliberately absent.

SVG edits do not automatically rebuild the compiled cape. Theme maintainers
must render updated artwork at the declared scales, retain hotspot semantics,
and validate the resulting cape with `neon-cursorctl validate` before use.
Application builds consume the checked-in cape and require no artwork tools.

Palette: cyan `#35e7f3`, magenta `#f02bbe`, graphite `#152332`, white `#edfaff`.
Theme artwork is covered by the project's MIT license.
