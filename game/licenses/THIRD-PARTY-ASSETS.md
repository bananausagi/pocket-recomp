# Third-party fonts, skins and mod artwork

This notice identifies the licenses of the bundled assets. It does not
relicense them or grant any rights the original authors do not hold.
Original notices in each component remain authoritative.

## Misaki Gothic 8x8

- Copyright (C) 2002-2021 Num Kadoma.
- Assets: `assets/fonts/misaki/` (original BDF and generated bitmap atlas).
- Source: https://littlelimit.net/misaki.htm
- Terms: https://littlelimit.net/font.htm#license ; unrestricted use, copying,
  modification and commercial/noncommercial redistribution, without warranty.
- Full original notices: `assets/fonts/misaki/upstream-misaki.txt` and
  `LICENSE.txt`.
- Change: bitmap bits are placed unchanged into 8x8 atlas cells; ASCII cells
  use the separately listed public-domain Latin 8x8 bitmap so all screens
  share the same alphabet. No outline rasterization or smoothing.

## Noto Sans JP Regular

- Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'.
- Asset: `assets/fonts/noto/NotoSansJP-Regular.ttf`.
- License: SIL Open Font License 1.1; full original text in `assets/fonts/noto/OFL.txt`.
- Source: https://github.com/google/fonts/tree/main/ofl/notosansjp
- Source revision: `66a36c8c94b1a5d992ee4e7f392fccfe4945767c`.
- Change: the upstream variable font is instantiated at weight 400 with fontTools;
  all glyphs are retained. The modified font remains under OFL-1.1.
- The reserved name 'Source' is not used as this modified font's name.
- See `assets/fonts/noto/README.md` and `provenance.json` for build details and hashes.

## Plain Pixel Font

"Plain Pixel Font" by Douglas Vautour (Burpy Fresh) is licensed under CC-BY 4.0.

- Copyright Douglas Vautour (Burpy Fresh) 2025.
- Asset: `assets/fonts/plainpixel/PlainPixel-Regular.ttf`.
- Version: 0.009; font file unmodified.
- Source: https://burpyfresh.itch.io/plain-pixel
- License: https://creativecommons.org/licenses/by/4.0/
- Legal text: https://creativecommons.org/licenses/by/4.0/legalcode.en
- The bundled font metadata identifies its author, version and CC-BY-4.0 license.
- SHA-256: `7c0fa36aa0f99224644cee27a0f0ed509c3f49884e2453bc8c665aecd8d51458`.

## Latin 8x8

- Assets: `assets/fonts/latin8x8/font8x8_basic.h` and `latin.png`.
- Daniel Hepper; based on public-domain VGA fonts by IBM and Marcel Sondaar.
- Source: https://github.com/dhepper/font8x8
- Terms: Public Domain; see `assets/fonts/latin8x8/LICENSE.txt` and header notices.
- Change: the PNG atlas is rasterized from the supplied 8x8 character data.

## libretro common-overlays

- Attribution: libretro common-overlays contributors.
- Source: https://github.com/libretro/common-overlays
- License: CC BY 4.0, as recorded by the upstream COPYING and bundled skin README files.
- Upstream license: https://github.com/libretro/common-overlays/blob/master/COPYING
- License URI: https://creativecommons.org/licenses/by/4.0/
- Legal text: https://creativecommons.org/licenses/by/4.0/legalcode.en
- `assets/skins/gb_anim/`: `gamepads/gb_anim_portrait/gb_big.cfg` and its image files.
- `assets/skins/tv_crt/`: `borders/tv-integer.cfg` and `borders/img/tv-integer.png`.
- Changes: source configuration files are named `overlay.cfg` for packaging;
  configurations and artwork are unmodified as recorded in their retained READMEs.
- Keep those READMEs and any more specific notices supplied with future updates.

## Running Shoes

- Author: MadeinTaly. Copyright (c) 2026 MadeinTaly.
- Source: https://github.com/MadeinTaly/gen1recomp-running-shoes
- Pinned revision: `6f911f1c8e6f07584aa298c7fb97626cb486e532`.
- Bundled adapted version: 1.10.0+jp.3; current compatibility edits are recorded in
  `vendor/jp-mods/running_shoes/JP-ADAPTATION.md`.
- Code: MIT; original notice in `vendor/jp-mods/running_shoes/LICENSE`.
- Original artwork: **CC BY-NC-SA 4.0**, not MIT;
  `vendor/jp-mods/running_shoes/LICENSE-ART.md` is preserved verbatim.
- License URI: https://creativecommons.org/licenses/by-nc-sa/4.0/
- Legal text: https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode.en
- Scope specified by the author: sprites, patterns, images and artwork produced
  by procedural drawing code. Third-party artwork, where separately identified,
  keeps its own license. Do not infer that unlisted assets have CC0 or CC BY terms.
- The original pixel-mask table (`local ART`) and visual effect drawing remain
  in `main.lua`; absence of standalone image files does not mean an art-free mod.
- This fork does not change the author's artwork license or claim a separate
  commercial license. Its Japanese adaptation changes are described separately.

The CC licenses contain warranty disclaimers and do not license trademark or
patent rights. Consult the linked legal texts for the complete conditions.

## Field rendering adapted from Voxel Ascendant

- Source: https://github.com/Roxas2712/voxel-ascendant
- Pinned revision: `22c2bb5502290d4396aa3ab11d075ee2fb70e341`.
- Incorporated in Dramaless: deterministic outdoor weather, shared tree-template
  instancing with exact seam clipping, compact-house Y scaling, compact soft
  shadow parameters, canopy backdrop colours, and the field tilt-shift
  saturation/band progression. The existing filtered blur and independent
  battle-depth composition remain in use.
- The standalone Ascendant renderer and battle assets are not shipped.
- MIT notice: `vendor/jp-mods/DRAMALESS_SHAPE/ASCENDANT-FIELD-LICENSE`.
- The cloud texture and its drawing code were removed in jp.40. No Ascendant
  image assets are included.
