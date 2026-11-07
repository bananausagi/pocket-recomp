-- The Japanese player's 3D card belongs at the chosen screen position.
-- The original camera follows (px+16, py+8), placing a 16px card to the
-- upper left. Adjust only the render call; collision, scripted pans and the
-- original 2D camera never acquire the presentation-only correction.
local Framing = {}
local cachedLibrary, cachedModules

local function finite(value)
  return type(value)=="number" and value==value
    and value>-math.huge and value<math.huge
end

-- A leaned billboard's centre is (px+8, ground+halfHeight*sin(a),
-- py+8-halfHeight*cos(a)). Intersect its line toward the orbit eye with
-- the ground to find the camera focus. WorldCurve lowers that point by
-- k*distance^2, so solve u + k*tan(a)*u^2 = centreHeight*tan(a).
function Framing.offset(angle, halfHeight, ground, curve)
  if not (finite(angle) and finite(halfHeight) and finite(ground)) then return end
  local cosine, sine = math.cos(angle), math.sin(angle)
  if cosine < 0.1 or angle < 0 or halfHeight <= 0 then return end
  local tangent = sine / cosine
  local height = ground + halfHeight * sine
  local k = finite(curve) and math.max(0,curve) or 0
  local discriminant = 1 + 4*k*height*tangent*tangent
  if discriminant < 0 then return end
  local distance = 2*height*tangent / (1+math.sqrt(discriminant))
  return -8, -halfHeight*cosine-distance
end

local function modules(library)
  if library==cachedLibrary then return cachedModules end
  cachedLibrary, cachedModules = library,nil
  if not (type(library)=="table" and type(library.require)=="function") then return end
  local ok, value = pcall(function()
    return {voxel=library.require("VoxelState"),scene=library.require("VoxelScene"),
      firstPerson=library.require("FirstPerson"),curve=library.require("WorldCurve")}
  end)
  if ok then cachedModules=value end
  return cachedModules
end

function Framing.begin(id, owner, ctx)
  if id~="voxel" or (owner~="DRAMALESS_SHAPE" and owner~="VOXEL_ASCENDANT")
      or require("src.core.GameVersion").get()~="red_jp" then return end
  local state=ctx and ctx.state
  local camera=state and state.camera
  local player=state and state.player
  if not (camera and player and finite(camera.x) and finite(camera.y)) then return end
  local Game=require("src.core.Game")
  local export=Game.mods and Game.mods.exports and Game.mods.exports[owner]
  local m=modules(export and export.lib)
  if not (m and m.voxel and m.scene and m.firstPerson) then return end
  -- A completed placed rig owns its focus. During the transition, its
  -- orbit endpoint must retain the same correction as the previous frame;
  -- FirstPerson.frame blends that endpoint toward the untouched head rig.
  if (m.firstPerson.blend or 0)>=1 then return end
  local sprite=player.sprite
  local height=sprite and sprite.def and sprite.def.frameHeight or 16
  local ground=0
  if m.scene.groundAt and state.map and player.cellX and player.cellY then
    local ok,value=pcall(m.scene.groundAt,state.map,player.cellX,player.cellY)
    if ok and finite(value) then ground=value end
  end
  local curve=m.curve and m.curve.k and m.curve.k(ctx.vh) or 0
  local dx,dy=Framing.offset(m.voxel.angle,height/2,ground,curve)
  if not dx then return end
  local copy={}
  for key,value in pairs(camera) do copy[key]=value end
  setmetatable(copy,getmetatable(camera))
  copy.x,copy.y=camera.x+dx,camera.y+dy
  local token={state=state,camera=camera,ctx=ctx,ctxCamera=ctx.cam}
  state.camera,ctx.cam=copy,copy
  return token
end

function Framing.finish(token)
  if not token then return end
  token.state.camera=token.camera
  token.ctx.cam=token.ctxCamera
end

return Framing
