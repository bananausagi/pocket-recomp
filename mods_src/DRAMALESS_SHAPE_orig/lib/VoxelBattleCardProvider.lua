-- Native Gen 1 battle pictures presented as camera-facing cards.
--
-- This is the intentionally narrow 2D exception to Dramaless 2.0's
-- environment boundary. It captures only the engine's side-only pics layer
-- and draws it at the selected arena cells. It owns no battle camera, HUD,
-- transition, move animation, portable stage, or lifecycle policy.

local V = ...

local Provider = { id = "DRAMALESS_SHAPE:voxel-cards" }
local GB_W, GB_H = 160, 144
local WORLD_PER_PIC_PIXEL = 16 / 56
local WORLD_CARD_HEIGHT = GB_H * WORLD_PER_PIC_PIXEL
local TEX_AX, TEX_AY = 80, 96

-- Anchors of the engine's native slots. The enemy's 7x7 front/trainer slot
-- is centred at x=124 with its baseline at y=56. The player's scaled back
-- slot is centred at x=64 with its feet at y=96.
local ANCHOR = {
  enemy = { x = 124, y = 56 },
  player = { x = 64, y = 96 },
}

local canvases = {}
local textures = {}
local visible = { player = false, enemy = false }
local drawn = { player = false, enemy = false }
local active = false
local preparedContext
local placements={}
local placementContext
local installedPicImage, innerPicImage
local Motion = V.require("WildEncounterMotion")
local Intro = V.require("BattleIntroFocus")

local function wildEntry(context)
  return context and context.battle and context.battle.kind == "wild"
    and context.arena and context.arena.entryDuration ~= nil
end

-- The engine's intro and trainer exits span most of the 160-pixel screen.
-- Capturing those translations in a card texture slices the picture at its
-- texture edge. Capture a whole, stationary card instead, then preserve the
-- original movement on the billboard. Only wild entries add a retreat fade.
local function withoutTrainerOffset(context, side, fn)
  local battle = context and context.battle
  if not (battle and (battle.kind == "trainer" or battle.kind == "link"
      or wildEntry(context))) then return fn() end
  local slot = side == "player" and battle and battle.showPlayerBack and "back"
    or side == "enemy" and battle and battle.showEnemyTrainer and "foe"
  if not (slot and type(battle.picOffset) == "function") then return fn() end
  local own, original = rawget(battle, "picOffset"), battle.picOffset
  battle.picOffset = function(self, requested)
    if requested == slot then return 0 end
    return original(self, requested)
  end
  local results = { pcall(fn) }
  battle.picOffset = own
  if not results[1] then error(results[2], 0) end
  table.remove(results, 1)
  return unpack(results)
end

local function nativeSlide(context, side, card, pixelScale, screenX, screenWidth)
  local battle = context and context.battle
  if not (battle and (battle.kind == "trainer" or battle.kind == "link")) then return 0 end
  local Timing = require('src.core.Timing')
  local remaining = Intro.nativeSlide(context.arena) and 0
    or math.max(0, tonumber(battle.introSlide) or 0)
  local distance = Timing.BATTLE_SLIDE_IN_FRAMES * Timing.BATTLE_SLIDE_PX_PER_FRAME
  local exitDistance = side == "enemy" and 64 or 72
  local departure = card.trainer and type(battle.picOffset) == "function"
    and battle:picOffset(side == "enemy" and "foe" or "back") or 0
  local nativeExit = exitDistance
  if pixelScale and pixelScale > 0 and screenX and screenWidth then
    -- The original 160px slide starts/finishes beyond the LCD edge. A wide
    -- 3D playfield needs a longer path, but keeps exactly the same native
    -- frame progression. Otherwise the foe is already visible at frame 0
    -- and either trainer still pops away halfway across a landscape screen.
    local half = (card.picWidth or 56) * pixelScale / 2 + 2
    local left, right = screenX + half, screenWidth - screenX + half
    distance = math.max(distance, (side == "enemy" and left or right) / pixelScale)
    exitDistance = math.max(exitDistance, (side == "enemy" and right or left) / pixelScale)
  end
  local slide = Intro.entranceRemaining(context.arena,remaining,Timing.BATTLE_SLIDE_IN_FRAMES,side)*distance
  return (side == "enemy" and -slide or slide) + departure / nativeExit * exitDistance
end

