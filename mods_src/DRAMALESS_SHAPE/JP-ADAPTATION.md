# Japanese Red Android adaptation

Upstream: https://github.com/artyrambles/DRAMALESS_SHAPE

Pinned commit: 97ca3e1f8f7c3aa0b3e671db497076150f494051

The manifest limits this copy to red_jp on Gen1Recomp JP 0.1.0-jp.3.
The upstream update field is omitted to preserve these compatibility changes.
Original authors and license are preserved; see LICENSE.

VoxelBattleStandalone.lua adds light HUD backplates to keep Japanese names,
levels and HP readable over 3D terrain. The base game's HUD still owns the
text, gauges and animation. Mobile defaults are applied once by the host:
35-degree view, day lighting, half-resolution, short distance, no cast-shadow
or supersampling passes, sky-only water, native player back sprite.

JP.3 update: VoxelBattleScene uses Renderer.frameRects() for physical playfield
size and presentation scale, including Android touch-reserved layouts.
The local manifest advances to 2.0.4+jp.2 and uses a short Japanese name.

## 0.2.66-jp.4

本体の互換バージョンを本家0.2.66へ更新。manifestの対象を `>=0.2.66 <0.3.0` とし、既存の日本語表示・Android向け調整を維持。MODの改変済みコピーと個別設定は自動上書きしません。


## Local MOD 2.0.4+jp.4 / host 0.2.66-jp.9

The host exposes a narrowly scoped packed voxel mesh builder so this MOD can
use native vertex buffers without granting raw FFI to sandboxed MOD code.
Terrain build scheduling and packed buffers are adjusted to reduce route/town
transition stalls. Conservative view culling skips off-screen terrain index
ranges. Graphics preferences and original assets are retained.

Diagnostic log export now calls the Android document picker through the host's
shared export controller. It displays pending, saved, cancelled and failed
results and does not reapply graphics options just to export a log.

Battle sprite readback and native card capture now isolate graphics state,
including transform, scissor, shader, depth and stencil tests. A failed
readback is retried instead of caching an incomplete mask permanently. The
host also restores enclosed shade-zero holes in legacy extracted battle
pictures before palette conversion. Exterior-connected transparency and
authored true-color overrides are preserved; no new silhouette heuristic is
used to close open outlines.

Only a byte-identical managed copy of the previously shipped MOD is upgraded;
its 60-file fingerprint is retained in assets/jp-mods/upgrades-jp8.json, and the
old files are backed up before replacement. User modifications are not replaced.

See the host's TEST-RESULTS-JP9.md for measured results and their limits.

## Local MOD 2.0.4+jp.5 / host JP.11 camera input

The independent host settings menu now owns its touch, mouse and scroll
events while first- or third-person view is selected. Host pointer cancellation
also releases this MOD's private look finger, analog pad vector, pinch state,
mouse button holds and relative mouse capture. Contacts cancelled by opening
or closing the menu cannot resume camera movement or activate menu entries.
Fresh input resumes normally. Camera IDs, saved settings, camera-relative
movement, shoulder framing and terrain collision behavior are unchanged.

The host retains its corrected orbit endpoint during the interpolation into
and out of the free camera, preventing an initial jump while leaving the fully
placed first/third-person rig untouched.

For the host's Japanese battle presentation, encounters retain the current map
and the local encounter origin rather than relocating to an unrelated authored
arena. Nearby valid cells define the two participants' axis; the camera rig and
card footprint follow that axis and separation. The actual world camera blends
into the encounter camera over 0.55 seconds and returns over 0.4 seconds,
including world curvature and clip-space framing offsets. Starting another
encounter during a return preserves those offsets too. Native battle effects
use the same field coordinates. The older white HUD backing is omitted when
the host's Japanese HUD owns that layer.

This local MOD version is 2.0.4+jp.5 for host 0.2.66-jp.11. The managed prior
2.0.4+jp.4 copy is replaced only when every one of its 60 files matches the
actual delivered jp.10 APK fingerprint in assets/jp-mods/upgrades-jp10.json.
The prior files are backed up under jp-mod-backups/jp10 before replacement.
Edited, separately installed, duplicated or removed copies are preserved;
settings, enable flags and profiles are retained. The six companion MOD
archives and all native Android binaries remain unchanged in this host update.

## Local MOD 2.0.4+jp.6 / host 0.2.66-jp.12

Japanese encounters use a 50-degree downward camera with a long lens, larger
camera-facing participant cards and the host's centered field/HUD composition.
The base 12-degree lens is fitted to the usable field. Native effect positions
follow the new participant feet, while original SGB palette attribute geometry
remains separate. Grass is lowered locally around the two participants' feet;
ordinary world grass, distant grass and opaque terrain depth remain intact.

Actual road-jump boundaries gain a local bank connected to their upper ground,
with the same local floor used by world placement and camera framing. This is
a rendering model, not cartridge altitude data: it does not infer global map
heights or alter walking, jump rules, scripts, water, buildings or map borders.
Terrain analysis is cached, and the mesh cache revision is advanced for the
changed geometry. Unsupported connected-map ledges retain their prior shape.

The original healing-machine FX closure is captured only when the ball count,
flash or effective palette changes, then attached to the exact matched
machine's monitor and front-panel faces. The captures preserve the original
art, color mapping, two-column ball order, timing and sound. They use world
depth and follow the machine under camera motion. Unknown/custom layouts or
unreadable art keep the ordinary overlay fallback. Capture graphics state is
isolated, failed partial writes cannot be reused, and the small capture is
released when healing finishes. No cartridge art is included in this MOD.

