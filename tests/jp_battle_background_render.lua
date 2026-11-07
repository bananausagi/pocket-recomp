-- Real seven-MOD loader + battle event + Game/Renderer/GL composition.
-- The simple overworld here intentionally takes the stock 2D world pass;
-- unlike the larger UI fixture it cannot supply a hidden 3D fallback.
return function(Game,Renderer,V,state,battle,check,write)
  local g=love.graphics
  local Host=V.require('VoxelBattleStandalone')
  local Cards=V.require('VoxelBattleCardProvider')
  local Finder=V.require('BattleArena')
  local VS=V.require('VoxelScene')
  local V3=V.require('Voxel3D')
  local Blend=V.require('BattleCameraBlend')
  local Runtime=require('src.mods.Runtime')
  local Pipelines=require('src.render.Pipelines')
  local Viewport=require('src.render.GameViewport')
  local oldEnd=Renderer.endFrame
  local worldCanvas
  Renderer.endFrame=function(self,...)
    worldCanvas=self.worldOverride
    return oldEnd(self,...)
  end
  love.window.setMode(480,800,{vsync=0})
  Game.save.options.jpDialogScale=1
  Game.save.options.pipelines={voxel=0}
  Pipelines.applyOptions(Game.save.options)
  check(Pipelines.worldPipeline()==nil,'world 3D pipeline is explicitly OFF')
  local originalDraw=state.draw
  function state:draw()
    Renderer:beginWorldPass()
    g.clear(.3,.55,.25,1)
    g.setColor(.25,.42,.2,1)
    for x=0,320,16 do for y=0,320,16 do
      if (x+y)%32==0 then g.rectangle('fill',x,y,16,16)end
    end end
    Renderer:endWorldPass()
  end
  local originalX,originalY=state.player.cellX,state.player.cellY
  Game.stack.states={state,battle}
  battle.phase,battle.current='menu',nil
  local function option(value)
    Runtime.emit('mod.options_changed',{mod='DRAMALESS_SHAPE',key='voxel_2d_battles',value=value})
  end
  local function start()
    Runtime.emit('battle.started',{battle=battle})
    local arena=Host.session and Host.session.context.arena
    if arena then arena.presentationTime=.55 end
    Game:draw();g.setCanvas()
    return arena
  end
  local function shot(label)
    write(label..'.png',Viewport.target():newImageData():encode('png'):getString())
  end
  local function retained(arena,label)
    check(arena and arena.backgroundOnly,label..' retains background without unsafe 3D actor placement')
    check(arena.map==state.map and arena.origin.cellX==originalX and arena.origin.cellY==originalY,
      label..' uses the original encounter map and position')
    check(worldCanvas~=nil,label..' presents a genuine GL world canvas')
    check(not Host.coversSide(battle,'player') and not Host.coversSide(battle,'enemy'),
      label..' keeps both native battle pictures and their FX')
    check(Cards:center(Host.session.context,'player')==nil
      and Cards:footprint(Host.session.context,'enemy')==nil,
      label..' does not export camera reference points as actor positions')
    check(Pipelines.worldPipeline()==nil,label..' never enables overworld 3D')
    local pose=arena.lastPose
    local x,y,z=pose.eye[1]-pose.focus[1],pose.eye[2]-pose.focus[2],pose.eye[3]-pose.focus[3]
    check(math.abs(math.atan2(y,math.sqrt(x*x+z*z))-math.rad(75))<1e-6,
      label..' preserves the accepted 75-degree camera')
    local active=g.getCanvas();g.setCanvas()
    local pixels=Renderer.canvas:newImageData();g.setCanvas(active)
    local yellow,green=0,0
    for py=0,143 do for px=0,159 do
      local r,gg,b,a=pixels:getPixel(px,py)
      if a>.1 and r>.8 and gg>.4 and b<.4 then yellow=yellow+1 end
      if a>.1 and r>.4 and r<.8 and gg>.4 and b<.4 then green=green+1 end
    end end
    check(yellow>100 and green>100,label..' draws both native actor artworks')
  end
  option(true)
  local oldFind=Finder.find
  Finder.find=function()return nil end
  local arena=start();shot('no-safe-pair-world-off-battle-on')
  retained(arena,'no safe pair')
  -- The actual provider's height check rejects every distinct cell pair.
  Finder.find=oldFind
  local oldGround=VS.groundAt
  VS.groundAt=function(_,x,y)return x*100+y end
  arena=start();shot('uneven-pair-world-off-battle-on')
  retained(arena,'uneven pair')
  VS.groundAt=oldGround
  arena=start();shot('flat-terrain-normal-arena')
  check(arena and not arena.backgroundOnly,'flat jp14 terrain still uses safe 3D actor placement')
  check(worldCanvas~=nil and Host.coversSide(battle,'enemy'),
    'normal flat terrain keeps its 3D map and card')
  -- Explicitly switching battle 3D OFF must suppress this fallback too.
  Finder.find=function()return nil end
  option(false);arena=start();shot('no-safe-pair-battle-off')
  check(not arena and worldCanvas==nil,'battle OFF respects native 2D background')
  option(true)
  -- Unavailable graphics support still declines gracefully, never a stale
  -- canvas or an attempt to force the ordinary world pipeline on.
  local oldAvailable=V3.available
  V3.available=function()return false end
  arena=start()
  check(not arena and worldCanvas==nil,'unavailable 3D declines safely')
  V3.available=oldAvailable
  Finder.find=oldFind
  Host.finish('qa-complete');Blend.cancel();state.draw=originalDraw
  Renderer.endFrame=oldEnd
  check(state.player.cellX==originalX and state.player.cellY==originalY,'background does not move player')
  check(#Game.mods.errors==0,'actual loaded MOD reports no errors')
end
