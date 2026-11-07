# ROM-free title verification

Run `tests/player_start_menu_test.lua` from the source root with LuaJIT for
first-opening persistence (including jp8 upgrades and failed writes), later-boot
title defaults, A/START/B navigation, save recovery/failure, new-game protection,
MOD title/splash precedence and independent title scaling.

For real rendering, stage this directory's `main.lua` and `conf.lua` at an
isolated LÖVE app root with `assets/` and `tools/rom_manifest_red_jp.json`
copied from the source tree. Set `TITLE_QA_ROOT`
to the source root and `TITLE_QA_OUT` to an existing output directory. Run with
LÖVE 11.5. The fixture generates geometric title/sprite assets and a genuine
Misaki 8×8 atlas, then exercises the original IntroMovie, first-start option
persistence, production TitleState animation, transition,
command menu and production `Game:draw()` / renderer at 320×480, 480×800,
1080×720 (3:2) and 800×480, with active touch controls and simulated Android
safe-area insets. It checks that the entire start page is centered above the
controls and ordinary game pages keep their previous placement. Screenshots show
synthetic art, not a Pokémon cartridge title. No ROM bytes are required.

The synthetic copyright tiles remain visible in the first opening, disappear
only on the default Japanese title, and remain visible on overseas titles or
an explicitly configured MOD footer. Images are retained in the loader; no
ROM cache, opening state or source attribution is removed.

On the headless Linux toolchain use `SDL_VIDEODRIVER=offscreen`,
`LIBGL_ALWAYS_SOFTWARE=1`, and `ALSOFT_DRIVERS=null`. Add the extracted LÖVE
toolchain's `lib` directory to `LD_LIBRARY_PATH`, then run its `bin/love` with
the staged fixture directory. `TITLE_QA_OUT` receives numeric results and
synthetic screenshots. The jp.11 run passes 216 rendering checks and the
separate boot/input/save test passes 115 checks.

Audio, a full ROM playthrough and physical Android input are outside this fixture.

`python3 tests/android_back_bridge_test.py` compiles and executes the production
GameActivity Back methods with a fake Android dispatcher and SDL event sink.
It covers legacy/physical Back, API33+ gesture callbacks, cancelled keys, native
startup failure and registration lifetime. A JDK compiler module accessible as
`java com.sun.tools.javac.Main` is required. `tests/session_menu_test.lua` checks
the actual main.lua event boundary, including Android's escape/acback pair.
These Java boundary checks do not substitute for a device gesture test.