Only the byte-identical managed 2.0.4+jp.5 copy from the delivered jp.11 APK is
newly eligible for replacement. Its 61-file fingerprint is recorded in
assets/jp-mods/upgrades-jp11.json; the prior files are backed up under
jp-mod-backups/jp11 before installation. All earlier migration protections are
retained. Edited, separately installed, duplicated or removed copies are
preserved, as are settings, enabled flags and profiles. The other six MOD
archives, native Android binaries, compiled resources and icons are unchanged.
See the host's TEST-RESULTS-JP12.md and verification/jp12 for the final synthetic
rendering, migration and packaging results and their device-testing limits.

## Local MOD 2.0.4+jp.7 / host 0.2.66-jp.13

Japanese encounters now use a 75-degree downward camera, enlarged participant
cards and centered field framing. The host's three battle-spacing choices feed
the shared battle geometry; its default is wide. Native effects follow the same
participant placement. The enemy remains legible through foreground occlusion
using a depth-aware silhouette, while ordinary world rendering keeps its
existing presentation.

The jp.12 local ledge bank is replaced by a connected-map height field. Actual
road-jump boundaries constrain relative upper/lower height by 12 units, allowing
broad upper ground and cumulative steps across connected maps. Walkable routes
around ledge ends use continuous slopes. Water and building footprints keep
level foundations without forcing the entire map to height zero; trees, props,
participants and camera placement share the same local floor. This remains a
rendering interpretation of cartridge jump boundaries, not new cartridge
altitude data or a change to walking, jumping, collision or scripts. Solving
is budgeted and cached, and mesh cache invalidation covers the new geometry.

Only the byte-identical managed 2.0.4+jp.6 copy from the delivered jp.12 APK is
newly eligible for replacement. Its complete 63-file fingerprint is retained
in assets/jp-mods/upgrades-jp12.json, and the prior copy is backed up under
jp-mod-backups/jp12 before installation. All earlier migration fingerprints
and protections remain in place. Edited, separately installed, duplicated or
removed copies are preserved, together with settings, enable flags and profiles.
The six companion MOD archives and all Android native binaries, compiled
resources and icons remain unchanged. See the host's TEST-RESULTS-JP13.md and
verification/jp13 for final evidence and the synthetic/device-testing limits.

## Local MOD 2.0.4+jp.8 / host 0.2.66-jp.14

The added road elevation is removed. Actual road-hop tile art is drawn on a
flat Y=0 plane, with only local semantic classification of the original jump
boundaries. The connected height solver, added slopes, raised foundations and
foliage lifting are removed. Ordinary buildings, trees, unrelated cliffs and
water retain their normal geometry. Original walking, jumping, collision,
events and saves are unchanged. The numeric ground-height API is retained, and
the mesh cache revision advances to 4 so earlier elevated meshes are rebuilt.

When no safe pair of terrain cells exists for 3D battle actors, the encounter
still renders its current-map 3D background at the actual encounter origin.
The native two-dimensional participants and effects remain in front of that
background; actor-specific grass flattening and foreground cutaway are skipped
for this fallback. An explicitly disabled 3D battle option is still respected.
The existing 75-degree camera, 12-degree lens and host battle layout are unchanged.

Only the byte-identical managed 2.0.4+jp.7 copy from the delivered jp.13 APK is
newly eligible for replacement. Its complete 63-file fingerprint is retained
in assets/jp-mods/upgrades-jp13.json, and the prior copy is backed up under
jp-mod-backups/jp13 before installation. All six earlier migration fingerprints
and protections remain in place. Edited, separately installed, duplicated or
removed copies are preserved, together with settings, enable flags and profiles.
The six companion MOD archives and all Android native binaries, compiled
resources and icons remain unchanged. See the host's TEST-RESULTS-JP14.md and
verification/jp14 for the final synthetic testing and packaging evidence.

## Local MOD 2.0.4+jp.9 / host 0.2.66-jp.15

The battle-only downward camera angle is 30 degrees. The 12-degree lens and
the projected participant feet, picture sizes and HUD placement in the four
supported layouts are retained. At the same encounter location, safe terrain
pairs are ranked by their proximity to the actual world camera heading to
reduce unnecessary rotation. Missing/invalid cameras and constrained terrain
retain the prior valid-pair fallback. Saved preferences, overworld camera angle,
collision, scripts and the player's world position are unchanged.

Battle grass occlusion is tested at its final shader position after the grass
depth pull, so grass cannot move back in front of a participant after the
visibility check. A grass-pass-only exemption also removes obstructing grass
roots from the participant silhouette without removing ordinary terrain or
the supporting floor. The battle-only uniforms are reset between passes.
Participant cards, ordinary world graphics preferences and palette behavior
are unchanged. The existing intro, send-out and command sequence uses this
correction, including the camera-entry interpolation.

Only the byte-identical managed 2.0.4+jp.8 copy from the delivered jp.14 APK is
newly eligible for replacement. Its complete 63-file fingerprint is retained
in assets/jp-mods/upgrades-jp14.json, and the prior copy is backed up under
jp-mod-backups/jp14 before installation. All seven earlier migration
fingerprints and protections remain in place. Edited, separately installed,
duplicated or removed copies are preserved, together with settings, enable
flags and profiles. The six companion MOD archives and all Android native
binaries, compiled resources and icons remain unchanged. See the host's
TEST-RESULTS-JP15.md and verification/jp15 for final evidence and testing limits.

