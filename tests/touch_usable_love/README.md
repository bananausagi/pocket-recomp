# Touch-free common UI placement

Run with an isolated LÖVE runner containing `main.lua`, `conf.lua`, the source
`assets/` directory, `tests/fixture_data/`, and `tools/rom_manifest_red_jp.json`.
The source tree and output directory are selected separately:

```sh
JP_QA_ROOT=/absolute/source JP_QA_OUT=/absolute/existing/evidence love /absolute/runner
luajit tests/jp_responsive_layout_test.lua
```

The actual Game renderer draws PartyMenu and OptionsMenu, then the current
TouchControls draws its buttons. Independently authored fixture sprites and the
bundled licensed bitmap font replace all ROM assets. The focused run passes
175 checks across portrait, fold-sized portrait and landscape windows, larger
buttons, manual placement, rotation, a custom game viewport, expanded hotbar,
controller hiding, and disabled touch controls. Battle's shared body and panel
bounds are checked here; its actual scene projection is covered by the separate
battle GL fixture. The existing responsive suite passes 361 checks including
anisotropic DPI and integer glyph sizes.

`GameUILayout.touchBounds()` reads window-space visible artwork bounds.
`GameUILayout.usable(localSpace, bounds)` excludes those rectangles with a small
2–6 unit gap and returns a continuous free rectangle. Selection favours readable
native page scale, then area and centring. This usually selects the upper area
in portrait, or a taller central corridor in landscape. Repeated calls cache
only the computation, using all current coordinates as the key; returned values
are copied. No settings are written. Controller/disabled touch leaves the
ordinary safe area unchanged, and battle retains its former full viewport.

The standard START/SELECT bounds are conservatively square (their artwork is
shorter); this does not enlarge the primary A/B/d-pad exclusion. Custom skins
use their declared control geometry. If a user deliberately covers the entire
screen with controls, no empty readable rectangle exists; the fallback keeps a
valid surface rather than a zero-sized canvas. No guarantee is made for that
impossible placement.

Evidence lives outside source at `verification/jp18/touch-layout/`. Screenshots
show positioning with the settings content available during this run; the
settings owner's final grouping/density images are separate. No device timing,
user ROM, or original game artwork is included.

## Faithful mobile UI exception

For the focused follow-up, use `faithful.lua` as the runner's `main.lua` with
an output directory such as `verification/jp18/touch-layout/faithful`. Its 36
checks compare the actual previous overlapping path with the new placement for
PartyMenu and TextBox at 480×800, 1160×1536 and 800×480. The native canvas is
byte-identical; world `r.ox`, `r.oy` and `r.Sp` remain identical. Existing UI
scales 3 and 7 are retained when they fit; the landscape case steps from 3 to 2.
No display option is rewritten. Controller-only placement stays fixed.

Only Japanese native page/world UI with visible touch reservations takes this
exception. Battle's dedicated composition, title and opening remain on their
existing path. The separate 81-check title fixture was rerun afterward to
confirm title/Intro geometry and surround behavior. The world is not shifted or
rescaled along with the windows.
