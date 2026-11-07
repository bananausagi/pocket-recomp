# JP screen-position regression

This ROM-free fixture uses the bundled Dramaless `Voxel3D.viewProjection`
and the real LÖVE `Renderer:endFrame` compositor. It draws synthetic ground
lines and a camera-facing 16 × 16 marker, using no cartridge data or artwork.

Run `tests/engine/japanese_world_position.lua` with LuaJIT from the repository
root for the headless geometry/DPI/effect-scale checks.

For GPU checks, stage this directory's `main.lua` and `conf.lua` as a LÖVE
application and link the repository's `src`, `assets`, `data`, `tools`,
`tests` and `vendor` directories beside them. Set `JP_QA_ROOT` to the absolute
repository root and `JP_QA_OUT` to an existing output directory, then run
LÖVE 11.5 against that application. Use an isolated `XDG_DATA_HOME`.

The fixture covers CENTER, UPPER and TOP at 480 × 800, 800 × 480 and
972 × 1536, with 0° and 45° camera pitch. Image pixels are inspected to
verify the marker remains square at the same zoom, moves to the selected
position, and leaves no uncovered screen corners. Output includes 18
PNG files, `summary.json`, and console results (144 checks).

This verifies rendering geometry and composition, not Android device
behavior or a complete playthrough with a Japanese ROM.