## Local MOD 2.0.4+jp.10 / host 0.2.66-jp.16

The battle-only downward camera angle is lowered from 30 to 15 degrees. The
12-degree lens and the four layouts' projected participant feet, picture sizes
and HUD placement are preserved by refitting the encounter rigs. The prior
world-heading-based safe-pair selection, grass visibility correction and
foreground cutaway remain intact. Saved settings, overworld camera angles,
participant sprites, palette algorithms and gameplay rules are unchanged.

Road ledges return to the original six-unit-high box geometry, and the floor
query again agrees with the block top. This removes the jp.14 flat-road
overrides without reinstating the connected height solver or raised banks.
Walking, jumping and collision rules remain cartridge-driven. Mesh cache
revision 5 distinguishes these blocks from revision 4 flat meshes if disk
caching is enabled; the current provider disables disk caching and rebuilds
its in-memory meshes at startup. The compatibility classifier remains in place.

Only the byte-identical managed 2.0.4+jp.9 copy from the delivered jp.15 APK is
newly eligible for replacement. Its complete 63-file fingerprint is retained
in assets/jp-mods/upgrades-jp15.json, and the prior copy is backed up under
jp-mod-backups/jp15 before installation. All eight earlier migration
fingerprints and protections remain in place. Edited, separately installed,
duplicated or removed copies are preserved, together with settings, enable
flags and profiles. The six companion MOD archives and all Android native
binaries, compiled resources and icons remain unchanged. See the host's
TEST-RESULTS-JP16.md and verification/jp16 for final evidence and testing limits.

## Local MOD 2.0.4+jp.11 / host 0.2.66-jp.17

The battle-only downward camera angle is 10 degrees with a native vertical
field of view of 20 degrees. The four encounter rigs retain the projected
participant feet and the shared UI/actor sizing contract. Previous heading
selection, grass visibility and original block ledges are preserved.

Supported Japanese wild encounters keep the world background visible while
the camera moves into the battle over one second. This path requires active
voxel world rendering, 3D battles, the standalone battle style and a successful
initial scene render. Trainer encounters, 2D mode, disabled MODs, other
languages/versions and custom styles keep the original flash/wipe/black-hold
path. Captured world framing is retained through the handoff; original battle
logic, participants, effects and input progression still own the encounter.

Presentation preparation runs during the opening/title/player-start screens.
It prepares a bounded target-map neighbourhood using the live renderer's
cache and approximately two-millisecond mesh work slices, with separate map,
shader and atlas stages. Animated atlas images upload one per update. Skipping
the opening does not synchronously flush the queue; normal streaming reuses
the cache and continues any in-flight atlas. Disabling or reloading the MOD
cancels pending preparation. No world-enter/update, script, input or save-load
hook is invoked by this preparatory work. Driver shader compilation remains
an indivisible operation. Large grass, flower and figure auxiliary meshes use
the existing packed builder in original-order blocks of 4,096 quads, spreading
generation and upload work. Opaque terrain and water geometry are unchanged.

The host seeds an absent renderDistanceSetting with 64, the existing FAR
choice; explicit saved SHORT/FULL/MEDIUM/FAR choices remain unchanged. Other
previous defaults and saved preferences are retained. Only the byte-identical
managed 2.0.4+jp.10 copy from the delivered jp.16 APK is newly eligible for
replacement. Its complete 63-file fingerprint is retained in
assets/jp-mods/upgrades-jp16.json, with the prior copy backed up under
jp-mod-backups/jp16 before installation. All nine earlier fingerprints and
protections remain. Edited, separately installed, duplicated or removed copies
are preserved, together with settings, enable flags and profiles. The six
companion MOD archives and all Android native binaries, compiled resources
and icons remain unchanged. See TEST-RESULTS-JP17.md and verification/jp17 in
the host source for the complete changes, evidence and testing limits.

## Local MOD 2.0.4+jp.12 / host 0.2.66-jp.18

The encounter rigs keep a 10-degree downward angle and use a 30-degree native
vertical field of view. The four layouts target participant foot positions
at logical x=42 and x=124, coordinated with the host's separate scene and text
scales. This strengthens perspective and gives the near participant more room
without changing sprite data, saved camera preferences or movement rules.

Battle participant visibility protection now remains active through the flower
pass. Its decorative-mesh pass uses the existing projected participant masks
without the terrain-floor exemption that previously left flower roots opaque
over the participants. The ordinary world and terrain-floor behavior are
retained, and the pass-specific state is restored after drawing.

The extra Ball_Toss sound introduced during standalone encounter preparation
is removed. Original send-out and capture sounds, supported wild-encounter
background continuity and the trainer encounter's original transition remain.
Previous startup preparation, packed meshes, block ledges and palette behavior
are preserved. The host additionally defaults an absent window-size preference
to compact (0.75); explicit saved sizes remain unchanged.

Only the byte-identical managed 2.0.4+jp.11 copy from the delivered jp.17 APK is
newly eligible for replacement. Its complete 64-file fingerprint is retained
in assets/jp-mods/upgrades-jp17.json, with the prior copy backed up under
jp-mod-backups/jp17 before installation. All ten earlier fingerprints and
protections remain. Edited, separately installed, duplicated or removed copies
are preserved, together with settings, enable flags and profiles. The six
companion MOD archives and all Android native binaries, compiled resources
and icons remain unchanged. See TEST-RESULTS-JP18.md and verification/jp18 in
the host source for the complete changes, evidence and testing limits.


