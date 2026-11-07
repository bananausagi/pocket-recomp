# Native JP title surround

The supported Japanese title extends its own resolved paper color into the
window surround, including when a generic black/white/palette letterbox or
mobile Faithful setting was saved. Faithful size/position and saved options
remain unchanged. Overseas titles, registered MOD titles, explicit `boot.title`
customizations, and the opening movie retain their existing surround rules.

Run the actual TitleState, Game.draw and Renderer with authored geometric art:

```sh
JP_QA_ROOT=/absolute/source TITLE_QA_OUT=/absolute/existing/evidence love tests/title_surround_love
```

The final run passes 81 checks: portrait 480×800 and 1160×1536, landscape 800×480,
white and tinted title paper, classic/inverted/custom display palettes, shade
remaps, MOD palette zones, explicit generic overrides, Faithful, original title
bounce/ribbon progress, and other-screen compatibility. Each title case compares
native canvas bytes and presentation geometry with the title opt-in temporarily
disabled. Only the surround changes. No ROM art or user image is used or copied
into this fixture. Generated geometric assets stay in its private LÖVE identity.

Evidence: `verification/jp18/title/{results.json,summary.json,run.log,*.png}`.
Timing, Android performance and actual imported-ROM artwork are not measured.
