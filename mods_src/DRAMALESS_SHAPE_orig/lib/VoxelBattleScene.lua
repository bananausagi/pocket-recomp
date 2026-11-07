-- Voxel-map arena rendering for StadiumBattleFX API 1.
-- Dramaless owns the environment pass; the host injects battle actors.

local V = ...

local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")
local ChunkMesher = V.require("ChunkMesher")
local TerrainAtlas = V.require("TerrainAtlas")
local VoxelScene = V.require("VoxelScene")
local BattleCam = V.require("BattleCam")
local DayNight = V.require("DayNight")
local AntiAlias = V.require("AntiAlias")
local TiltShift = V.require("TiltShift")
local PaletteFX = require("src.render.PaletteFX")
local Map = require("src.world.Map")

local Scene = {}
local GB_W, GB_H = 160, 144
local INDOOR_SHADE = 4

local function pixelSize()
  -- Android's touch layout reserves part of the window. The engine crops
  -- world overrides to that playfield; a full-window arena loses its bottom
  -- and right edge. Render directly at the actual playfield's pixel size.
  local ok, Renderer = pcall(require, "src.render.Renderer")
  if ok and Renderer and type(Renderer.frameRects) == "function" then
    local got, rect = pcall(Renderer.frameRects, Renderer)
    if got and rect and tonumber(rect.pw) and tonumber(rect.ph)
        and rect.pw > 0 and rect.ph > 0 then
      return math.floor(rect.pw), math.floor(rect.ph)
    end
  end
  if love.graphics.getPixelDimensions then
    local w, h = love.graphics.getPixelDimensions()
    if w and h and w > 0 and h > 0 then return w, h end
  end
  if love.graphics.getDimensions then return love.graphics.getDimensions() end
  return GB_W, GB_H
end

local function fitScale()
  local ok, Renderer = pcall(require, "src.render.Renderer")
  if ok and Renderer and type(Renderer.fitScale) == "function" then
    local okScale, scale = pcall(Renderer.fitScale, Renderer)
    if okScale and type(scale) == "number" and scale > 0 then return scale end
  end
  local w, h = pixelSize()
  return math.max(1, math.floor(math.min(w / GB_W, h / GB_H)))
end

-- WIDE battles may be presented with BATTLE SIZE = FILL.  In that mode
-- Gen1Recomp scales the 304x144 battle surface by a fractional Up value
-- (Renderer:frameRects), while fitScale() deliberately stays integer.  The
-- voxel camera has to use the same presentation scale as the native battle
-- layer or the world cards are pulled inward relative to move/Poke Ball FX.
-- Classic battles also follow Up, which may differ from the world zoom.
local function presentationScale(arena)
  if arena then
    local ok, Renderer = pcall(require, "src.render.Renderer")
    if ok and Renderer and type(Renderer.frameRects) == "function" then
      local okRects, rects = pcall(Renderer.frameRects, Renderer)
      local scale = okRects and type(rects) == "table" and tonumber(rects.Up)
      if scale and scale > 0 then return scale end
    end
  end
  return fitScale()
end

local function windowCamera(camera, ph, scale)
  if not camera then return nil end
  local out = {}
  for key, value in pairs(camera) do out[key] = value end
  local span = GB_H * math.max(0.01, scale or 1)
  if type(out.fov) == "number" and span > 0 then
    out.fov = 2 * math.atan(math.tan(out.fov / 2) * ph / span)
  end
  return out
end

local function captureGraphics()
  local g = love.graphics
  local sx, sy, sw, sh
  if g.getScissor then sx, sy, sw, sh = g.getScissor() end
  local blend, alpha = g.getBlendMode()
  local depth, write = g.getDepthMode()
  return {
    canvas = g.getCanvas(), shader = g.getShader(),
    blend = blend, alpha = alpha, depth = depth, write = write,
    color = { g.getColor() }, scissor = sx and { sx, sy, sw, sh } or false,
  }
end

local function restoreGraphics(saved)
  local g = love.graphics
  g.setCanvas(saved.canvas)
  g.setShader(saved.shader)
  if saved.depth then g.setDepthMode(saved.depth, saved.write)
  else g.setDepthMode() end
  g.setBlendMode(saved.blend or "alpha", saved.alpha)
  g.setColor(unpack(saved.color))
  if saved.scissor then g.setScissor(unpack(saved.scissor))
  else g.setScissor() end
end

local function paletteFor(state, home)
  return function(map)
    return PaletteFX.pal(require("src.core.Game").data,
      state:paletteNameFor(map or home))
  end