local function motionFor(context, side, card, start)
  if context and context.arena and context.arena.trainerIntro and card.trainer then
    return 0,1,Intro.trainerAlpha(context.arena,side),0
  end
  if not wildEntry(context) then return 0, 1, 1, 0 end
  local battle, arena = context.battle, context.arena
  if side == "player" and card.trainer then
    local alpha, retreat = Motion.retreat(battle:picOffset("back"))
    return 0, 1, alpha, retreat
  end
  if side ~= "enemy" or card.trainer then return 0, 1, 1, 0 end
  local now = love.timer.getTime()
  -- Start only when the real enemy card is about to be drawn. This is the
  -- very frame the host acknowledges before allowing the original cry.
  -- Real time keeps 4x gameplay from collapsing the leap into two frames.
  if start and not arena.wildRevealAt then arena.wildRevealAt = now end
  local age = arena.wildRevealAt and math.max(0,now-arena.wildRevealAt) or 0
  local lift, scale = Motion.hop(age)
  card.wildHopActive = age < Motion.HOP_SECONDS
  return lift, scale, 1, 0
end

local function backPinned(battle,arena)
  -- Pinned back sprites are a preference for the player's Pokémon. During
  -- an opponent-focus introduction the human trainer must belong to the
  -- world camera too, or the native HUD fallback appears over the close-up.
  if battle and battle.showPlayerBack and arena and (arena.focusIntro or arena.trainerIntro) then return false end
  local setting = V and V.backSpritesSetting
  if not (setting and type(setting.get) == "function") then return false end
  local ok, value = pcall(setting.get, setting)
  return ok and value and true or false
end

local function voxelArena(context)
  local id = context and context.arena and context.arena.id
  return type(id) == "string" and id:match("^dramaless:voxel%-map:") ~= nil
end

local function syncCamera(context, recenter)
  if not voxelArena(context) then return end
  local ok, camera = pcall(V.require, "BattleCam")
  if not (ok and camera) then return end

  -- Native Gen 1 move animations and Poke Ball throws remain screen-space
  -- effects at the engine's fixed battle anchors. The voxel cards only line
  -- up with those effects when BattleCam uses the canonical solved shot.
  -- Lock out drift/zoom/steering while these 2D cards are active instead of
  -- letting the camera move the cards away from the effects that target them.
  camera.steerable = false
  camera.still = true
  if recenter and type(camera.recentre) == "function" then camera.recentre() end
end

local function canvasFor(side)
  local canvas = canvases[side]
  if canvas then return canvas end
  local ok, made = pcall(love.graphics.newCanvas, GB_W, GB_H, { dpiscale = 1 })
  if not (ok and made) then return nil end
  made:setFilter("nearest", "nearest")
  canvases[side] = made
  return made
end

local function fxHidden(battle, battler)
  if not (battle and battler and type(battle.fxHidden) == "function") then
    return false
  end
  local ok, hidden = pcall(battle.fxHidden, battle, battler)
  return ok and hidden and true or false
end

local function sideVisible(battle, side)
  if not battle or battle.fieldCleared then return false end
  local battler = side == "enemy" and battle.enemy or battle.player
  local trainer = side == "enemy" and battle.showEnemyTrainer and battle.trainerPic
    or side == "player" and battle.showPlayerBack and battle.playerBackPic
  if not trainer and battler then
    local scale = type(battle.growInScale) == "function" and battle:growInScale(battler)
    if not scale and side == "player" and type(battle.shrinkOutScale) == "function" then
      scale = battle:shrinkOutScale(battler)
    end
    local ball = side == 'enemy' and battle.growIn
      and battle.growIn.battler == battler and battle.growIn.presentation
    if scale == 0 and not ball then return false end
    -- A hidden native picture must not leave a free-standing contact shadow
    -- or a foreground cutout. A faint slide and a substitute/minimized blob
    -- are still visible artwork and continue through the native capture.
    local faint = type(battle.fxFaintActive) == "function" and battle:fxFaintActive(battler)
    if battler.fainted and not faint then return false end
    local pf = battle.picFx and battle.picFx[battler]
    local substitute = battler.substituteHP and not battler.substitutePending and not battler.fainted
    if not faint and not substitute and pf and type(pf.fade) == "number" and pf.fade <= 0 then
      return false
    end
    if not faint and not substitute and pf and not pf.fade then
      if pf.hidden then return false end
      if not pf.minimized and pf.kind == "blink" and math.floor((pf.t or 0) / 5) % 2 == 0 then
        return false
      end
    end
  end
  if side == "enemy" then
    if battle.showEnemyTrainer and battle.trainerPic then return true end
    return battle.enemy and battle.enemy.sprite
      and not battle.enemyHidden and not battle.enemySendingOut
      and not fxHidden(battle, battle.enemy) and true or false
  end
  if battle.showPlayerBack and battle.playerBackPic then return true end
  return battle.player and battle.player.sprite
    and not battle.safari and not battle.demo and not battle.sendingOut
    and not fxHidden(battle, battle.player) and true or false
