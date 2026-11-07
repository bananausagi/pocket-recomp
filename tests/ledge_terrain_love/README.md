# Original block road ledges QA (jp.16)

Road-hop tiles again use their original authored six-unit block profile. The mesher emits the existing top and side geometry; actor and battle floor queries use the same height. Surrounding roads remain flat. The rejected jp.12/jp.13 inferred heightfield, slopes, lifted buildings and foliage are not restored. Collision, event and jump rules are not changed by this rendering restoration.

Run from the source directory, with local LuaJIT/LÖVE paths:

```sh
TERRAIN_QA_OUT=/absolute/output luajit tests/japanese_ledge_terrain_test.lua
JP_QA_ROOT=/absolute/source TERRAIN_QA_OUT=/absolute/output love tests/ledge_terrain_love
```

Results: 30 focused checks and 12 real LÖVE checks pass. Tests cover six-unit block tops and exposed sides, level surrounding roads, left/right-facing ledges, matching actor/battle floor, the original Player jump arc, unchanged collision cells, no global terrain solving, ordinary wall height and water depth. Production profile/Structures classification and cache reuse are covered.

The mesh-cache revision is 5, so an obsolete flat mesh has a different fingerprint. The shipped disk provider remains disabled; in-memory meshes and classifications are rebuilt when the application starts. No user save or setting is reset.

`straight-after.png`, `two-rows-blocks.png` and `normal-objects.png` use an original synthetic map and atlas with the production terrain mesher. No ROM, extracted images or map dumps are present. Actual user-ROM and Android device behaviour have not been tested here.
