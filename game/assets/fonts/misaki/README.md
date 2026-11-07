# Misaki Gothic 8x8 bitmap font

Copyright (C) 2002-2021 Num Kadoma.

- Author's page: https://littlelimit.net/misaki.htm
- Author's terms: https://littlelimit.net/font.htm#license
- Download: https://littlelimit.net/arc/misaki/misaki_bdf_2021-05-05.zip
- Download SHA-256: `a275f173cf5935890f84d3e65d05b1bf73028e4d4bf41cb3de0ef3b5ebe8e217`
- Unmodified BDF SHA-256: `28a8745552c844f7c73f11bdf4470225f5e08645a98c5404b2e25bb326a5cabd`

The author's `misaki_gothic.bdf`, `upstream-misaki.txt` and
`upstream-readme.txt` are retained unchanged. The font permits use, copying,
modification and redistribution for commercial and noncommercial purposes.
The full original terms are in `upstream-misaki.txt` and `LICENSE.txt`.

`tools/build_misaki_atlas.py` copies each BDF bitmap bit into `misaki8x8.png`.
It performs no outline rasterization, smoothing or resizing. All 7,171 glyphs
use 8x8 cells. ASCII cells use the existing public-domain Latin 8x8 bitmap
(`../latin8x8/LICENSE.txt`) so Latin letters match the game in every screen;
all other cells retain the Misaki bitmap. Every UI character advances by
8 pixels. `glyphs.json` maps Unicode characters to cells.

This is the pre-import UI font and the missing-glyph fallback. After importing
Japanese Red, the launcher reads its extracted kana/border font privately;
in-game UI uses the game's `src/render/Font.lua`. ROM-extracted font pixels
are never copied into distributed assets.