## Local MOD 2.0.4+jp.14 / host 0.2.66-jp.20

The Japanese encounter camera now stands at the default free-roam 3RD eye
height: 13px head + 4px pivot lift + 48px boom * sin(10 degrees), or 25.335px
above a level floor at the canonical 48px participant separation. The prior
normal/wide/wider/compact cameras were only 13.99/13.34/12.81/8.06px high.
Each rig is re-solved at this higher eye with the existing 30-degree native
vertical lens and exact participant feet/effect targets. This yields a
15.54/16.18/16.76/18.99-degree downward pitch without moving HUD or touch
controls, changing participant pictures, or altering world/free-camera input.
Arena-distance scaling and the continuous encounter/return camera blend remain.

Favorite registration, bicycle boost, original block ledges, native white
Japanese battle windows, same-map 3D battles and audio-clock synchronization
from the previous host release remain. This release returns the bundled
renderer to Dramaless Shape; it does not include Voxel Ascendant.
# jp.20 wild encounter presentation

- Wild encounters retain the actual BGM reveal cue and the engine's single
  entrance cry. On the first visible card frame, a 360 ms grounded leap starts
  at 84% size and settles exactly at the native battle anchor. It uses real
  presentation time, so accelerated game logic does not shorten the leap.
  Leap height is limited by the actual projected head position, retaining
  two scene pixels of headroom for tall Pokemon and portrait layouts.
- The captured overworld protagonist fades during the camera movement, reaching
  zero opacity before the native battle back picture takes over. Other actors
  and the first-person hidden-player rule remain unchanged.
- During the native wild send-out queue, the trainer back picture is captured
  intact, then smoothly retreats and fades using the original slide's progress.
  This prevents the 160-pixel capture from cropping the trainer and leaving a
  visible remainder at removal. Queue timing and the Pokemon send-out are intact.
- No wild blackout or added sound effect. Trainer encounters retain native wipes.

## jp.20 adjacent-map visibility

Neighboring terrain is culled against the closest point of its rectangular
bounds, rather than its potentially distant north-west origin. Terrain,
water, grass, flowers and neighboring figures share the same distance rule.
Each neighbor uses its own terrain atlas. Pending neighbor bodies are prepared
in approach order within the existing 5 ms idle work budget, without making
all neighboring maps urgent. Collision, connection metadata, the two-hop map
graph and saved render-distance preferences remain unchanged.


## Local MOD 2.0.4+jp.15 / host 0.2.66-jp.21

The six JP encounter rigs use a 46-degree native vertical lens while retaining
the normal 3RD standing eye height. They solve the new shared actor/effect
anchors for all three spacing choices, in portrait and compact compositions.
The wider and widest choices extend the participants' separation without
changing the independent native text scale.

Distant mesh submission combines adjacent visible ranges. Ordered foliage
ranges retain the original transparent triangle order; conservative frustum
bounds include depth pull and world curvature. No distance or shadow setting
is reduced. Existing nearest-edge connected-map visibility is preserved.

Predictive preparation prioritizes the two nearest adjacent destinations,
interleaves them before distant work and builds palette atlases incrementally.
Finished destination meshes are promoted without rebuilding when crossing a
seam. Cold urgent loading retains its earlier budget; visible promotions and
background work use shorter slices. Budgets remain cooperative rather than
hard per-frame guarantees.

World blur adds levels 4 and 5 without renumbering saved levels. Two reduced
resolution Gaussian passes are composited with the sharp source. Battle blur
is independent (off/normal/strong, strong by default) and composites distant
terrain using linearized scene depth before actors are drawn. It preserves
near scenery, Pokémon and native UI, detaches sampled depth from the target
on GLES and reattaches the original depth for the card pass. Without readable
depth it uses a conservative far/top fallback. Wild entry ramps its strength
with camera motion instead of turning it on abruptly.

Free-camera input follows the live selected pipeline level before the first
resumed logic update. Switching modes retires camera-owned look/pinch/mouse
state without clearing physical movement inputs; mouse A/B uses its own input
source so releasing it cannot clear a real touch hold.

Trainer encounters retain native flash/wipe timing and the original silhouette
entry/departure. Their camera is settled when the original wipe finishes; the
wild-only pan/hop/fade is not reused for trainer encounters. The host's native
animation block projection preserves each block's internal tile offsets so a
multi-tile thrown ball or burst no longer separates at the remapped anchors.

Only exact managed copies are upgraded. The complete delivered jp.20
2.0.4+jp.14 fingerprint is retained in assets/jp-mods/upgrades-jp20.json; the
old copy is backed up under jp-mod-backups/jp20. User modifications, other
MODs, saved preferences and the once-only Ascendant retirement are preserved.
The other six MOD archives remain byte-identical to jp.20.

See TEST-RESULTS-JP21.md and verification/jp21 for generated-scene comparisons,
actual LÖVE rendering, migration and package checks. Android physical-device
frame rates, retail-ROM playthroughs and audible speaker output are not part
of these checks.

## Local MOD 2.0.4+jp.16 / host JP.22

The host's optional `jpAnalogWalk` enables continuous stick-direction and
magnitude-based walking in the ordinary 3D camera, using the same collision and
cell-entry paths as existing first/third-person movement. It is off by default.
Native scripted movement still owns escorted/event sequences, and changing a
camera mode retires private gestures without discarding live movement input.