end

-- Original Dramaless rendered both world cards at 1:1 into a known texture
-- anchor. The billboard's world transform performed the only scaling. Keep
-- these overrides scoped to the synchronous native-pics callback.
local function withOriginalPlacement(battle, fn)
  local okState, BattleState = pcall(require, "src.battle.BattleState")
  if not (okState and BattleState) then return fn() end
  local scale, back, front = BattleState.resolveBattleScale,
    BattleState.backPlacement, BattleState.frontPlacement
  if type(scale) ~= "function" or type(back) ~= "function"
      or type(front) ~= "function" then return fn() end

  BattleState.resolveBattleScale = function() return 1 end
  BattleState.backPlacement = function(w, h, pad, padL, spriteScale)
    local _, _, state = back(w, h, pad, padL, spriteScale)
    spriteScale = tonumber(spriteScale) or 1
    return TEX_AX - w * spriteScale / 2,
      TEX_AY - (h - (pad or 0)) * spriteScale, state
  end
  BattleState.frontPlacement = function(ex, ey, w, h, spriteScale)
    local _, _, state = front(ex, ey, w, h, spriteScale)
    spriteScale = tonumber(spriteScale) or 1
    return TEX_AX - w * spriteScale / 2,
      TEX_AY - h * spriteScale, state
  end
  -- The native effect scissors describe the original LCD slots. The card
  -- above has moved the picture to TEX_AX/TEX_AY; applying those scissors
  -- here slices visible blink/shake frames into a corner of the sprite.
  -- As with the native wide layout, this canvas owns its clipping instead.
  local wideRegion = battle.wideRegion
  battle.wideRegion = true
  local results = { pcall(fn) }
  battle.wideRegion = wideRegion
  BattleState.resolveBattleScale, BattleState.backPlacement,
    BattleState.frontPlacement = scale, back, front
  if not results[1] then error(results[2], 0) end
  table.remove(results, 1)
  return unpack(results)
end

local function withNativePics(context, fn)
  local service = context and context.services
    and context.services.withNativeBattlePics
  if type(service) == "function" then return service(fn) end
  local ok, result = pcall(fn)
  return ok, result
end

local function battlerForSide(battle, side)
  if not battle then return nil end
  return side == "player" and battle.player or battle.enemy
end

-- Splash's SE_BOUNCE_UP_AND_DOWN is implemented by the engine as repeated
-- tilemap Y displacement on the user's native battle picture. Baking that
-- displacement into a 160x144 capture makes the card clip/wrap inside its
-- texture before the texture is mounted in 3D. Keep the captured card stable
-- and promote only this displacement to the billboard's world transform.
local function bounceWorldOffset(battle, side)
  local battler = battlerForSide(battle, side)
  local pf = battler and battle.picFx and battle.picFx[battler]
  if not (pf and pf.kind == "bounce") then return 0 end
  local t = tonumber(pf.t) or 0
  -- The native effect slides the 2D tilemap downward and resets it five
  -- times. In world space that would push the billboard through the floor.
  -- Preserve the stepped timing as a small above-ground hop instead:
  --   0, 8, 16, 24, 16, 8, 0 pixels over each 21-frame pass.
  local phase = math.floor((t % 21) / 3)
  local step = phase <= 3 and phase or (6 - phase)
  return step * 8 * WORLD_PER_PIC_PIXEL
end

local function withoutCapturedBounce(battle, side, fn)
  local battler = battlerForSide(battle, side)
  local pf = battler and battle.picFx and battle.picFx[battler]
  if not (pf and pf.kind == "bounce") then return fn() end

  local kind, t = pf.kind, pf.t
  pf.kind = nil
  local results = { pcall(fn) }
  pf.kind, pf.t = kind, t
  if not results[1] then error(results[2], 0) end
  table.remove(results, 1)
  return unpack(results)
