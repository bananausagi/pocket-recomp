# Opening surround rendering fixture

Run the actual IntroMovie, Game.draw and Renderer on authored geometric images:

```sh
JP_QA_ROOT=/absolute/source OPENING_QA_OUT=/absolute/evidence love tests/opening_surround_love
```

82 checks cover all four phases, portrait/landscape, display palettes and shade maps, explicit letterbox overrides and mobile FaithfulRes. Generated fixture images stay in LOVE's save directory. No ROM assets are needed.
