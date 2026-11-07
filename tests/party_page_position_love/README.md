# Japanese Pokémon page position

This ROM-free fixture uses the actual Game.draw, Renderer, StateStack, touch controls, PartyMenu, PokedexMenu, DexEntryMenu, SummaryMenu and BattleState/BagMenu. Only Pokémon records/art, sound and generated font pages are synthetic. Kana use the bundled licensed Misaki font. No save or user ROM is read.

The production change sets the existing `centerInPlayfield` attribute on those four Pokémon pages. The Japanese layout gate centers the full native page in the usable region above the touch controls. Six party slots, the bottom prompt, the first-row voicing inset, integer scaling, common saved scale, callbacks and overseas layouts are retained. A one-member party still reserves the original six-member native page; this change does not compact it.

Stage `main.lua` and `conf.lua` outside the source tree, together with `assets/fonts`, `assets/touch`, `tests/fixture_data/assets` and `tools/rom_manifest_red_jp.json`. Run real LÖVE with `JP_QA_ROOT` pointing at this source tree and `JP_QA_OUT` at an existing output folder. Use an isolated LÖVE save directory. On the Linux software renderer, set `SDL_VIDEODRIVER=offscreen`, `LIBGL_ALWAYS_SOFTWARE=1`, `ALSOFT_DRIVERS=null` and the toolchain's `LD_LIBRARY_PATH` as needed.

`JP_QA_BEFORE=1` temporarily clears only the four class attributes in the fixture process to reproduce the prior top alignment on the same code. Neither source nor shared geometry is rewritten. Before/after `results.json` contains physical placement, usable bounds, scale and native canvas SHA256, so unchanged native content can be checked independently of the new position.

Evidence covers 972×1536 portrait, 1536×1160 fold and 1536×864 landscape: one/six members, Pokédex list/entry, status, battle-opened party/bag, first-row voiced kana, native selection and cancellation, story completion callback, save object identity and non-Japanese gating. These are synthetic desktop LÖVE checks, not real-ROM or Android-device testing.
