# Actual START → MOD manager integration (jp.14)

This narrow fixture uses actual Game.draw/Game.update, Renderer.endFrame, Input source edges, StateStack, Screens, StartMenu, ManagerState and OptionsMenu. Only the world image, native-shaped font, installed MOD records, sound/output persistence boundaries are synthetic. It contains no ROM content.

29 checks pass: native system menu → START → MOD Manager; the retained START parent; post-present floating draw; portrait and landscape scenery margins; game/fixed-step/playtime pause; detail → manager → START Back hierarchy; preservation of a pre-existing staged enable; apply confirmation cancellation; and final B to the same original world state. The same path also renders Options root and its first group. No production source was changed for this verification.

Launcher task separately exercises native Overworld.handleInput START and restricted-state guards in tests/unified_system_menu_test.lua.

To reproduce, stage main.lua/conf.lua from this folder, plus assets/fonts and tools/rom_manifest_red_jp.json from the source tree. Run LÖVE on the staging directory with JP_QA_ROOT pointing to source-jp14 and JP_QA_OUT to an output directory. tests/jp_battle_bitmap_font.lua supplies independently drawn cursor/voicing marks and bundled licensed kana glyphs.

Images: integrated-mods-480x800.png, integrated-mods-800x480.png, integrated-options-800x480.png, integrated-options-group-800x480.png. Default gbc/grayscale menu colors are used; existing custom display palette preferences remain a production feature. No actual Android device was tested.
