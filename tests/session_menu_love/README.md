# Session menu verification

`tests/session_menu_test.lua` runs with LuaJIT from the source root. It checks
pause/input isolation, progress-save gating, write-failure behavior, home return,
live settings and preference rollback without a ROM.

Run both the session and launcher settings fixtures with:

```sh
python3 tools/run_jp_settings_ui_qa.py --love /path/to/love --output /tmp/settings-ui-qa
```

Each fixture has its own temporary save directory. The result includes native
screenshots, input/render logs, and a JSON summary.

For the real LÖVE fixture, stage this directory's `main.lua` and `conf.lua` at an
isolated app root with `assets/fonts/misaki/` copied from the source tree. Set
`SESSION_QA_ROOT` to the source root and `SESSION_QA_OUT` to an existing output
directory. Run the staged app with LÖVE 11.5. It renders the genuine 8×8 bitmap
font through variable-size settings canvases and the original 160×144 pause
canvas. It writes native-size screenshots and checks direct touch targets,
16px logical controller rows, paging, keyboard navigation, safe-area insets, and
centered placement above touch controls. Category windows are capped at 320
logical pixels; wide detail windows put names and values on the same row.
The jp.12 dense launcher/session subset can be run with `--fixture dense`.
It covers the complete home routes, long MOD lists, small-window paging,
English, full-size attribution text preservation, and persisted settings.
The terrain visible behind selected samples is a synthetic drawing with no
ROM assets. These samples verify that the floating window preserves the
background and leaves the real touch controls visible. The
session menu has no persistent screen button or invisible opening hotspot.

These fixtures do not test Android hardware or a complete real-ROM playthrough.