end

local function captureSide(context, side)
  local battle = context and context.battle
  if side == "player" and backPinned(battle,context and context.arena) then
    visible[side] = false
    textures[side] = nil
    return true
  end
  visible[side] = sideVisible(battle, side)
  if not visible[side] then
    textures[side] = nil
    return true
  end
  if not (battle and type(battle.drawPicsLayer) == "function") then
    textures[side] = nil
    return false
  end
  local canvas = canvasFor(side)
  if not canvas then
    textures[side] = nil
    return false
  end

  local g = love.graphics
  g.push("all")
  local called, ok, err = pcall(withNativePics, context, function()
    g.setCanvas(canvas)
    g.origin()
    g.setScissor()
    g.setStencilTest()
    g.setDepthMode("always", false)
    g.clear(0, 0, 0, 0)
    if g.setShader then g.setShader() end
    g.setBlendMode("alpha")
    g.setColor(1, 1, 1, 1)
    if g.setScissor then g.setScissor() end
    withOriginalPlacement(battle, function()
      withoutCapturedBounce(battle, side, function()
        withoutTrainerOffset(context, side, function()
          battle:drawPicsLayer(0, 0, 0, side, true)
        end)
      end)
    end)
  end)

  g.pop()
  if not called then err, ok = ok, false end
  if not ok then
    textures[side] = nil
    local log = context and context.services and context.services.log
    if log and log.warn then
      log:warn("[DRAMALESS_SHAPE] native card capture failed: side=%s error=%s",
        tostring(side), tostring(err))
    end
    return false
  end
  local ax, ay, trainer = TEX_AX, TEX_AY, false
  if side == "enemy" and battle.showEnemyTrainer and battle.trainerPic then
    ax, ay, trainer = ANCHOR.enemy.x, ANCHOR.enemy.y, true
  elseif side == "player" and battle.showPlayerBack and battle.playerBackPic then
    trainer = true
  end
  textures[side] = {
    canvas = canvas, ax = ax, ay = ay, trainer = trainer,
    worldYOffset = bounceWorldOffset(battle, side),
  }
  local b=battlerForSide(battle,side)
  local path=trainer and (side=='enemy' and battle.trainerPic or battle.playerBackPic)
    or b and b.sprite
  local img=path and battle:picImage(path)
  textures[side].picWidth=img and img:getWidth() or 56
  textures[side].picHeight=img and img:getHeight() or 56
  motionFor(context,side,textures[side],false)
  return true
end

local function capture(context)
  captureSide(context, "enemy")
  captureSide(context, "player")
end

local function cellFor(context, side)
  local arena = context and context.arena
  if arena and arena.backgroundOnly then return nil end
  return arena and arena[side] or nil
end

local function distanceScale(context)
  local arena=context and context.arena
  if not (arena and arena.encounter and arena.player and arena.enemy) then return 1 end
  local dx,dz=arena.player[1]-arena.enemy[1],arena.player[2]-arena.enemy[2]
  return math.sqrt(dx*dx+dz*dz)/48
end

local function drawSide(context, side)
  local card = textures[side]
  local cell = cellFor(context, side)
  local project = context and context.services and context.services.project
  if not (card and card.canvas and cell and type(project) == "function") then
    return false
  end

  local ground = (tonumber(context.groundY) or 0) + (card.worldYOffset or 0)*distanceScale(context)
  local fx, fy = project(cell[1], ground, cell[2])
  local tx, ty = project(cell[1], ground + WORLD_CARD_HEIGHT*distanceScale(context), cell[2])
  if not (fx and fy and tx and ty) then return false end
  local scale = math.abs(fy - ty) / GB_H
  if not (scale > 0 and scale < 64) then return false end
  local lift, emergence, alpha, retreat=motionFor(context,side,card,true)
  local size=context.services and context.services.renderSize
  retreat=retreat+nativeSlide(context,side,card,scale,fx,size and size.width)
  fx,fy=fx+retreat*scale,fy-lift*scale
  scale=scale*emergence
  local r,g,b,a=love.graphics.getColor()
  love.graphics.setColor(r,g,b,a*alpha)
  love.graphics.draw(card.canvas,
    fx - card.ax * scale,
    fy - card.ay * scale,
    0, scale, scale)
  love.graphics.setColor(r,g,b,a)
  return true