The default `jpBattleIntro="focus"` introduces the opponent with a close-up and
pulls back to the existing final encounter camera. `"original"` keeps the native
presentation. Disabled animations or reduced-motion settings skip the new
camera move. Final sprite/effect anchors, white Gen 1 HUD and touch-safe layout
remain unchanged. The trainer wipe is retained, with presentation synchronized
to the same playing BGM rather than accelerated simulation ticks.

`jpBattleBlur="strong"` remains the default. The background-only depth falloff
is adjusted for the actual battle viewing distance and has a depth-independent
fallback for unsupported shader paths. Actor cards and the HUD are drawn after
the background blur. World blur remains independently configurable.

The host adds optional party EXP, HM forgetting and reusable TMs, contextual
field-move questions, and an optional soft full-color palette. These features
are not taken from a third-party QoL MOD. The six companion MOD ZIPs are
byte-identical to jp.21; Voxel Ascendant remains excluded.

The delivered jp.21 managed renderer fingerprint is retained exactly in
`assets/jp-mods/upgrades-jp21.json`. Only recognized unedited bundled copies are
upgraded, with backups; manual/edited/missing copies and saved preferences are
preserved. The once-only historical renderer retirement is not repeated.

Validation and limits are recorded in `TEST-RESULTS-JP22.md` and the matching
source package's `verification/jp22` evidence. Android hardware and retail-ROM
playthroughs are not part of these synthetic automated checks.

## Local MOD 2.0.4+jp.17 / host JP.23

Field and battle now use the same live `pipelines.tiltshift` OFF/1–5 setting.
The legacy `jpBattleBlur` value can round-trip through old settings files but
does not influence rendering. FULL view no longer forces maximum blur or
hides its control. A filtered reduction pyramid and contiguous separable
Gaussian replace sparsely spaced samples. The sharp source, original depth,
actor cards and native HUD remain separate; the GLES precision correction and
independent depthless fallback are retained. No saturation boost is applied.

The focus introduction waits for the opening message to be completely drawn
before pulling back. The trainer's native pinned-picture path is disabled
only during this focus presentation: the player is an opaque world-anchored
card revealed by the camera, not another simultaneous fade-in. Pokémon size
uses a common field depth reference instead of cancelling the distant actor's
perspective. Original trainer transitions, source-clock synchronization,
gameplay queues, final feet and native effect anchors are preserved.

`jpAtmosphere="soft"` adds restrained face-light fill, a mild highlight
shoulder, outdoor distance haze using the existing sky colour, and feathered
ground contact shadows. `"off"` restores the previous scene treatment. The
lighting is part of the existing terrain shader rather than an additional
full-screen pass. Contact shadows follow the existing shadow switch, skip
water/unknown ground and fade with jump height. Sprite cards and UI stay
unlit and crisp. Existing palette, time, blur and shadow preferences remain
unchanged, and Voxel Ascendant remains excluded.

The delivered jp.22 managed renderer fingerprint is retained exactly in
`assets/jp-mods/upgrades-jp22.json`. Only exact managed copies are updated,
with backups; edited, manual and removed copies keep their previous
behaviour. The other six bundled MOD ZIPs remain byte-identical to jp.22.

See `TEST-RESULTS-JP23.md` and `verification/jp23` for the generated-scene,
shader, audio-clock, settings, upgrade and package evidence. These are not
Android hardware, retail-ROM, audible speaker or frame-rate guarantees.

## Local MOD 2.0.4+jp.18 / host JP.24

Field actors use their existing cast shadow, or one projected fallback when
the shadow map is unavailable. The extra atmosphere ellipse no longer stacks
on those shadows or repeats inside reflected actor rendering. The actual
`shadowQuality` ON/OFF switch also controls the fallback path; the dormant
quality ladder must not leave shadows enabled after the user selects OFF.
Battle terrain does not retain the previous field frame's actor shadows.
The battle cards retain their own contact shadows when enabled.

The shadow-map availability probe reuses a valid allocated target rather
than replacing it with the minimum size before fitting a larger size every
frame. The requested quality and shadow distance are unchanged.

Native battle cards are captured for the current presentation state, after
logic updates, rather than on the earlier input tick. Trainer withdrawal,
send-out pictures and damage visibility consequently use the same frame.
This prevents a withdrawn trainer from reappearing when its slide offset is
reset. Damage blinking is phased from the hit itself while preserving the
original duration and six cycles. Native hit sounds, faint cries and move
cries are not replaced.

The host also displays a Japanese area-name notice on arrival in towns,
routes and named wilderness regions, using the existing town-map names and
white pixel UI. It defers to dialogue, scripted events, battles and menus,
and does not write saves or alter map loading and movement.

For Japanese manual movement, FreeMove passes its current dash multiplier
to the host player's walk-cycle clock for one tick. Grid movement uses the
ratio of the normal step duration to the movement-speed hook's result.
Normal walking/biking, scripted escorts and non-Japanese movement retain
their cadence. Position, collision and input handling are unchanged; the
Running Shoes archive itself remains identical to jp.23.

The exact delivered jp.23 renderer fingerprint is retained in
`assets/jp-mods/upgrades-jp23.json`. Pristine managed copies are backed up and
updated; manual, edited and removed copies remain protected. The other six
bundled MOD archives remain byte-identical to jp.23. Voxel Ascendant remains
excluded. Validation and limits are in `TEST-RESULTS-JP24.md` and
`verification/jp24`.


