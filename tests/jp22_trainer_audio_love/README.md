# Trainer intro music synchronization

## jp.27 crossing entrance

The modern trainer option now shows both native trainer silhouettes crossing
from opposing sides in the settled 3D battle shot. It transfers at the same
3.6-second slide-start cue as the original option and preserves the original
4.8-second colour/text cue. Only acceleration and braking of the world-space
cards are eased; there is no opponent-only close-up or additional sound.
The former modern-only 72-frame black wait is now the visible entrance.
Wild opponent focus and the original-mode linear slide are unchanged.

Current regression cases live in `jp22_trainer_music_timing_test.lua`,
`jp23_battle_intro_test.lua`, `jp_trainer_original_render.lua`, and the trainer
section of `jp_battle_seamless_render.lua`. Both portrait and landscape renders
check complete native art, opposing crossing paths, screen-edge entry, native
landing colours and settled battle anchors. The low-cost Source fixture below
now expects 3.6-second entry and 4.8-second landing in both options at 1x/4x.

## Original jp.22 diagnosis and evidence

The previous trainer wipe and silhouette entrance counted gameplay ticks,
while battle BGM used real-time audio. At 4x speed the opponent therefore
appeared at one quarter of the intended music phase. Wild encounters already
used `Music.playbackClock`; trainer encounters now use that same transport.

Japanese built-in trainer transitions retain their original wipe shape and
frame budgets. The normal inward spiral is 156 frames, followed by the
existing 60-frame hold and 72-frame silhouette slide. The original option
enters the battle at 3.6 seconds and lands at 4.8 seconds; an available focus
renderer presents its first close-up at 4.8 seconds, replacing the native
slide. These are the port's existing presentation budgets, not a new claim
that the approximated 60-frame loading hold matches original hardware.

The renderer readiness hook decides whether focus is actually available.
Absent providers, custom transitions and non-Japanese paths keep their
existing contracts. Native trainer entrance derives remaining slide frames
from the same clock. Fast game updates cannot advance a paused audio source.
Focus queues wait for a physical draw; native fallback also acknowledges that
draw, preventing a stalled introduction if the MOD renderer fails later.

Verification:

- `tests/jp22_trainer_music_timing_test.lua`: 158 checks. Four native styles,
  original/focus, 1x/4x, paused clock, cancellation, native picture fallback,
  silent backend and unchanged non-Japanese behavior.
- `tests/engine/battle_music_clock_test.lua`: 55 existing checks, including
  queued PCM, source replacement, pause, unsupported/null audio and looping.
- `tests/japanese_seamless_transition_test.lua`: 129 ownership checks.
- `tests/jp_battle_seamless_render.lua`: 169 actual GL checks in the integrated
  run, including existing wild regression plus four trainer cases with the
  real overworld entry, battle state, renderer and OpenAL Source. Exactly one
  BGM Source per case and no additional Ball_Toss during intro.
- This low-cost fixture: 24 actual Source checks. It isolates clock accuracy
  from full renderer readback overhead. Original entry was 3.600000 seconds,
  original landing and focus first frame 4.800125 seconds at both 1x and 4x.

The integrated Mesa llvmpipe run had physical frame/readback steps up to
0.56 seconds and first visible focus frames 0.40–0.46 seconds after the cue.
That test verifies behavior at available rendered frames, not Android frame
rate. The low-cost Source test verifies audio-clock timing separately.
OpenAL used null output with authored PCM; physical speaker latency and
Android/OLED hardware were not measured. No ROM assets are included.

Run the low-cost fixture from the source root:

```sh
JP_QA_ROOT="$PWD" JP_QA_OUT=/absolute/evidence/directory love tests/jp22_trainer_audio_love
```

The full render runner is the existing `jp_battle_scene_actions_render`
fixture with `JP_QA_BATTLE_SEAMLESS=1`, `JP_QA_SEAMLESS_CASE=1` and current
vendor MODs mounted; its trainer section runs all four cases automatically.