end

local function voxelPlacement(context, side)
  local card, cell = textures[side], cellFor(context, side)
  if not (card and card.canvas and cell) then return false end
  local Billboard = V.require("BattleBillboard")
  local Voxel3D = V.require("Voxel3D")
  local mesh = Billboard.mesh()
  if not mesh then return false end
  local lift, emergence, alpha, retreat=motionFor(context,side,card,true)
  local presentation
  local metrics=context.arena and context.arena.jpMetrics
  if context.arena and context.arena.encounter and metrics then
    local r=require('src.render.Renderer'):frameRects()
    local nativeScale=require('src.battle.BattlePresentation').pictureScale(metrics,side,card.picWidth,card.picHeight)
    local ground=tonumber(context.groundY) or 0
    local canonical=context.arena.cardCanonical or context.arena.focusCanonical
      or {eye=Voxel3D.eye,focus=Voxel3D.focus,fov=Voxel3D.fovY}
    local worldPerPixel=Intro.cardWorldPixel(context.arena,canonical,side,ground,nativeScale,r,card.trainer)
    presentation={faceCamera=true,worldPerPixel=worldPerPixel*emergence}
    card.worldPerPixel=worldPerPixel
  end
  local ground=(tonumber(context.groundY) or 0)+(card.worldYOffset or 0)*distanceScale(context)
  local worldPixel=card.worldPerPixel or WORLD_PER_PIC_PIXEL*distanceScale(context)
  local function placed(hop)
    return Billboard.matrix(card.canvas,card.ax,card.ay,
      cell[1],ground+hop*worldPixel,cell[2],side=="player" and not card.trainer,
      distanceScale(context),presentation)
  end
  local model=placed(lift)
  local nativeModel={unpack(model)}
  local fxX,fxY,fxZ,fxSX,fxSY=V.require('SceneEffects').pose(
    context.arena,context.battle,side,card.trainer)
  -- Pivot at the native feet. HUD and native move anchors stay in place;
  -- the small reaction is measured in sprite pixels, not viewport size.
  local ax,ay=card.ax/GB_W-.5,(GB_H-card.ay)/GB_H
  for row=0,2 do
    local i=row*4+1
    model[i+3]=model[i+3]+model[i]*(1-fxSX)*ax+model[i+1]*(1-fxSY)*ay
    model[i],model[i+1]=model[i]*fxSX,model[i+1]*fxSY
  end
  model[4],model[8],model[12]=model[4]+fxX*worldPixel,
    model[8]+fxY*worldPixel,model[12]+fxZ*worldPixel
  if metrics and (fxX~=0 or fxY~=0 or fxZ~=0 or fxSX~=1 or fxSY~=1) then
    local rect=require('src.render.Renderer'):frameRects()
    local size=context.services and context.services.renderSize
    local width=size and size.width or rect.pw
    local ratio=width/rect.pw
    local bottom=(metrics.y+metrics.command.y*metrics.sy-rect.vuy)*rect.dpiY*ratio
    local left,right=ax-card.picWidth/(2*GB_W),ax+card.picWidth/(2*GB_W)
    local top=ay+card.picHeight/GB_H
    local function fits(m)
      for _,x in ipairs({left,right})do for _,y in ipairs({ay,top})do
        local px,py=Voxel3D.project(m[1]*x+m[2]*y+m[4],m[5]*x+m[6]*y+m[8],m[9]*x+m[10]*y+m[12])
        if not px or px<0 or px>width or py<0 or py>bottom then return false end
      end end
      return true
    end
    if not fits(model) then
      local goal=model;model={unpack(nativeModel)}
      if fits(nativeModel) then
        local lo,hi=0,1
        for _=1,10 do
          local mid=(lo+hi)/2;local candidate={}
          for i=1,16 do candidate[i]=nativeModel[i]+(goal[i]-nativeModel[i])*mid end
          if fits(candidate) then lo,model=mid,candidate else hi=mid end
        end
      end
    end
  end
  if lift>0 and side=="enemy" then
    -- Portrait layouts can fit a tall mon with only a few pixels above its
    -- head. Limit the leap using this actual projection, not a fixed screen
    -- size, so emergence never clips a sprite that fits at its native pose.
    local top=(GB_H-card.ay+card.picHeight)/GB_H
    local function fits(m)
      local _,y=Voxel3D.project(m[2]*top+m[4],m[6]*top+m[8],m[10]*top+m[12])
      return y and y>=2
    end
    if not fits(model) then
      local lo,hi=0,lift
      model=placed(0)
      for _=1,8 do
        local mid=(lo+hi)/2
        local candidate=placed(mid)
        if fits(candidate) then lo,model=mid,candidate else hi=mid end
      end
    end
  end
  if nativeSlide(context,side,card) ~= 0 then
    local view=V.require('Mat4').lookAt(Voxel3D.eye,Voxel3D.focus,{0,1,0})
    local px=Voxel3D.project(cell[1],ground,cell[2])
    local qx=Voxel3D.project(cell[1]+view[1]*worldPixel,
      ground+view[2]*worldPixel,cell[2]+view[3]*worldPixel)
    local size=context.services and context.services.renderSize
    retreat=retreat+nativeSlide(context,side,card,
      px and qx and math.abs(qx-px),px,size and size.width)
  end
  if retreat ~= 0 then
    local Mat4=V.require('Mat4')
    local view=Mat4.lookAt(Voxel3D.eye,Voxel3D.focus,{0,1,0})
    local shift=retreat*(card.worldPerPixel or WORLD_PER_PIC_PIXEL*distanceScale(context))
    model[4],model[8],model[12]=model[4]+view[1]*shift,
      model[8]+view[2]*shift,model[12]+view[3]*shift
  end
  return {card=card,model=model,mesh=mesh,lift=lift,alpha=alpha,worldPixel=worldPixel}