## Local MOD 2.0.5+jp.18 / host 0.2.66-jp.25

This host adds an optional party follower. SpriteBillboards accepts its generated
in-memory 18px card dimensions while retaining ordinary NPC card geometry. The
follower graphic comes from the user's imported Pokemon image and existing shiny
adapter; no extracted ROM image or new companion MOD is bundled.

FreeMove preserves its fractional position when A interacts or START opens a menu.
Only native scripted player movement hands the logical position back to the grid;
the host's short shared pose/camera offset settles the visual difference. NPC-only
script steps do not snap the player. The jp.24 running cadence and the existing
first/third-person input behavior remain in place.

The former FULL camera-preset label is now DIORAMA (ジオラマ). Its saved level,
35-degree angle and component settings remain unchanged.

Cold-map preparation publishes the same-quality terrain and water together before
its grass, flowers and figures finish in the same cooperative job. The real map
body receives priority over its surrounding ring, and a confirmed native warp can
prepare its exact destination during the original fade. The opening warmup also
prepares the actual starting map before its neighbors. Atlas readiness is queried
without synchronously completing every animation frame. This changes preparation
order and first-visible timing, not the final mesh, palette or graphics settings.

A pristine managed 2.0.4+jp.18 copy upgrades using the exact delivered jp.24 APK
fingerprint in assets/jp-mods/upgrades-jp24.json and an exact old-file backup.
Edited, manually installed, duplicated or removed copies remain untouched, as do
all saved options and profiles. All six companion MOD archives remain identical
to jp.24. Older migration fingerprints and Voxel Ascendant retirement bookkeeping
remain, while Ascendant code is excluded. See host TEST-RESULTS-JP25.md for measured
checks and the limits of synthetic GL measurements.


## Local MOD 2.0.6+jp.18 / host 0.2.66-jp.26

Following Pokemon now reuse the same imported party-menu icon resolver and two
native poses as the party list. The previous reduced battle-front picture is
removed. VoxelScene selects these two poses consistently for the visible card,
shadow and silhouette, without invented direction mirroring. All map render
passes supply their current palette to the shared follower image. Native icon
transparency is identified before OBJ palette mapping, retaining white bodies.
No external sprite pack or extracted ROM artwork is bundled.

The mobile shadow writer and reader use the supported high precision for packed
depth and light-space coordinates. A receiver-plane gradient compares each of the
same four shadow taps at its sampled texel centre, preventing diagonal self-shadow
lines on slanted receivers as the light moves. Derivatives are computed before
alpha/occlusion discard. Devices without the required derivatives or fragment
precision, and drivers that reject the derivative shader, retain a working
fallback. Shadow strength, resolution, global bias and user settings are unchanged.

A pristine managed 2.0.5+jp.18 installation upgrades against the exact jp.25 APK
fingerprint in assets/jp-mods/upgrades-jp25.json. Edited, incomplete, duplicate,
manual and removed installations remain untouched; saved settings and all six
companion MOD archives are retained. Older fingerprints and Ascendant retirement
bookkeeping remain unchanged. See host TEST-RESULTS-JP26.md for synthetic GL/GLES
validation, upgrade tests and the untested Android-device scope.


## Local MOD 2.0.7+jp.18 / host 0.2.66-jp.27

Followers retain the original party-icon color indices before OBJ palette
mapping, so the field palette can apply each species' colors correctly. Native
six-frame directional sheets use their original back and side poses; replacement
icons retain their own layout. Visible cards, shadows and silhouettes share the
same pose selection.

Trainer battles bring the two trainer silhouettes in from opposing sides in one
fixed common 3D shot, preserving the original music, slide and reveal cues. Both
trainers use the same camera throughout the crossing. Wild encounter focus is
unchanged. Shared field/battle blur is selected by default, without overwriting
explicit saved preferences. Final implementation and validation are recorded in
the host TEST-RESULTS-JP27.md.

During actual move animations, a small action-camera lens movement zooms by at
most 3 percent and eases back without delaying the battle queue. The final native
scene composite and 3D camera receive the same transform, keeping pinned back
pictures and multi-tile effects aligned. HUD panels and text remain fixed. Existing
reduced-motion and disabled-animation preferences suppress this movement.
The jp.26 ShadowMap/Voxel3D precision, receiver-plane and compatibility corrections
remain unchanged. No new sprite pack or extracted ROM artwork is bundled.

The managed prior renderer is the exact delivered 2.0.6+jp.18 archive from jp.26.
Its fingerprints are retained in assets/jp-mods/upgrades-jp26.json. All six
companion MOD archives, older migration fingerprints and user-modification
protection remain unchanged. Voxel Ascendant remains excluded.


## Local MOD 2.0.8+jp.18 / host 0.2.66-jp.28

Battle encounters cut raised scenery on the camera side of a plane through the
far battle foot across the full view. The standing floor and scenery beyond the
plane retain their real geometry. This replaces rectangular card cutouts; the
background-only fallback protects the real origin floor. Ordinary field shaders,
ShadowMap and the shadow receiver calculation are unchanged.

Trainer entrances first show the opponent, then pull back while the player enters
from the other side, using the same original 72-frame music interval. Each draw
samples one common music position; projection corrections keep the opponent's
head and side edges in frame. Native battle clocks and extra sound cues are
unchanged. Wild focus and the previous action-camera behavior remain in place.

