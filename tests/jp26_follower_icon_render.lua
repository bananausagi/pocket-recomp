-- Compare the actual party-list and follower render paths pixel for pixel.
-- Native art comes from the user's ROM in production; these sheets are
-- original asymmetric test drawings, never downloaded cartridge graphics.
return function(Game,V,check,write)
  local g=love.graphics
  local F=require('src.render.JapaneseFollowerSprite')
  local P=require('src.render.PaletteFX')
  local A=require('src.render.Assets')
  local Party=require('src.ui.PartyMenu')
  local function pixels(image)
    local c=g.newCanvas(image:getWidth(),image:getHeight(),{dpiscale=1})
    g.setCanvas(c);g.clear(0,0,0,0);g.setShader();g.origin();g.setScissor()
    g.setColor(1,1,1,1);g.setBlendMode('replace');g.draw(image);g.setCanvas()
    local p=c:newImageData();c:release();g.setBlendMode('alpha');return p
  end
  local function sheet(path,height,trueColor)
    local p=love.image.newImageData(16,height)
    for yy=0,height-1 do for x=0,15 do
      local y,frame=yy%16,math.floor(yy/16)
      local foot=frame%2
      local body=x>=3 and x<=12 and y>=4 and y<=11
      local ear=(x==4 or x==5)and y>=2 and y<=4
      local leg=y>=12 and y<=13 and (x==4+foot or x==11-foot)
      local ink=ear or leg or (body and (x==3 or x==12 or y==4 or y==11))
      local shade=ink and 0 or body and (y<8 and .333333333 or .666666667) or 1
      -- A different right half and each distinct source frame catch both
      -- accidental full-frame reuse and wrong rest/alternate lookup.
      if x>8 and y==7 then shade=0 end
      if x==5 and y==5+frame%4 then shade=0 end
      local r,gg,b=shade,shade,shade
      if trueColor and body and not ink then r,gg,b=.25,.65,.9 end
      p:setPixel(x,yy,r,gg,b,trueColor and not(body or ear or leg) and 0 or 1)
    end end
    love.filesystem.write(path,p:encode('png'));p:release()
  end
  sheet('jp26-icon-sheet.png',96)
  sheet('jp26-icon-single.png',16)
  sheet('jp26-icon-mod.png',32,true)
  Game.data.icons={icons={},bySpecies={},byDex={}}
  local classes={'BUG','GRASS','SNAKE','QUADRUPED','MON','FAIRY','BIRD','WATER','PIKACHU','BALL','HELIX'}
  local function monFor(name)
    local id='JP26_ICON_'..name
    Game.data.pokemon[id]={dex=1,spriteFront='DO_NOT_LOAD_BATTLE_PICTURE.png'}
    Game.data.icons.bySpecies[id]=name
    Game.data.icons.icons[name]=(name=='BALL'or name=='HELIX')and'jp26-icon-single.png'or'jp26-icon-sheet.png'
    return {species=id,hp=20,stats={hp=20}}
  end
  local function drawMenu(mon,alt)
    local c=g.newCanvas(24,24,{dpiscale=1})
    g.setCanvas(c);g.clear(1,1,1,1);g.setColor(1,1,1,1);g.setShader()
    Party.drawIcon(Game,mon,4,4,false,0,alt,false);g.setCanvas()
    return c
  end
  local function drawField(sprite,phase,facing)
    local c=g.newCanvas(24,24,{dpiscale=1})
    g.setCanvas(c);g.clear(1,1,1,1);g.setColor(1,1,1,1);g.setShader()
    sprite:draw(4,8+sprite:poseOffset(phase),0,0,facing,phase,true);g.setCanvas()
    return c
  end
  local sprites,mons={},{}
  local comparisons=0
  P.setMode('og')
  local gallery=g.newCanvas(11*96,192,{dpiscale=1})
  g.setCanvas(gallery);g.clear(.8,.9,.85,1);g.setCanvas()
  for i,name in ipairs(classes) do
    local mon=monFor(name);local sprite=assert(F.new(Game.data,mon))
    sprites[i],mons[i]=sprite,mon
    check(sprite.frameWidth==16 and sprite.frameHeight==16,name..' keeps native 16px dots')
    for phase=0,1 do
      local menu=drawMenu(mon,phase==1);local expected=pixels(menu):getString()
      for _,facing in ipairs({'down','up','left','right'}) do
        local field=drawField(sprite,phase,facing)
        if facing=='down' or not sprite.def.jpFollowerDirections then
          check(pixels(field):getString()==expected,name..' pose '..phase..' '..facing..' matches actual party pixels')
          comparisons=comparisons+1
        end
        if facing=='down' then
          g.setCanvas(gallery);g.setColor(1,1,1,1)
          g.draw(menu,(i-1)*96,phase*96,0,2,2)
          g.draw(field,(i-1)*96+48,phase*96,0,2,2);g.setCanvas()
        end
        field:release()
      end
      menu:release()
    end
    local raw=pixels(sprite:resolveImage())
    check(select(4,raw:getPixel(0,0))==0,name..' removes OBJ index-zero background')
    check(select(4,raw:getPixel(6,9))==1 and select(1,raw:getPixel(6,9))>.99,
      name..' preserves white body created by OBP')
    check(sprite:poseOffset(1)==((name=='BALL'or name=='HELIX')and 1 or 0),name..' uses only its native alternate nudge')
    local geometry=sprite:getPoseGeometry('right',1,true)
    check(geometry.frame==(sprite.def.jpFollowerDirections and 5 or 1)
      and geometry.mirror==(sprite.def.jpFollowerDirections==true),name..' mirrors only a real native side frame')
  end
  write('party-field-exact.png',gallery:newImageData():encode('png'):getString());gallery:release()

  local sprite,mon=sprites[1],mons[1]
  local Runtime=require('src.mods.Runtime')
  local iconCalls,battleCalls=0,0
  Runtime.hooks:wrap('pokemon.sprite',function(next,path,ctx)battleCalls=battleCalls+1;return next(path,ctx)end,0,'jp26-icon-qa')
  Runtime.hooks:wrap('pokemon.icon',function(next,path,ctx)
    if ctx.mon==mon then iconCalls=iconCalls+1;ctx.trueColor=true;return'jp26-icon-mod.png'end
    return next(path,ctx)
  end,0,'jp26-icon-qa')
  P.setMode('redpp')
  local menu=drawMenu(mon,true);local field=drawField(sprite,1,'right')
  check(pixels(menu):getString()==pixels(field):getString(),'live pokemon.icon replacement matches the party-list replacement')
  check(iconCalls>0 and battleCalls==0,'follower uses pokemon.icon with live mon, never pokemon.sprite')
  write('mod-icon-party-field.png',pixels(field):encode('png'):getString())
  menu:release();field:release();Runtime.hooks:removeOwner('jp26-icon-qa')
  P.setMode('og');sprite:resolveImage()
  local reads,uploads,canvases=0,0,0
  local oldRead,oldUpload,oldCanvas=A.imageData,g.newImage,g.newCanvas
  A.imageData=function(...)reads=reads+1;return oldRead(...)end
  g.newImage=function(...)uploads=uploads+1;return oldUpload(...)end
  g.newCanvas=function(...)canvases=canvases+1;return oldCanvas(...)end
  for i=1,120 do sprite:poseOffset(i%2);sprite:resolveImage()end
  A.imageData,g.newImage,g.newCanvas=oldRead,oldUpload,oldCanvas
  check(reads==0 and uploads==0 and canvases==0,'120 warm animated frames perform zero image I/O or GPU allocations')
  local zone={{255,255,255},{30,210,80},{210,40,180},{0,0,0}}
  P.setMode('gbc')
  local colored=pixels(sprite:resolveImage(zone))
  local r,gg,b=colored:getPixel(6,6)
  check(math.abs(r-30/255)<.01 and math.abs(gg-210/255)<.01 and math.abs(b-80/255)<.01,
    '3D bakes the active map palette once into the party icon')

  -- Run the actual VoxelScene entity path, including its frame choice and
  -- depth mesh. Keep four facing renders equal for an icon without facings.
  P.setMode('og')
  local Scene,V3,Voxel=V.require('VoxelScene'),V.require('Voxel3D'),V.require('VoxelState')
  Voxel.angle=math.rad(35);Voxel.level=3
  local captured={}
  local originalDraw=V3.draw
  V3.draw=function(mesh,tex,matrix,...)
    captured[#captured+1]={mesh=mesh,texture=tex}
    return originalDraw(mesh,tex,matrix,...)
  end
  local function card(facing,phase)
    assert(V3.beginScene(480,360,40,48,96,72,{.2,.4,.6,1}))
    V3.lighting(false)
    check(Scene.drawEntity(sprite,32,48,facing,phase,true,0,nil,0),'actual VoxelScene draws icon '..facing..'/'..phase)
    local c=V3.endScene();g.setCanvas()
    return c:newImageData()
  end
  local first=card('down',1)
  write('voxel-icon.png',first:encode('png'):getString())
  for _,facing in ipairs({'up','left','right'}) do
    check(card(facing,1):getString()==first:getString(),'3D '..facing..' preserves the same icon pixels and mirror state')
  end
  local pose1=captured[1].mesh
  card('down',0)
  check(captured[#captured].mesh~=pose1,'3D chooses the real resting and alternate sheets separately')
  V3.draw=originalDraw

  -- Actual world integration: native actor trail, entity discovery, ground
  -- anchor, shadow pass, and removal before the next battle render.
  Game.data.field=Game.data.field or {}
  Game.data.field.playerSprites={walk='SPRITE_FIX_PLAYER'}
  Game.data.tilesets.FIX_OUT.tilesPerRow=love.image.newImageData(Game.data.tilesets.FIX_OUT.image):getWidth()/8
  local map=require('src.world.MapLoader').load(Game.data,'FIX_TOWN')
  local player=require('src.world.Player').new(Game.data,8,8,'right')
  local camera=require('src.render.Camera').new()
  local ow={isOverworld=true,map=map,player=player,camera=camera,entities={player},npcs={},neighbors={},ghosts={}}
  Game.overworld=ow;Game.stack.states={ow};Game.save.party={mon}
  Game.save.flags=Game.save.flags or {};Game.save.flags.EVENT_GOT_STARTER=true
  Game.save.options.jpFollower=true
  local Follow=require('src.world.JapaneseFollower')
  Follow.update(Game,ow)
  for _=1,33 do player.px=player.px+1;player.cellX=math.floor(player.px/16);Follow.update(Game,ow)end
  local actor=assert(ow.jpFollowerState).actor
  local _,_,poseY=actor:pose()
  check(poseY==actor.py,'native two-pose icon does not bob the whole moving actor')
  camera:follow(player.px,player.py,160,120)
  for _=1,100 do if Scene.prefetch(ow)then break end;V.require('ChunkMesher').pump(true)end
  local actorDraws=0;local actorImage=actor.sprite:resolveImage()
  V3.draw=function(mesh,tex,...)if tex==actorImage then actorDraws=actorDraws+1 end;return originalDraw(mesh,tex,...)end
  local function fieldScene(name)
    Follow.prepareDraw(Game,ow)
    local canvas=assert(Scene.render(ow,480,360,160,120,function()return P.GRAYS end))
    g.setCanvas();write(name..'.png',canvas:newImageData():encode('png'):getString())
  end
  fieldScene('voxel-scene-icon')
  check(actorDraws>0 and ow.entities[2]==actor,'real VoxelScene discovers and renders the native-icon actor')
  actorDraws=0;Game.stack.states={ow,{isBattleState=true}}
  fieldScene('voxel-scene-battle-hidden')
  check(ow.jpFollowerState==nil and #ow.entities==1 and actorDraws==0,'battle preparation removes icon and its shadow before drawing')
  V3.draw=originalDraw;Game.stack.states={ow};Follow.reset(ow)

  -- Restore 2D compositing around the native unchanged party grayscale.
  P.setMode('gbc')
  local raw=g.newCanvas(24,24,{dpiscale=1});g.setCanvas(raw);g.clear(0,0,0,0)
  sprite:draw(4,8,0,0,'down',0,false);g.setCanvas()
  local composed=g.newCanvas(24,24,{dpiscale=1});g.setCanvas(composed);g.clear(0,0,0,0)
  Game.renderer:blitCanvas(raw,1,1,{P.whole(zone)},1,1,0,0,0,0,24,24)
  g.setCanvas();g.setShader()
  local composited=pixels(composed)
  local rr,rg,rb=composited:getPixel(10,10)
  check(math.abs(rr-30/255)<.01 and math.abs(rg-210/255)<.01 and math.abs(rb-80/255)<.01,
    'flat final Renderer compositor applies map color exactly once')
  raw:release();composed:release()

  -- Failed image composition is bounded too: a corrupt override must not
  -- retry a GPU readback every tick while the actor tries to spawn.
  local bad=monFor('CORRUPT')
  assert(require('src.ui.PokemonIcon').resolve(Game,bad,false))
  local failedReads,failedCanvases=0,0
  A.imageData=function(path,...)
    if path=='jp26-icon-sheet.png'then failedReads=failedReads+1;error('test corrupt source')end
    return oldRead(path,...)
  end
  g.newCanvas=function(...)failedCanvases=failedCanvases+1;return oldCanvas(...)end
  local absent=true
  for _=1,60 do absent=F.new(Game.data,bad)==nil and absent end
  A.imageData,g.newCanvas=oldRead,oldCanvas
  check(absent and failedReads==1 and failedCanvases==1,'60 failed spawns attempt malformed source composition exactly once')
  F.invalidate()
  local repaired=F.new(Game.data,bad)
  check(repaired~=nil,'asset invalidation retries a repaired icon')
  repaired:release()

  for i=1,20 do P.setCustomRamp({{255,255,255},{i*10,60,90},{20,20,20},{0,0,0}});sprite:resolveImage()end
  P.setCustomRamp(nil);P.setMode('og')
  check(pcall(pixels,sprite:resolveImage()),'bounded palette-cache eviction preserves a live sprite')
  A.releaseSession()
  check(pcall(pixels,sprite:resolveImage()),'session release permits clean icon reconstruction')
  for _,s in ipairs(sprites)do s:release()end
  check(sprite:resolveImage()==nil,'released follower does not retain renderer access')
  check(#Game.mods.errors==0,'loaded MODs report no icon follower errors')
  write('results.json',assert(require('src.link.Json').encode({actualLoveGL=true,physicalAndroid=false,
    sourceArt='original test icon sheet, production uses imported party icon',nativeFrameSize=16,
    exactPartyComparisons=comparisons,classes=classes,arbitraryFacingMirrors=false,
    warmFrames=120,warmImageReads=reads,warmGPUUploads=uploads,warmCanvases=canvases})))
end
