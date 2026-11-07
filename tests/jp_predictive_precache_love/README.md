# jp.21 predictive area preparation

## Changes

`VoxelPrecache.lua` now re-ranks actual warp/connection destinations when the
player's target cell changes, retaining at most two predictions. Repeated doors
for a destination use the closest door. `Warp.destination` remains authoritative
(including LAST_MAP and hooks); no movement, warp, collision, or map script is
executed by prediction. Requests use squared world-pixel distance alongside
visible neighbor priorities. They no longer wait for every far neighbor to build.
Runtime MapLoader.load is unchanged and returns the same cached objects.

Destination atlas preparation now uses Scene's exact live palette resolver and
TerrainAtlas.prepare with a 1 ms cooperative target, at most one animation image
upload per update. Changing direction cancels abandoned partial atlases. Crossing
into a partly prepared destination transfers the pending job and retains the
static atlas rather than cancelling it and forcing a synchronous animation build.
Assets reset clears speculative ownership; same-ID replacement map objects and
changed data/lastOutdoor replan predictions.

ChunkMesher retains current + previous distinct live neighborhoods plus the two
predictions. Repeated identical setLive calls do not prematurely discard history.
Prediction changes cancel only jobs still tagged speculative; a live request
promotes a job and removes that tag. Finished full geometry is reused unchanged
when it becomes current, and stale block edits remain drawable during rebuild.
Per-map animated atlases follow the same current/previous/predicted retention.

Ordinary/promotion meshing target changed 5 -> 2 ms; covered/menu target changed
30 -> 4 ms. Truly cold current geometry keeps its existing 12 ms allowance to
avoid deliberately delaying the first visible world. Startup preparation retains
its existing 2 ms allowance. No call synchronously flushes queued meshes.

For the far-render agent's conservative culling, ChunkMesher passes through the
new PackedMesh `ordered` mode for auxiliary quads; grass/flower/figure vertex and
triangle order remain unchanged. Water continues its unpartitioned mode.

## Verification

- `tests/jp_predictive_precache_test.lua`: 15 ROM-free scheduler checks, including
  reversal, at-most-two predictions, at-most-one runtime map load per update,
  duplicate-door distance, LAST_MAP, partial-atlas transfer, restore and reset.
- `tests/jp_predictive_precache_love/`: actual MOD Loader, actual ChunkMesher,
  TerrainAtlas and LÖVE graphics. Synthetic generated grayscale atlas and fixture
  maps only. jp.20 baseline: 5 checks. Final jp.21: 31 checks. Includes identical
  destination Mesh object after seam promotion and zero rebuild jobs; actual
  partial-atlas crossing yields zero synchronous uploads from the first live
  atlas request, one upload per subsequent update, and no upload after completion.
  Previous-neighborhood retention, bounded eviction, visible stale geometry,
  refresh/requeue and global cancellation also pass.
- Existing `voxel_aux_cleanup_test.lua`: all 8 checks pass; cancellation and
  failed later uploads release every unpublished GPU part.

`comparison.json` contains paired synthetic measurements using Linux LÖVE 11.5
software GL (Mesa), four queued far map bodies and one near warp destination.
The far body jobs finished before the near full mesh: **4 -> 0**. The near full
mesh completed at pump/update **323 -> 194**. Measured CPU/pump work until that
completion: **1882.29 -> 477.88 ms**. This is work before the destination becomes
ready, not work saved across every eventual far map. Far work is deferred.
Atlas animation image uploads in one update: **8 -> 1**. p95 pump interval:
**7.56 -> 4.12 ms**; largest observed pump interval: **41.74 -> 20.11 ms**.

Cold current-map sample, with unchanged 12 ms target: 6 -> 7 updates,
62.99 -> 84.01 ms accumulated work; largest cold pump 13.71 -> 22.72 ms.
Those cold samples do not establish a first-world speedup. Prediction and opening
preparation aim to avoid reaching that cold path. Timing is sensitive to JIT,
allocation/GC and software GL. Budgets are cooperative targets, not hard limits:
map loading, analysis steps, texture bake/upload, individual packed uploads and
GC can exceed them. No Android device, retail ROM or Android FPS measurement was
used. Existing map quality and user distance options are retained.

Run the LOVE test like `voxel_boot_warmup_love`, staging this runner, fixture_data,
assets and the candidate MOD outside source. Set JP_QA_ROOT, JP_QA_OUT and
JP_QA_VERSION=after. Baseline uses jp.20 source with JP_QA_VERSION=before; all
common performance scenarios are identical. Do not package stage-before or
stage-after: they duplicate the source and generated runtime save data.