end

local function drawVoxelSide(context,side)
  local placement=placementContext==context and placements[side] or voxelPlacement(context,side)
  if not placement then return false end
  local card,model,mesh=placement.card,placement.model,placement.mesh
  local lift,alpha,worldPixel=placement.lift,placement.alpha,placement.worldPixel
  local Voxel3D=V.require('Voxel3D')
  local Billboard=V.require('BattleBillboard')
  -- A soft contact shadow stays on the actual terrain beneath the card.
  -- Derive X/Z from the final model so native trainer retreat follows it;
  -- jumps reduce opacity, while water/unknown ground receives no decal.
  local Atmosphere=V.require('Atmosphere')
  local ax,ay=card.ax/GB_W-.5,(GB_H-card.ay)/GB_H
  local footX=model[1]*ax+model[2]*ay+model[4]
  local footZ=model[9]*ax+model[10]*ay+model[12]
  local grow=context.battle and context.battle.growIn
  local contactScale=grow and grow.presentation and side=='enemy'
    and context.battle:growInScale(context.battle.enemy) or 1
  contactScale=contactScale or 1
  if contactScale>0 and Atmosphere.solidGround(context.arena and context.arena.map,footX,footZ) then
    Atmosphere.drawContact(footX,tonumber(context.groundY) or 0,footZ,
      math.max(3,math.min(20,card.picWidth*worldPixel*.30))*contactScale,
      alpha*contactScale/(1+lift/12))
  end
  Voxel3D.seams(false)
  Voxel3D.glass(false)
  -- Both cards already stand at their world anchors. The close camera puts
  -- the near trainer behind/outside its view; pulling back reveals them
  -- naturally, with no simultaneous fade-in alongside the wild opponent.
  if side=="enemy" then Intro.shown(context.arena) end
  local r,g,b,a=love.graphics.getColor()
  love.graphics.setColor(r,g,b,a*alpha)
  Voxel3D.draw(mesh, card.canvas, model, Billboard.PULL)
  love.graphics.setColor(r,g,b,a)
  Voxel3D.glass(true)
  Voxel3D.seams(true)
  return true
end

-- jp.58: allocate the two capture targets ahead of the first battle and lend
-- them (still transparent) to the offscreen warm-up rehearsal.
function Provider.warmCanvases()
  if active then return nil end
  local player,enemy=canvasFor("player"),canvasFor("enemy")
  return player and enemy and {player,enemy} or nil
end

function Provider:available(context)
  local battle = context and context.battle
  return love and love.graphics and battle
    and type(battle.drawPicsLayer) == "function" and true or false
end

