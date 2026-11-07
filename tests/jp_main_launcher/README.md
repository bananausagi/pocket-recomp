# ROM-free main entrypoint integration check

Runs the real main.lua launcher and event loop with isolated storage. The scenario exercises touch, keyboard, gamepad navigation, settings persistence, JSON export and JSON import. Only the Android file-picker boundary is stubbed; the real settings codec, model, native lifecycle controller and save path run.

```sh
python3 tests/jp_main_launcher/run.py --root . --output /tmp/jp-main-qa --scenario tests/jp_main_launcher/scenario.json --love /path/to/love --width 480 --height 800
```

Use LÖVE 11.5; an offscreen software OpenGL driver is supported. No real ROM is read or included. Scenario Lua actions are developer-owned test code and are not an application import format.
