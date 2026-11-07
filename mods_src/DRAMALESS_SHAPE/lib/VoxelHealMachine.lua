-- Attach the original healing animation to the modelled machine, not to
-- the player's screen-space feet. No party, sound or timing logic lives here.
local V = ...
local Voxel3D = V.require("Voxel3D")
local PaletteFX = require("src.render.PaletteFX")
local H = {}
local cached

local function matches(map, anchor)
  for y,row in ipairs(anchor.template.tiles) do
    for x,tile in ipairs(row) do
      if map:tileAt(anchor.x/8+x-1,anchor.z/8+y-1)~=tile then return false end
    end
  end
  return true
end

local function release()
  if cached then
    if cached.canvas then cached.canvas:release() end
    if cached.mesh then cached.mesh:release() end
  end
  cached = nil
end

function H.anchor(map, ha)
  if not (map and ha and map.tileAt and map.tileset) then return nil end
  local profile = V.data("voxel_heights")
  local list = profile.buildings and profile.buildings[map.tileset.id]
  if not list then return nil end
  -- A free walker may talk across the counter from an adjacent cell. Locate
  -- the actual model's tile pattern; the original screen-space anchor is
  -- only a distance hint, never a reason to float the FX above the player.
  local hintX, hintY = (ha.px - 32) / 8, (ha.py - 48) / 8
  local def=map.def or {}
  local maxX=def.width and def.width*4-1 or math.ceil(hintX)+8
  local maxY=def.height and def.height*4-1 or math.ceil(hintY)+8
  local best,distance
  for _, t in ipairs(list) do
    if t.id == "center_heal_machine_w" or t.id == "center_heal_machine_e" then
     for ty=math.max(0,math.floor(hintY)-8),math.min(maxY,math.ceil(hintY)+8) do
      for tx=math.max(0,math.floor(hintX)-8),math.min(maxX,math.ceil(hintX)+8) do
      local match = true
      for y, row in ipairs(t.tiles) do
        for x, tile in ipairs(row) do
          if map:tileAt(tx + x - 1, ty + y - 1) ~= tile then match = false;break end
        end
        if not match then break end
      end
      local d=(tx-hintX)^2+(ty-hintY)^2
      if match and (not distance or d<distance)then
        best,distance={x=tx*8,z=ty*8,template=t},d
      end
      end
     end
    end
  end
  return best -- custom art/layouts keep the ordinary pipeline fallback
end

-- Two faces, using the cabinet and monitor dimensions that build the
-- terrain model itself. The six balls retain their original 2-column,
-- 3-row spacing and aspect ratio, uniformly fitted inside its front panel.
function H.faces(anchor)
  local t, x, z = anchor.template, anchor.x, anchor.z
  local d, p = t.desk, t.parts[1]
  local plane = d.fascia[2] - d.fascia[1] + d.base[2] - d.base[1] + 2
  local size = math.min((d.x[2] - d.x[1] + 1) / 16, (plane - .4) / 18)
  local left = x + (d.x[1] + d.x[2] + 1 - 16 * size) / 2
  return {
    { x = x + 12, top = plane + p.facade[2] - 4 + 1,
      z = z + p.z + p.depth + .035, w = 8, h = 8,
      u = 4, v = 0, tw = 8, th = 8 },
    { x = left, top = plane - .2,
      z = z + d.z + d.depthPx + .035, w = 16 * size, h = 18 * size,
      u = 0, v = 8, tw = 16, th = 18 },
  }
end

local function meshFor(anchor)
  local verts, indices = {}, {}
  for n, f in ipairs(H.faces(anchor)) do
    local x, y, z, w, h = f.x, f.top, f.z, f.w, f.h
    local u0, u1 = (f.u + .01) / 16, (f.u + f.tw - .01) / 16
    local v0, v1 = (f.v + .01) / 32, (f.v + f.th - .01) / 32
    verts[#verts + 1] = {x, y-h, z, u0, v1, 1}
    verts[#verts + 1] = {x+w, y-h, z, u1, v1, 1}
    verts[#verts + 1] = {x+w, y, z, u1, v0, 1}
    verts[#verts + 1] = {x, y, z, u0, v0, 1}
    Voxel3D.pushQuad(indices, n-1)
  end
  return Voxel3D.newMesh(verts, indices)
end

function H.prepare(ctx)
  if not (ctx and ctx.state and ctx.state.healAnim and ctx.fx and ctx.fx.heal) then
    release()
    return nil
  end
  local ha, map = ctx.state.healAnim, ctx.state.map
  local anchor = cached and cached.anim==ha and cached.map==map and matches(map,cached.anchor) and cached.anchor or H.anchor(map, ha)
  if not anchor then release();return nil end
  local colors = ctx.spriteColors and ctx.spriteColors(map)
  local signature = tostring(ha.lit) .. ":" .. tostring(ha.visible)
      .. ":" .. tostring(PaletteFX.mode)
  -- Display ramps and hardware shade changes can transform an otherwise
  -- unchanged source palette while a healing animation is in progress.
  for _, c in ipairs(PaletteFX.effectiveColors(colors or PaletteFX.GRAYS) or {}) do
    signature = signature .. ":" .. table.concat(c, ",")
  end
  if not cached or cached.anim ~= ha or cached.map ~= map or cached.anchor.x~=anchor.x or cached.anchor.z~=anchor.z or cached.anchor.template~=anchor.template then
    release()
    cached = { anim = ha, map = map, anchor=anchor, mesh = meshFor(anchor),
      canvas = love.graphics.newCanvas(16, 32, {dpiscale = 1}) }
    cached.canvas:setFilter("nearest", "nearest")
  end
  if not cached.mesh then return nil end
  if cached.signature ~= signature then
    -- An interrupted capture has already cleared/partially written the
    -- texture; never let an older successful signature reuse those pixels.
    cached.signature = nil
    local g = love.graphics
    g.push("all")
    local previous = g.getCanvas()
    local ok, err = pcall(function()
      g.setCanvas(cached.canvas); g.origin(); g.setScissor(); g.setStencilTest()
      g.setDepthMode(); g.clear(0, 0, 0, 0); g.setColor(1, 1, 1, 1)
      g.setBlendMode("alpha", "alphamultiply")
      local shader = colors and PaletteFX.shader()
      g.setShader(shader)
      if shader then PaletteFX.sendColors(shader, colors) end
      -- Camera framing may replace ctx.cam for the geometry pass. fxHeal
      -- still closes over the original flat camera: capture in THAT space.
      local fxCam = ctx.fxCam or ctx.cam
      g.translate(-(ha.px - 24 - math.floor(fxCam.x)),
                  -(ha.py - 44 - math.floor(fxCam.y)))
      -- In the original flat art the monitor and first balls overlap by
      -- one row. Separate their captures before attaching to two faces.
      g.setScissor(4, 0, 8, 8)
      ctx.fx.heal("monitor")
      g.setScissor(0, 8, 16, 18)
      g.translate(0, 1)
      if shader then
        PaletteFX.sendColors(shader, colors); g.setShader(shader)
      end
      ctx.fx.heal("balls")
    end)
    g.setCanvas(previous); g.pop()
    if not ok then error(err) end
    -- Missing/unreadable extracted art must not suppress the flat fallback.
    if not ctx.state.healMachineImg then return nil end
    cached.signature = signature
  end
  return cached
end

function H.draw(frame)
  if not frame then return false end
  Voxel3D.draw(frame.mesh, frame.canvas)
  return true
end

return H
