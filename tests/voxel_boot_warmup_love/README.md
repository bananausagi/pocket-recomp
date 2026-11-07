# ROM-free startup preparation check

This fixture loads the actual Dramaless MOD and registered render pipeline in
LÖVE. It uses `tests/fixture_data` plus an independently generated grayscale
atlas. No game ROM, extracted game picture, or user save is required.

It checks cold Intro preparation, the title's existing decoded-save hint,
identical map/mesh cache reuse on world entry, zero repeated atlas/shader uploads,
one animation image upload per update, skip without synchronous flushing,
MOD OFF, asset reload, cancellation, and unchanged save/options/world state.
The auxiliary-mesh comparison checks XYZ/UV/shade and triangle order across part
boundaries and byte-identical rendered pixels for 8,192 quads. The larger fixture
has 161,280 grass quads, divided into 40 parts of at most 4,096 quads.

Run from the source root with LÖVE and LuaJIT on PATH. Keep the runner and its
output outside the source tree. These commands use a dedicated test identity;
do not substitute a normal game's save identity.

```sh
export JP_QA_ROOT="$PWD"
export JP_QA_STAGE="$(mktemp -d)"
export JP_QA_OUT="$(mktemp -d)"
mkdir -p "$JP_QA_STAGE/mods" "$JP_QA_STAGE/tests"
cp tests/voxel_boot_warmup_love/main.lua tests/voxel_boot_warmup_love/conf.lua "$JP_QA_STAGE/"
cp -R vendor/jp-mods/DRAMALESS_SHAPE "$JP_QA_STAGE/mods/"
cp -R tests/fixture_data "$JP_QA_STAGE/tests/"
cp -R assets "$JP_QA_STAGE/"
SDL_VIDEODRIVER=offscreen LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null love "$JP_QA_STAGE"
luajit tests/voxel_aux_cleanup_test.lua
```

The cleanup fixture injects upload failure, a nil upload, cancellation after an
uploaded part, and failure in a later figure after an earlier figure succeeded.
It verifies that no incomplete collection is published and all unpublished GPU
objects are released. It does not need an actual graphics context.

Release evidence is `verification/jp17/startup/results.json`, `summary.json`,
`run.log`, `cleanup.log`, and `aux-before.png` / `aux-after.png` in the external
verification directory. The final functional run passed 76 checks; the focused
cleanup run passed 8 checks. Timing-only runs can set `JP_QA_MEASURE_ONLY=1`;
they write `measurement-results.json` without the remaining functional checks.

The 2 ms mesh argument is a cooperative target, not a maximum frame duration.
Shader compilation, map loading, one static atlas bake, individual GPU uploads,
and garbage collection can exceed it. Atlas animation uploads are split across
updates; an incomplete animation uses the already prepared static atlas on
skip. Preparation initially uses the current boot map and only refines the
saved-map hint after the title's existing save read; it performs no extra save
read or world update. Initial engine boot before Intro is not made asynchronous.
Measurements use Linux software GL and synthetic geometry, not Android hardware
or a real ROM; they must not be converted into an Android FPS claim. Splitting
auxiliary meshes increases draw calls (two rather than one in the 8,192-quad
comparison), while terrain and water meshes retain their existing path.
