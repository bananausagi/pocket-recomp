# jp.22 color profile checks

`tests/jp22_colors_test.lua` checks all Gen 1 color choices on Japanese Red,
Red, Blue and Yellow, including picker open/cancel, custom ramps, option
serialization and the launcher route. Opening the picker must never change
the selected color mode. A custom ramp suppresses incompatible baked-color
routes until cleared; the underlying saved color choice remains intact.

The Love fixture generates its own four-shade atlas and actor/monster shapes,
then exercises production `TileRenderer`, Dramaless `TerrainAtlas`,
`SpriteRenderer`, `BattleState.makeBattler`, `PaletteFX` and `ClassicPalette`.
GPU readback checks all 1,024 terrain shade samples per mode, actor alpha,
battle colors, shader paper/ink, session window paper and vivid → soft → vivid
cache restoration. `comparison.png` is synthetic verification artwork.

Run from the source root:

```sh
luajit tests/jp22_colors_test.lua
JP_QA_ROOT="$PWD" JP_QA_OUT=/absolute/evidence/directory love tests/jp22_colors_love
```

The new stored mode is `redpp_soft`; the original `redpp` remains unchanged.
Soft color reduces chromatic spread by 35%, then applies up to 6% brightness
reduction in proportion to chroma. Exact neutral grays, white and black remain
unchanged, preserving readable menus and text. This is a selectable appearance
profile, not device-specific OLED calibration. Authored true-color mod assets
retain their explicit colors.

Reference execution: Love 11.5 / Mesa llvmpipe, 3,092 GL checks; 330 focused
logic checks; 112 existing palette checks; 16 existing Yellow title checks.
The generated terrain's mean RGB channel spread changed from 0.09237 to
0.05827 (36.9% lower), returning exactly to 0.09237 when switching back.
Android/OLED hardware appearance has not been measured.

Unrelated existing fixtures were not counted: the Gen 2 picker test has a
legacy fake stack without `top()`, and `parity_hpcolor_og_palette.lua` requires
generated ROM data that is deliberately absent from this source package.
