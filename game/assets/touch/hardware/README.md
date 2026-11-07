# Hardware-style touch controls

Original geometry and material renders for the built-in overlay. Burgundy
plastic, dark moulded plastic and grey rubber are lit by a soft light. The
material renderer calculates bevel normals, surface grain and soft shadows
offline; the app draws cached PNGs with linear mipmap filtering.

`tools/render_touch_hardware.lua` exports `render(write)` for a LÖVE 11.5 host.
The callback receives each basename and the complete PNG bytes. Run once to
regenerate this directory. All textures are 512×512, except the rubber and
action keys (512×256). Labels use the separately licensed, bundled Noto Sans JP.

The material geometry is original and follows the repository's code license.