function Provider:install()
  local ok, BattleState = pcall(require, "src.battle.BattleState")
  if not (ok and BattleState and type(BattleState.picImage) == "function") then
    return true
  end
  if BattleState.picImage == installedPicImage then return true end
  innerPicImage = BattleState.picImage
  installedPicImage = function(battle, image)
    local out = innerPicImage(battle, image)
    if not active then return out end
    local player = battle and battle.player
    local pinned = backPinned(battle,Provider.currentArena) and battle and
      (image == battle.playerBackPic or (player and image == player.sprite))
    return V.require("BattlePics").filled(out, pinned)
  end
  BattleState.picImage = installedPicImage
  return true
end

function Provider:begin(context, arena)
  self:install(context)
  context.arena = arena or context.arena
  self.currentArena=context.arena
  self.currentBattle=context.battle
  if self.currentBattle then
    self.currentBattle.jpEnemySendOut3D=voxelArena(context) and Intro.enabled(self.currentBattle)
      and self.currentBattle.kind=='trainer' and not context.arena.backgroundOnly or nil
  end
  active = not (context.arena and context.arena.backgroundOnly)
  textures.player, textures.enemy = nil, nil
  visible.player, visible.enemy = false, false
  drawn.player, drawn.enemy = false, false
  preparedContext = nil
  if not active then return true end
  syncCamera(context, true)
  return true
end

function Provider:update(context)
  if context and context.arena and context.arena.backgroundOnly then return end
  syncCamera(context, false)
end

-- Capture only at the presentation boundary, after this frame's battle
-- logic. input.step runs before BattleState:update; capturing there kept a
-- stale trainer/mon and stale blink state for one tick, while the native
-- fallback was already rendering the new state. At 4x it also captured four
-- times per displayed frame. The arena calls this before its bounds pass.
function Provider:prepareFrame(context)
  if not active or self.currentArena ~= (context and context.arena) then return end
  preparedContext = context
  placementContext=nil;placements={}
  capture(context)
end

-- Called after the final camera is bound, before any scenery is drawn.
-- Reuse the exact model later, including emergence, bounce and hit reactions.
function Provider:terrainCards(arena,ground,width,height)
  local context=preparedContext
  if not (active and context and context.arena==arena and voxelArena(context)) then return nil end
  context.groundY=ground
  if width and height then context.services.renderSize={width=width,height=height} end
  placementContext=context
  local cards={}
  for i,side in ipairs({'player','enemy'})do
    local p=voxelPlacement(context,side);placements[side]=p
    if p and p.alpha>.001 then
      local card,model=p.card,p.model
      local ax,ay=card.ax/GB_W-.5,(GB_H-card.ay)/GB_H
      local x,y,z=model[1]*ax+model[2]*ay+model[4],
        model[5]*ax+model[6]*ay+model[8],model[9]*ax+model[10]*ay+model[12]
      cards[i]={texture=card.canvas,model=model,pull=V.require('BattleBillboard').PULL,
        floor=ground,foot={x,z,ground,radius=math.max(6,math.min(14,card.picWidth*p.worldPixel*.28)),
          pressure=p.alpha*math.max(0,1-math.max(0,y-ground)/3)}}
    end
  end
  return cards
end

function Provider:drawWorld(context)
  drawn.player, drawn.enemy = false, false
  if not (context and context.services) then return false end
  if context.arena and context.arena.backgroundOnly then return false end
  -- Other compatible arena hosts may not provide the early bounds pass.
  if preparedContext ~= context then self:prepareFrame(context) end
  preparedContext = nil
  if voxelArena(context) then
    drawn.enemy = drawVoxelSide(context, "enemy")
    drawn.player = drawVoxelSide(context, "player")
    return drawn.player or drawn.enemy
  end
  if type(context.services.project) ~= "function" then return false end
  local g = love.graphics
  if g.push then g.push("all") end
  if g.setShader then g.setShader() end
  if g.setDepthMode then g.setDepthMode("always", false) end
  g.setBlendMode("alpha", "premultiplied")
  g.setColor(1, 1, 1, 1)
  drawn.enemy = drawSide(context, "enemy")
  drawn.player = drawSide(context, "player")
  if g.pop then g.pop() end
  return drawn.player or drawn.enemy
end

function Provider:covers(context, side)
  return (side == "player" or side == "enemy") and drawn[side] == true
end

