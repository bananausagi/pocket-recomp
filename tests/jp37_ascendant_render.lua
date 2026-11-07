-- Installed VASC against the production JP engine, with authored fixture data.
return function(Game,Renderer,V,check,write)
  local g=love.graphics
  local v3=V.require('Voxel3D')
  check(v3.available(),'Ascendant 3D shader links on requested GLES')
  check(v3.shader(false,true)~=nil,'Ascendant battle visibility shader links')
  require('tests.jp37_visibility_render')(Game,V,check,write)
  local Scene,Mesh=V.require('VoxelScene'),V.require('ChunkMesher')
  local data=Game.data
  data.tilesets.FIX_OUT.tilesPerRow=love.image.newImageData(data.tilesets.FIX_OUT.image):getWidth()/8
  data.tilesets.FIX_OUT.walkable={0,1,2}
  local map=require('src.world.MapLoader').load(data,'FIX_TOWN')
  local state={map=map,neighbors={},ghosts={},entities={},
    player={cellX=8,cellY=8,px=128,py=128},camera={x=0,y=0},
    paletteNameFor=function()return 'PALLET'end}
  map.id='ROUTE_1';map.def.tileset='OVERWORLD'
  Game.overworld=state
  local voxel=V.require('VoxelState');voxel.level=3;voxel.angle=math.rad(35)
  local canvas
  for _=1,350 do
    canvas=Scene.render(state,800,480,240,144,function()return nil end)
    if canvas then break end
    Mesh.pump(true,false,true)
  end
  check(canvas~=nil,'installed Ascendant world produces a real 3D canvas')
  g.setCanvas();write('ascendant-world.png',canvas:newImageData():encode('png'):getString())
  local Weather=V.require('Weather')
  Weather.setting:sync('clear')
  local clear=Scene.render(state,800,480,240,144,function()return nil end):newImageData():getString()
  for _,mode in ipairs({'rain','snow','fog','storm'})do
    Weather.setting:sync(mode);Weather.setClock(5)
    local effect=Scene.render(state,800,480,240,144,function()return nil end)
    check(effect:newImageData():getString()~=clear,'VASC '..mode..' changes the world')
    write('weather-'..mode..'.png',effect:newImageData():encode('png'):getString())
  end
  Weather.setting:sync('clear')
  local fs=love.filesystem
  local Save=require('src.core.SaveData')
  local Pokemon=require('src.pokemon.Pokemon')
  local Battle=require('src.battle.BattleState')
  local Stack=require('src.core.StateStack');Stack:init();Game.stack=Stack
  local Touch=require('src.core.TouchControls');Touch:init();Touch.active=true
  Game.input=require('src.core.Input');Game.input:init()
  local options=Game.save.options;Game.save=Save.newGame();Game.save.options=options
  Game.save.version='red_jp';Game.save.party={Pokemon.new(data,'FIXMON_A',12)}
  Game.save.party[1].nickname='ゼニガメ'
  options.colors='gbc';require('src.render.PaletteFX').setMode('gbc')
  require('tests.jp_battle_bitmap_font')(data)
  require('src.core.Data').font=data.font
  local function art(path,r,green,b,back)
    local c=g.newCanvas(56,56,{dpiscale=1});g.setCanvas(c);g.clear(0,0,0,0)
    g.setColor(r,green,b,1);g.rectangle('fill',8,9,40,back and 47 or 39)
    g.rectangle('fill',14,2,8,8);g.rectangle('fill',35,2,8,8)
    g.setColor(.02,.03,.04,1);g.rectangle('fill',16,20,5,5);g.rectangle('fill',35,20,5,5)
    g.setCanvas();fs.write(path,c:newImageData():encode('png'));c:release()
  end
  art('fixture/vasc-back.png',1,.3,.06,true)
  art('fixture/vasc-front.png',.8,.04,1,false)
  data.pokemon.FIXMON_A.spriteBack='fixture/vasc-back.png'
  data.pokemon.FIXMON_A.spriteFront='fixture/vasc-back.png'
  data.pokemon.FIXMON_A.battleScaleBack=1
  data.pokemon.FIXMON_C.spriteFront='fixture/vasc-front.png';data.pokemon.FIXMON_C.frontSize=7
  Battle.invalidate()
  local OW=V.require('OverworldBattle')
  state.isOpaque,state.isOverworld=true,true
  function state:draw()
    local r=Renderer:frameRects()
    local c=Scene.render(self,r.pw,r.ph,240,144,function()return nil end)
    if c then Renderer:setWorldOverride(c)end
  end
  for _,size in ipairs({{800,480},{480,800}})do
    love.window.setMode(size[1],size[2],{vsync=0})
    for _,mode in ipairs({true,'arena','flatB'})do
      OW.setting:sync(mode)
      local b=Battle.newWild(Game,'FIXMON_C',10)
      b.player.name,b.enemy.name='ゼニガメ','フシギダネ'
      b.phase,b.menuIndex,b.frame='menu',1,0
      b.isOpaque=true;b.introSlide,b.introBalls,b.showPlayerBack=0,false,false
      b.enemyHudPending,b.enemySendingOut=false,false
      Stack.states={state};OW.begin(state,b);Stack.states={state,b}
      local shot
      for _=1,350 do OW.update(1/60);shot=OW.shot();if shot then break end end
      check(shot and shot.canvas,'VASC '..tostring(mode)..' battle produces a scene')
      Game:draw();OW.update(1/60);Game:draw();g.setCanvas()
      local target=require('src.render.GameViewport').target()
      write('battle-'..tostring(mode)..'-'..size[1]..'x'..size[2]..'.png',target:newImageData():encode('png'):getString())
      local pixels=target:newImageData()
      local minx,miny,maxx,maxy,count=math.huge,math.huge,0,0,0
      for y=0,pixels:getHeight()-1 do for x=0,pixels:getWidth()-1 do
        local r,g,b=pixels:getPixel(x,y)
        if r>.3 and b>.3 and g<r*.4 and g<b*.4 then
          minx,miny,maxx,maxy,count=math.min(minx,x),math.min(miny,y),math.max(maxx,x),math.max(maxy,y),count+1
        end
      end end
      check(count>600,'opponent remains readable in '..tostring(mode)..' '..size[1]..'x'..size[2]..' count='..count)
      check(minx>=6 and maxx<size[1]-6 and miny>=6,'entire opponent stays inside viewport '..minx..','..miny..' '..maxx..','..maxy)
      write('battle-'..tostring(mode)..'-'..size[1]..'x'..size[2]..'.png',
        target:newImageData():encode('png'):getString())
      check(b.voxelAscendantShot~=nil,'native battle uses the active VASC shot')
      check(#Game.mods.errors==0,'no runtime MOD error after VASC battle draw')
      OW.finish()
    end
  end
  Stack.states={state}
  require('tests.jp36_windows_render')(Game,Renderer,V,state,check,write)
  check(#Game.mods.errors==0,'renderer and companion MODs have no runtime errors')
end