Touch-pad arrows now reach full walking speed at their visible centres, retaining
proportional movement nearer the middle and physical-stick settings. The host
allows bounded fixed-step catch-up at lower render rates instead of silently
slowing simulation. Player, FreeMove and Running Shoes are unchanged. Final
implementation and validation are recorded in the host TEST-RESULTS-JP28.md.
No external sprite pack or extracted ROM artwork is bundled.

The managed prior renderer is the exact delivered 2.0.7+jp.18 archive from jp.27.
Its fingerprints are retained in assets/jp-mods/upgrades-jp27.json. All six
companion MOD archives, older migration fingerprints and user-modification
protection remain unchanged. Voxel Ascendant remains excluded.


## Local MOD 2.0.9+jp.18 / host 0.2.66-jp.29

The trainer entrance holds a close view of the opposing trainer as they slide in
from the left. It keeps that view until the complete challenge message has been
drawn, then pulls back while the player trainer enters the near side. A renderer
heartbeat lets the host hold that displayed challenge until the final camera pose
has actually appeared; fallback renderers and original/reduced-motion modes do
not depend on that heartbeat. Native intro music and the initial silhouette cue
retain their own timing. The new pullback follows presentation time rather than
being consumed before a fast-speed frame reaches the display.

The host now supplies an opposing trainer's ball release during the existing
send-out interval. Its closed ball, opening flash and emerging Pokemon are
captured together into the 3D card so they share one position and scale. Wild
encounters and the player's existing throw remain on their established paths.
No external sprite pack or extracted ROM artwork is bundled.

The jp.28 foreground plane cut, fixed-step movement recovery and touch-pad
normalization are preserved byte for byte, alongside the shadow corrections.
The managed prior renderer is the exact delivered 2.0.8+jp.18 archive from jp.28,
fingerprinted in assets/jp-mods/upgrades-jp28.json. All six companion MOD archives,
older migration fingerprints, saved preferences and user-modification protection
remain unchanged. Voxel Ascendant remains excluded. See TEST-RESULTS-JP29.md for
the final measured scope and the Android-device limitation.


## Local MOD 2.0.10+jp.18 / host 0.2.66-jp.30

Battle camera motion changes the point of attention with the current action and
adds a slow, small orbit around the two battlers. It moves the actual 3D camera
rather than enlarging the composite image. The ordinary pinned player back
picture remains anchored above the command window; the other cards and native
move effects share their current projected feet. Scene scenery and silhouettes
therefore receive the same camera. The new jpBattleCameraMotion boolean defaults
to enabled, can be disabled independently in battle settings, and is retained by
settings import/export. Reduced-motion and disabled-animation preferences still
suppress the movement. The battle queue and its clocks remain authoritative.

Foreground clearance no longer extends to the far battler across the whole arena.
It clears raised scenery only in a short region immediately in front of the real
camera, capped at two map cells and shortened for close-up shots. The standing
floor and scenery beyond that clearance remain intact. It does not cut individual
rectangles around actors. Dense terrain farther from the camera may intentionally
still occlude an actor. ShadowMap and the shadow receiver calculation are unchanged.

The previous opposing-trainer close-up, challenge-text pullback, opponent ball
release and wild intro are retained. No external sprite pack, ROM artwork or
additional native binary is bundled. The managed prior renderer is the exact
delivered 2.0.9+jp.18 archive from jp.29, fingerprinted in
assets/jp-mods/upgrades-jp29.json. All six companion MOD archives, older migration
fingerprints, saved preferences and user-modification protection remain unchanged.
See TEST-RESULTS-JP30.md for the final measured validation scope.

## Local MOD 2.0.11+jp.18 / host 0.2.66-jp.31

Ordinary attacks track the recipient throughout the move, native blink or
screen shake, and HP drain. Host metadata identifies self-targeted status moves.
Attention translates eye and focus together across the image plane, with a small
physical push-in and the existing fit guard. This avoids making the selected
card smaller by only turning the view axis. The small orbit, fixed FOV, native
effect anchors, fixed HUD and optional pinned player back are preserved.

Foreground clearance is now a local radial footprint around the real camera.
Whole low objects, grass, flowers, water and the floor remain visible. Cached
structure masks classify complete objects; the clearance therefore does not
leave the bottom of a tall object as a stump. A narrow stable coverage band
softens the outer boundary while keeping actual depth for retained fragments.

Returning to the launcher and opening another game session now reconnects the
cached native input hook to the new camera and FreeMove instance. It releases
the old walker and does not stack hooks or change the saved analog-walk choice.

Only the exact managed renderer from the delivered jp.30 APK is newly eligible
for upgrade, recorded in assets/jp-mods/upgrades-jp30.json. Edited copies,
preferences and the six companion archives retain their previous handling.
See TEST-RESULTS-JP31.md for the synthetic rendering, input, migration and
packaging checks; Android hardware was not tested for this release.


## jp.39 field adaptation (2026-09-22)

Source comparison against the exact shipped jp.37 Voxel Ascendant trial,
based on upstream commit 22c2bb5502290d4396aa3ab11d075ee2fb70e341 (MIT).
ASCENDANT-FIELD-LICENSE preserves the source notice.

- TreeInstances adapts shared templates plus per-instance offsets from the
  trial ChunkMesher. Seam masks, shade and UVs match the expanded renderer.
  The sun and camera shaders receive the same offsets. Capability rejection
  releases partial resources and falls back once to the paged original path.