function Provider:showing(context, side)
  -- Optional hosts can query visibility before their render pass. Answer
  -- from live battle state without forcing an early, stale GPU capture.
  if not active or not (side == "player" or side == "enemy") then return false end
  if side == "player" and backPinned(context and context.battle, context and context.arena) then
    return false
  end
  return sideVisible(context and context.battle, side) and true or false
end

-- Read-only bounds for the arena's local foreground clearing. These are
-- logical screen pixels after the same fit used by the actual billboard;
-- hidden/pinned native pictures must not cut holes through world terrain.
function Provider:presentationBounds(metrics, side, ground)
  local card=textures[side]
  if not (visible[side] and card and card.picWidth and card.picHeight) then return nil end
  local scale=require('src.battle.BattlePresentation').pictureScale(metrics,side,
    card.picWidth,card.picHeight)
  local arena=Provider.currentArena
  local zoom=1
  if arena and (arena.cardCanonical or arena.focusCanonical) then
    local Voxel3D=V.require("Voxel3D")
    local r=require("src.render.Renderer"):frameRects()
    local current={eye=Voxel3D.eye,focus=Voxel3D.focus,fov=Voxel3D.fovY}
    local now=Intro.worldPixel(current,arena[side],ground or 0,scale,r)
    local world=Intro.cardWorldPixel(arena,arena.cardCanonical or arena.focusCanonical,
      side,ground or 0,scale,r,card.trainer)
    if now<=0 then return nil end -- behind the close camera: no terrain cutout
    zoom=world/now
  end
  return {width=card.picWidth*scale*zoom,
    height=(card.picHeight+(card.wildHopActive and Motion.HOP_PIXELS or 0))*scale*zoom,
    worldYOffset=card.worldYOffset or 0}
end

function Provider:center(context, side)
  local cell = cellFor(context, side)
  if not cell then return nil end
  local card=textures[side]
  if card and card.worldPerPixel then
    local Voxel3D=V.require('Voxel3D')
    local view=V.require('Mat4').lookAt(Voxel3D.eye,Voxel3D.focus,{0,1,0})
    local h=card.picHeight*card.worldPerPixel*.45
    return {cell[1]+view[5]*h,(tonumber(context.groundY) or 0)+view[6]*h,cell[2]+view[7]*h}
  end
  return { cell[1], (tonumber(context.groundY) or 0) + WORLD_CARD_HEIGHT * .45 * distanceScale(context),
           cell[2] }
end

function Provider:footprint(context, side)
  local cell = cellFor(context, side)
  if not cell then return nil end
  local card=textures[side]
  if card and card.worldPerPixel then
    return {x=cell[1],y=tonumber(context.groundY) or 0,z=cell[2],
      radius=card.picWidth*card.worldPerPixel/2,height=card.picHeight*card.worldPerPixel}
  end
  return { x = cell[1], y = tonumber(context.groundY) or 0, z = cell[2],
           radius = 8 * distanceScale(context), height = WORLD_CARD_HEIGHT * distanceScale(context) }
end

function Provider:cameraLocked(context)
  -- StadiumBattleFX owns the host camera when it is installed.  Our local
  -- BattleCam lock above cannot affect that camera, so explicitly ask the
  -- host to keep Dramaless' authored base shot while native 2D cards are
  -- staged on the voxel arena.  That base shot is solved against the same
  -- fixed Gen 1 move/Poke Ball anchors as the captured cards.
  return backPinned(context and context.battle,context and context.arena) or (active and voxelArena(context))
end

function Provider:finish()
  if self.currentBattle then self.currentBattle.jpEnemySendOut3D=nil end
  self.currentBattle=nil
  Intro.finish(self.currentArena)
  self.currentArena=nil
  preparedContext=nil
  placementContext=nil;placements={}
  active = false
  textures.player, textures.enemy = nil, nil
  visible.player, visible.enemy = false, false
  drawn.player, drawn.enemy = false, false
  local ok, camera = pcall(V.require, "BattleCam")
  if ok and camera then
    camera.steerable = true
    camera.still = false
  end
end

function Provider:invalidate()
  self:finish()
  canvases = {}
  local ok, billboard = pcall(V.require, "BattleBillboard")
  if ok and billboard and billboard.invalidate then billboard.invalidate() end
  local picsOk, pics = pcall(V.require, "BattlePics")
  if picsOk and pics and pics.invalidate then pics.invalidate() end
end

return Provider