end

local function prefetch(state, host)
  if host == state.map then return VoxelScene.prefetch(state) end
  local live = { [host.id] = true, [state.map.id] = true }
  for _, nb in ipairs(state.neighbors or {}) do live[nb.map.id] = true end
  ChunkMesher.setLive(live)
  TerrainAtlas.setLive(live)
  ChunkMesher.request(host, false, nil, true)
  local terrain, water = ChunkMesher.pair(host, false)
  if not terrain then terrain, water = ChunkMesher.pair(host, true) end
  return terrain, {}, water, {}
end


function Scene.ready(state, arena)
  if not (state and state.map and arena) or not Voxel3D.available() then return false end
  local terrain = prefetch(state, arena.map or state.map)
  return terrain ~= nil
end

local function groundAt(host, arena)
  local cell = arena and arena.playerCell
  if not cell then return 0 end
  local ok, height = pcall(VoxelScene.groundAt, host, cell[1], cell[2])
  return ok and height or 0
end

local function frameHeight(camera, fallback)
  if not (camera and type(camera.eye) == "table"
      and type(camera.focus) == "table" and type(camera.fov) == "number") then
    return fallback
  end
  local dx = camera.eye[1] - camera.focus[1]
  local dy = camera.eye[2] - camera.focus[2]
  local dz = camera.eye[3] - camera.focus[3]
  local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
  if distance < 1e-6 then return fallback end
  return 2 * distance * math.tan(camera.fov / 2)
end