- MeshParts shares already completed body meshes with the outer ring. Separate
  ownership covers replacement, cancellation and water surfaces.
- Five compact OVERWORLD house profiles opt into the source's 1.4x height.
  FieldStyle allows original/taller proportions; floor plans and doors stay put.
- Field tilt shift adopts the source's 1.10/1.18/1.28 saturation progression and
  narrower focus band. The existing contiguous filtered blur prevents ghosting;
  battle blur, battle cameras, stepping effects and game state are unchanged.
- Short soft shadows and forest canopy backdrop colours come from the same
  source. Existing day/night choices remain available in Diorama mode.
- options.lua is shipped as data for prelaunch settings and verified against
  the runtime schema. It does not execute MOD code before starting the game.


## jp.40 field/input fixes (2026-09-22)

- Removed the Ascendant cloud atlas, upload/draw path and settings row; procedural sky and weather remain.
- Healing overlays locate the authored machine template, including adjacent and fractional interaction positions, and validate cached anchors.
- Airborne actors use start/landing floor heights, avoiding the six-pixel ledge midpoint jolt. The host rebases fractional visual offsets across native connection steps.
- A confirmed area destination exposes cooperative terrain/atlas readiness. The Japanese 3D host holds the old world with identity palettes until entry; loading no longer allocates black artwork or copies a screen every frame.
- The host's visible touch joystick feeds the existing analog walker, with radial clamping, multi-touch ownership and explicit OFF. Field menus remain directional.
- Host autosaves use the existing current-slot report, MOD veto and backup path after safe field checkpoints, with a 60-second interval and idle-state gate.
- Standalone Ascendant rendering remains retired. Original battle, grass, shadows, footprint, water and menu effects remain installed.

## jp.41 adjacent-map preparation (2026-09-22)

- Direct north/south/east/west connections no longer compete with the two closest door predictions. Prepare all connected bodies and atlases; only the two nearest connections within 16 cells request full decorative rings.
- Rank by distance to the actual overlapping connection strip, including block offsets. Nearby body requests precede decorative work without increasing the normal 2 ms mesh slice.
- Within 16 cells, prepare up to six additional bodies from the nearest destination's upcoming neighbourhood. Retain the native hop count and zoom reach when computing masks; reuse live map objects and load at most one new object per update.
- Start adjacent animation preparation before geometry completes. One shared 1 ms atlas slice covers current, predicted and visible maps. Render-side reservation uses the correct static atlas until that continuation completes, preventing synchronous generation of a whole animation on the first visible frame.
- Keep completed/partial prediction products across seams, refresh palette readiness without requiring a step, and clear obsolete approach hints on reversal or reset.
- No gameplay, collision, scripts, save format, controls, effect options or battle behavior changes.

## Local MOD 2.0.21+jp.18 / host 0.2.66-jp.42

Connected outdoor scenery dissolves over 0.6 seconds in the moving camera.
Complementary 8x8 screen coverage mixes the outgoing/incoming distant terrain
without sorting transparency or allocating a history canvas. Nearby terrain,
actors, water effects and UI keep their normal passes. At most two explicitly
retained mesh layouts are held; common meshes draw once. Reverse crossings
reverse coverage. The existing depth-of-field pass softens distant coverage;
with blur disabled its fine ordered pattern can be visible during the fade.
The field-effects category has a default-ON sceneryFade toggle. Reduce motion
and OFF bypass it. The jp.41 preloading budgets and scheduling stay unchanged.

Healing-image capture uses the original FX camera, separate from the adjusted
3D framing camera. The host keeps healFxDrawn on the shared context because the
bundled shiny-effects wrapper forwards only the first two drawFx arguments.
This removes the duplicate floating legacy balls without replacing that MOD,
changing its sparkles, or changing healing timing, party data or sound.

JP.43 / 2.0.22+jp.18: Replace screen-bound weather tiles and rectangular fog
with one reusable depth-tested world-space particle batch (maximum 768 quads),
analytic rain/snow/rings/mist, and the existing distance-haze uniforms. Adjacent
ordinary routes share deterministic weather; transitions blend for 2.4 seconds.
Weather strength and soft lightning have independent settings. No cloud image,
new render target, game RNG call or battle weather pass. Prior grass pressure,
battle presentation, scenery dissolve and healing attachment code retained.

## 0.2.90-jp.90

クリスタル（crystal_jp）に対応。赤と同じボクセル3Dの描き方で、ジョウトの町・道路・建物・部屋を立体にする。クリスタルのマップを赤のマップと同じ形に読みかえる層（Gen2Facade / Gen2Host）を足しただけで、赤の描き方は変えていない。クリスタルではタイルごとの高さの手作り設定が無いので、通れる・通れない・水・だんさ・カウンター・木の判定から高さを決める。水や花のアニメ、一人称・自由カメラ、いあいぎりの木の即時反映、つりの演出はクリスタルでは動かない。

## 0.2.91-jp.91

クリスタルの3Dを赤と同じ作りに近づけた。ジョウトのタイル表と建物の形、水と花のアニメ、マップ端のふち、時間帯（朝・昼・夜）の明るさ、いあいぎり後の即時反映、つり・かいふくマシン・砂ぼこり、森と洞窟の雰囲気、一人称・自由カメラ、バトル背景の3Dをクリスタルでも動くようにした。赤の描き方は jp.90 と同じ。
