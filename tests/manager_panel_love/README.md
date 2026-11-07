# Floating in-game MOD manager (jp.14)

ManagerState now creates a floating, paused instance for Japanese games. Its panel uses shared GameUILayout.panelMetrics/overlay and ClassicUI, keeping the game scene visible outside the white frame. Integer 8px glyphs use dense 12px rows, with extra space for native voiced kana. Short lists produce smaller windows; longer lists scroll with the selected row. Lists, details, options, permissions, errors and apply confirmations share the adapter. Non-Japanese instances keep the original view.

The original dependency/permission/profile/staged-apply callbacks remain byte-identical to jp.13 (18 methods recorded in summary.json). The existing B hierarchy remains: child page to manager list, then native START menu. Closing the manager preserves staged flags. Applying/restarting keeps its confirmation; B cancels it, and the explicit discard action restores boot flags. The permanent MODS/PROFILES/ERRORS tabs are displayed during normal operation and do not indicate a failure.

The real LÖVE fixture passes 256 checks across narrow portrait, landscape and large portrait displays, sparse/long lists, cursor pixels, native kana spacing, game-scene margins, option callbacks, dependency cascade, apply confirmation/cancel/discard and Back. Its font pixels come from the bundled licensed bitmap atlas and an original synthetic cursor, not a ROM. An additional 29 checks in tests/jp14_mod_menu_integration exercise actual Game.draw/Game.update, Renderer, Input and native START routing, including Options root/group images. Launcher separately verifies native overworld START input and restricted-state guards.

Reproduction: stage main.lua/conf.lua from this folder with assets/fonts and tools/rom_manifest_red_jp.json from the project (the manifest has no ROM image). Run LÖVE on that staging directory with JP_QA_ROOT pointing to the project and JP_QA_OUT to an output directory. Source ManagerState is required directly from JP_QA_ROOT.

No Android device was available. Input remains the existing virtual pad/controller A/B/SELECT/START; direct row tap handlers were not added.