-- Structure analyses already live with each drawable map. Cache one small
-- nearest-filtered mask alongside their lifetime, rather than scan/upload
-- geometry during every camera frame. The classification is the object's
-- total height, never the current fragment's height (no leftover stumps).
local lowObjectMasks = setmetatable({}, {__mode="k"})
local function lowObjects(map)
  local ok, Structures = pcall(V.require, "Structures")
  if not ok then return nil end
  local got, structure = pcall(Structures.forMap, map)
  if not got or not structure then return nil end
  if lowObjectMasks[structure] ~= nil then return lowObjectMasks[structure] or nil end
  local cells, x0, z0, x1, z1 = {}, math.huge, math.huge, -math.huge, -math.huge
  for key, shape in pairs(structure.shapeAt or {}) do
    local run = structure.runs and structure.runs[key]
    local height = run and ((run.h or 0)+(run.rise or 0)) or (shape.h or 0)
    if not shape.flat and height > 0 and height <= 12 then
      local x,z = key % 4096 - 64, math.floor(key / 4096) - 64
      cells[#cells+1]={x,z}
      x0,z0,x1,z1=math.min(x0,x),math.min(z0,z),math.max(x1,x),math.max(z1,z)
    end
  end
  if #cells == 0 then lowObjectMasks[structure]=false;return nil end
  local width,height=x1-x0+1,z1-z0+1
  local data=love.image.newImageData(width,height)
  for _,cell in ipairs(cells)do data:setPixel(cell[1]-x0,cell[2]-z0,1,1,1,1)end
  local texture=love.graphics.newImage(data);data:release()
  texture:setFilter("nearest","nearest")
  local mask={texture=texture,grid={x0*8,z0*8,width*8,height*8}}
  lowObjectMasks[structure]=mask
  return mask
end

function Scene.render(state, arena, drawActors, hostCamera)
  if not (state and state.map and arena and type(drawActors) == "function") then
    return nil
  end
  if not Voxel3D.available() then return nil end

  local host = arena.map or state.map
  local neighbors = host == state.map and (state.neighbors or {}) or {}
  local terrain, nbMesh, water, nbWater = prefetch(state, host)
  if not terrain then return nil end

  local colors = paletteFor(state, host)
  local function atlasFor(map)
    return TerrainAtlas.forMap(map, VoxelScene._modeColors(colors, map))
  end

  local outdoor = host.def and Map.isOutdoor(host.def) or false
  DayNight.applyRig(outdoor)
  Voxel3D.tint = DayNight.tint(outdoor or DayNight.isCanopy(host))
  local GlassMask = V.require("GlassMask")
  Voxel3D.glassMask = outdoor and GlassMask.texture(host.tileset) or nil
  Voxel3D.glassNight = outdoor and DayNight.windowLight() or 0
  Voxel3D.glassGlint = 0

  local groundY = groundAt(host, arena)
  local pw, ph = pixelSize()
  if arena.encounter then
    arena.jpMetrics=require('src.battle.BattlePresentation').metrics(require('src.render.Renderer'):frameRects())
    arena.jpCompact=arena.jpMetrics.compact
  end
  local camera = hostCamera and hostCamera.pose
  local pitch = hostCamera and hostCamera.pitch
  -- Prepared encounters use the same canonical card shot before card.begin
  -- locks steering; otherwise its default 1.3x lens would snap at handoff.
  if not camera then camera, pitch = BattleCam.rig(arena, groundY, arena.entryDuration ~= nil) end
  camera = windowCamera(camera, ph, presentationScale(arena))
  -- Fit shadows to the settled shot, not every intermediate focus/orbit
  -- pose. Intro camera motion must not cause a new shadow texture per frame.
  local shadowVH = frameHeight(camera, BattleCam.frameH(arena))
  if arena.encounter then
    local Renderer=require('src.render.Renderer')
    camera.curveX,camera.curveZ=arena.mid[1],arena.mid[2]
    camera.filmX,camera.filmY=require('src.battle.BattlePresentation').filmOffset(Renderer:frameRects())
    camera=V.require('BattleIntroFocus').pose(arena,camera,groundY,Renderer:frameRects())
    if arena.entryPose then
      local blend=V.require('BattleCameraBlend')
      local present=arena.entryDuration and blend.encounter or blend.mix
      camera=present(arena.entryPose,camera,
        math.min(1,(arena.presentationTime or 0)/(arena.entryDuration or .55)))
    end
    arena.groundY=groundY
    camera=V.require('BattleActionCamera').pose(arena,camera,Renderer:frameRects())
    arena.lastPose=V.require('BattleCameraBlend').copy(camera)
  end
  local cx, cy = arena.mid[1], arena.mid[2]
  local vh = frameHeight(camera, BattleCam.frameH(arena))
  local vw = vh * pw / ph
  local sky = VoxelScene.skyColor(host, 1)
    or VoxelScene.skyShade(INDOOR_SHADE, 1)
  local rw, rh = AntiAlias.expand(pw, ph)

  -- Voxel3D and AntiAlias historically rendered as the top-level overworld
  -- pass and therefore ended with setCanvas(). Under API 1 this function is
  -- nested inside StadiumBattleFX's battle surface; preserve the complete
  -- caller state so the resolved arena, actors, HUD, and text all land back
  -- on that surface instead of the window or a stale intermediate canvas.
  local graphics = captureGraphics()
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setScissor()
  love.graphics.setStencilTest()
  Voxel3D.camera = camera
  local ok, result = pcall(function()
    VoxelScene.castBattleShadows(host, neighbors, terrain, nbMesh,
      cx, cy, shadowVH * pw / ph, shadowVH, atlasFor, water, nbWater)
    if not Voxel3D.beginScene(rw, rh, cx, cy, vw, vh, sky, "battle") then
      return nil
    end
    local clearings = {}
    V.require('SceneEffects').bind(arena.jpSceneEffects)
    local Cards=V.require('VoxelBattleCardProvider')
    -- jp.58: the pre-battle rehearsal (VoxelBattleWarmup) supplies its own
    -- transparent cards so the same card samplers are bound as in battle.
    local sightlines=arena.jpWarmupCards and arena.jpWarmupCards(groundY,rw,rh)
      or (arena.encounter and Cards.terrainCards and Cards:terrainCards(arena,groundY,rw,rh))
    Voxel3D.battleCards(sightlines)
    if arena.encounter and arena.player and arena.enemy then
      for i, side in ipairs({ 'player', 'enemy' }) do
        local point, cell = arena[side], arena[side..'Cell']
        local x, z = point[1], point[2]
        local cellX, cellY = cell and cell[1] or math.floor(x/16),
                            cell and cell[2] or math.floor(z/16)
        local floor = groundY
        if not arena.backgroundOnly then
          local got, height = pcall(VoxelScene.groundAt, host, cellX, cellY)
          floor = got and type(height)=='number' and height or groundY
        end
        -- Clear only raised obstacles immediately around the actual lens,
        -- even before a picture exists or while a trainer enters offscreen.
        -- Feet provide floor protection, never the cut depth: keep trees and
        -- buildings beyond the camera's short clearance in the real field.
        -- Background-only fallback uses these points only for its camera;
        -- protect the real origin floor instead of a blocked virtual foot.
        clearings[i] = {x=x,z=z,floor=floor}
      end
      Voxel3D.battleOcclusion(clearings, true)
    end
    Voxel3D.battleLowObjects(arena.encounter and lowObjects(host) or nil)
    Voxel3D.draw(terrain, atlasFor(host), nil)
    -- jp.62: a neighbour is only drawn once its own terrain exists. Asking for
    -- its low-object mask and atlas before that ran its whole shape analysis
    -- and atlas bake synchronously -- ~2 s for Route 1's neighbours with LuaJIT's
    -- compiler off (arm64 Android): the first battle's (and the warm-up's) stall.
    for i, nb in ipairs(neighbors) do
      if nbMesh[i] then
        Voxel3D.battleLowObjects(arena.encounter and lowObjects(nb.map) or nil)
        Voxel3D.draw(nbMesh[i], atlasFor(nb.map), Mat4.translate(nb.ox, 0, nb.oy))
      end
    end
    Voxel3D.battleLowObjects()
    Voxel3D.battleDecoration(true)
    if water then Voxel3D.draw(water, atlasFor(host)) end
    for i, nb in ipairs(neighbors) do
      if nbMesh[i] and nbWater and nbWater[i] then
        Voxel3D.draw(nbWater[i], atlasFor(nb.map), Mat4.translate(nb.ox, 0, nb.oy))
      end
    end

    local pull = VoxelScene.pull(math.max(pitch or 0, 0.05))
    -- A small footprint presses the blades beneath grounded visible feet.
    -- The independent alpha sight line keeps even a small foe readable.
    local footA,footB=V.require('SceneEffects').battleFeet(arena,sightlines)
    Voxel3D.grassClearance(footA,footB)
    Voxel3D.battleDecoration(true)
    Voxel3D.foliage(true,true)
    Voxel3D.draw(ChunkMesher.grass(host), atlasFor(host), nil, pull)
    for i, nb in ipairs(neighbors) do
      local grass = nbMesh[i] and ChunkMesher.grass(nb.map)
      if grass then Voxel3D.draw(grass, atlasFor(nb.map), Mat4.translate(nb.ox, 0, nb.oy), pull) end
    end
    Voxel3D.grassClearance()
    Voxel3D.battleDecoration(true)
    Voxel3D.foliage(true)
    local fpull = math.max(0, pull - 8 * math.sin(math.max(pitch or 0, 0.05)))
    Voxel3D.draw(ChunkMesher.flowers(host), atlasFor(host), nil, fpull)
    for i, nb in ipairs(neighbors) do
      local flowers = nbMesh[i] and ChunkMesher.flowers(nb.map)
      if flowers then Voxel3D.draw(flowers, atlasFor(nb.map), Mat4.translate(nb.ox, 0, nb.oy), fpull) end
    end
    Voxel3D.foliage(false)
    Voxel3D.battleDecoration(false)
    Voxel3D.battleLowObjects()
    Voxel3D.battleOcclusion()
    Voxel3D.battleCards()

    -- Background only: Pokémon cards, names, HP and commands arrive later.
    -- Depth protects nearby objects even when they reach the top of frame.
    local eye,focus=Voxel3D.eye,Voxel3D.focus
    local dx,dy,dz=eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]
    local amount=1
    if arena.entryDuration then
      amount=math.max(0,math.min(1,(arena.presentationTime or 0)/arena.entryDuration))
      amount=amount*amount*(3-2*amount)
    end
    TiltShift.battleBackground(Voxel3D.canvas(),Voxel3D.depthTexture(),{
      near=Voxel3D.nearPlane,far=Voxel3D.farPlane,
      focus=math.sqrt(dx*dx+dy*dy+dz*dz),amount=amount,
    })
    V.require('SceneGlow').apply(Voxel3D.canvas(),amount)
    Voxel3D.endWater()

    -- Actor rendering may bind its own shader. It is intentionally the last
    -- draw in this depth pass so Dramaless never has to restore host internals.
    drawActors({
      vp = Voxel3D.vp,
      groundY = groundY,
      width = rw,
      height = rh,
    })

    V.require('SceneEffects').draw(arena.jpSceneEffects)
    return AntiAlias.resolve(Voxel3D.endScene(), pw, ph, "battle")
  end)
  -- A failed grass draw must not carry its local deformation into another
  -- pass. beginScene also resets the uniforms when the next frame starts.
  Voxel3D.grassClearance()
  Voxel3D.foliage(false)
  Voxel3D.effects()
  Voxel3D.battleLowObjects()
  Voxel3D.battleOcclusion()
  Voxel3D.battleCards()
  Voxel3D.camera = nil
  love.graphics.pop()
  restoreGraphics(graphics)
  if not ok then
    V.require('BattleActionCamera').finish(arena)
    error(result, 0)
  end
  return result
end

return Scene
