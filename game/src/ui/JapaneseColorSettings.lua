-- Display-only Gen 1 color names shared by home and in-game settings.
-- Keep PaletteFX's persisted mode ids and custom palette selection untouched.
local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")
local C = {}

-- Descriptions follow PaletteFX's runtime paths: named SGB zone palettes,
-- usesGbcPack's terrain/OBJ colors, and effectiveColors' four-shade ramps.
local modes = {
  gbc = { "エリアの カラー", "Area colors",
    "ばしょごとの カラーです。\nスーパーGBふうの いろわけです。",
    "SGB colors change with the area or battle Pokemon." },
  redpp = { "フルカラー", "Full color",
    "ものごとに いろを つけます。\nちけい・ひと・ポケモンを いろわけ。",
    "Terrain, people and Pokemon each use their own colors." },
  redpp_soft = { "おだやかな カラー", "Gentle full color",
    "あざやかさを おさえます。\nフルカラーと おなじ いろわけです。",
    "Full color with gentler, less saturated colors." },
  og = { "しろくろ", "Black and white",
    "しろくろの 4だんかいです。\nしろ・はいいろ・くろを つかいます。",
    "Four shades from white through gray to black." },
  og_inv = { "しろくろ はんてん", "Inverted black and white",
    "しろと くろを いれかえます。\nしろくろの あかるさを はんてん。",
    "Reverses the four gray shades: white areas become black." },
  gbc_inv = { "カラー はんてん", "Inverted area colors",
    "カラーの こさを いれかえます。\nエリアの カラーを はんてん。",
    "Reverses the order of the four shades in each SGB palette." },
  classic = { "GBの みどり", "Game Boy green",
    "みどりの 4だんかいです。\nむかしの ゲームボーイふうです。",
    "Four green shades inspired by the original Game Boy screen." },
}

-- ogred keeps its old save id for Red, Blue and Yellow. A launcher may
-- describe a different version before GameVersion.current has been changed.
local hardware = {
  red = { "GBC あか", "GBC Red",
    "GBC あかばんの いろです。\nはいけいは あか、ひとは みどり。",
    "Red's GBC colors: red backgrounds and green people." },
  blue = { "GBC あお", "GBC Blue",
    "GBC あおばんの いろです。\nはいけいは あお、ひとは ピンク。",
    "Blue's GBC colors: blue backgrounds and pink people." },
  yellow = { "GBC ピカチュウ", "GBC Yellow",
    "GBC ピカチュウの いろです。\nばしょや ポケモンで いろが かわります。",
    "Yellow's GBC colors change with the area and Pokemon." },
}

local function entry(mode, version)
  mode = mode or PaletteFX.mode
  if mode == "ogred" then
    return hardware[version or GameVersion.get()] or hardware.red
  end
  return modes[mode]
end

function C.label(mode, english, version)
  local selected = entry(mode, version)
  return selected and selected[english and 2 or 1] or tostring(mode or PaletteFX.mode or "")
end

function C.description(mode, english, version)
  local selected = entry(mode, version)
  return selected and selected[english and 4 or 3]
    or (english and "Colors supplied by this mode." or "この モードで きめられた いろです。")
end

function C.customDescription(english)
  return english and "Your custom four-color palette takes priority over the color mode."
    or "カスタムの 4しょくを つかいます。\nいろの モードより ゆうせんします。"
end

return C
