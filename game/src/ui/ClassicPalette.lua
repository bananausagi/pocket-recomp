-- SPDX-License-Identifier: GPL-3.0-only
-- Session chrome follows the saved display palette, independently of world
-- lighting, hardware fade registers and the live palette picker's preview.
local ClassicPalette = {}
local PaletteFX = require("src.render.PaletteFX")
local Palette = require("src.render.Palette")
local GameVersion = require("src.core.GameVersion")
local cache = setmetatable({}, { __mode = "k" })
local shader

local function named(pack)
  return pack and pack.palettes and pack.palettes.MEWMON
end

local function menuBase(data, mode)
  local pack = data and data.palettes
  if GameVersion.isYellow() then
    local yellow = PaletteFX.yellowPack()
    if mode == "ogred" or mode == "redpp" or mode == "redpp_soft" then
      local cgb = pack and pack.cgbBase and pack.cgbBase.MEWMON
        or yellow and yellow.cgbBase and yellow.cgbBase.MEWMON
      if cgb then return cgb end
    end
    return named(yellow) or named(pack) or PaletteFX.GRAYS
  end
  if mode == "ogred" then return PaletteFX.ogBg() end
  if mode == "redpp" or mode == "redpp_soft" then
    return named(PaletteFX.gbcPack()) or named(pack) or PaletteFX.GRAYS
  end
  return named(pack) or PaletteFX.GRAYS
end

function ClassicPalette.colors(game)
  local options = game and game.save and game.save.options
  if not options then return nil end
  local mode, id = options.colors or "gbc", options.palette or ""
  local pack = game.data and game.data.palettes
  local version = GameVersion.get()
  local previous = cache[game]
  if previous and previous.mode == mode and previous.id == id
      and previous.pack == pack and previous.version == version then
    return previous.colors
  end
  local colors = id ~= "" and Palette.ramp(id) or nil
  if not colors then
    if mode == "classic" then colors = PaletteFX.CLASSIC
    elseif mode == "og" or mode == "og_inv" then colors = PaletteFX.GRAYS
    else colors = menuBase(game.data, mode) end
    colors = PaletteFX.displayColors(colors, mode)
    if mode == "og_inv" or mode == "gbc_inv" then
      colors = { colors[4], colors[3], colors[2], colors[1] }
    end
  end
  -- Own normalized uniforms; do not retain mutable global palette colors or
  -- call effectiveColors(), which also applies cave/poison/warp shade maps.
  local normalized = {}
  for i = 1, 4 do
    normalized[i] = { colors[i][1] / 255, colors[i][2] / 255, colors[i][3] / 255 }
  end
  cache[game] = { mode=mode, id=id, pack=pack, version=version, colors=normalized }
  return normalized
end

function ClassicPalette.shader(colors)
  if not colors then return nil end
  if shader == nil then
    local ok, result = pcall(love.graphics.newShader, [[
      extern vec3 c0; extern vec3 c1; extern vec3 c2; extern vec3 c3;
      vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4 p = Texel(tex, tc);
        float shade = p.a > 0.0 ? p.r / p.a : 0.0;
        vec3 mapped = shade > 0.83 ? c0 : (shade > 0.5 ? c1 : (shade > 0.17 ? c2 : c3));
        return vec4(mapped * p.a, p.a);
      }
    ]])
    shader = ok and result or false
  end
  if not shader then return nil end
  for i = 1, 4 do shader:send("c" .. (i - 1), colors[i]) end
  return shader
end

return ClassicPalette
