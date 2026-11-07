-- Production GL battle presentation using authored fixture sprites/terrain.
-- No ROM, physical Android device, or speaker timing is claimed.
return function(Game,Renderer,V,state,check,write,render)
  local g=love.graphics
  local Battle=require('src.battle.BattleState')
  local Host=V.require('VoxelBattleStandalone')
  local Intro=V.require('BattleIntroFocus')
  local Cards=V.require('VoxelBattleCardProvider')
  local Blend=V.require('BattleCameraBlend')
  local V3=V.require('Voxel3D')
  local P=require('src.battle.BattlePresentation')
  local Json=require('src.link.Json')
  local Touch=require('src.core.TouchControls')
  local Viewport=require('src.render.GameViewport')
  local rawTime,rawDraw=love.timer.getTime,V3.draw
  local now=100
  love.timer.getTime=function()return now end
  local mesh=V.require('BattleBillboard').mesh()
  local samples,skipPlayer={},false
  V3.draw=function(m,tex,model,...)
    if m==mesh then
      local copy={};for i,n in ipairs(model)do copy[i]=n end
      local _,_,_,a=g.getColor()
      samples[#samples+1]={matrix=copy,alpha=a}
      if skipPlayer and #samples==2 then return end
    end
    return rawDraw(m,tex,model,...)
  end
  local report={cases={},physicalAndroid=false,assets='authored',clock='fixed physical frame time'}
  report.runtimeHashes={}
  for _,path in ipairs({
    'src/battle/BattleState.lua','src/battle/JapaneseBattlePanels.lua',
    'mods/DRAMALESS_SHAPE/lib/BattleIntroFocus.lua',
    'mods/DRAMALESS_SHAPE/lib/VoxelBattleCardProvider.lua',
    'mods/DRAMALESS_SHAPE/lib/VoxelBattleStandalone.lua',
    'mods/DRAMALESS_SHAPE/lib/VoxelBattleScene.lua',
    'mods/DRAMALESS_SHAPE/lib/BattleCam.lua',
    'mods/DRAMALESS_SHAPE/lib/Atmosphere.lua',
    'mods/DRAMALESS_SHAPE/lib/Voxel3D.lua',
    'mods/DRAMALESS_SHAPE/lib/TiltShift.lua',
  })do
    local bytes=love.filesystem.read(path)
    if bytes then report.runtimeHashes[path]=love.data.encode('string','hex',love.data.hash('sha256',bytes))end
  end
  write('focus-runtime-sha256.json',assert(Json.encode(report.runtimeHashes)))

  local function draw()
    samples={}
    local pixels,metrics=render()
    return pixels,metrics,samples
  end
  local function bounds(sample,anchorX,anchorY,w,h)
    local m=sample.matrix
    local out={x0=math.huge,y0=math.huge,x1=-math.huge,y1=-math.huge}
    for _,x in ipairs({(anchorX-w/2)/160-.5,(anchorX+w/2)/160-.5})do
      for _,y in ipairs({(144-anchorY)/144,(144-anchorY+h)/144})do
        local sx,sy=V3.project(m[1]*x+m[2]*y+m[4],m[5]*x+m[6]*y+m[8],m[9]*x+m[10]*y+m[12])
        if sx and sy then
          out.x0,out.y0=math.min(out.x0,sx),math.min(out.y0,sy)
          out.x1,out.y1=math.max(out.x1,sx),math.max(out.y1,sy)
        end
      end
    end
    out.height=out.y1-out.y0
    return out
  end
  local function difference(a,b)
    local n=0
    for y=0,a:getHeight()-1 do for x=0,a:getWidth()-1 do
      local r,g,b1=a:getPixel(x,y);local r2,g2,b2=b:getPixel(x,y)
      if math.max(math.abs(r-r2),math.abs(g-g2),math.abs(b1-b2))>3/255 then n=n+1 end
    end end
    return n
  end
  local function visiblePlayer(b)
    local context=Host.session.context
    Cards:update(context);local actual=draw()
    local own,original=rawget(b,'drawPicsLayer'),b.drawPicsLayer
    b.drawPicsLayer=function(self,slide,sx,sy,side,clip)
      if side=='player' then return end
      return original(self,slide,sx,sy,'enemy',clip)
    end
    Cards:update(context)
    skipPlayer=true;local absent=draw();skipPlayer=false
    b.drawPicsLayer=own;Cards:update(context)
    return difference(actual,absent)
  end
  local function capture(tag,pixels)
    write(tag..'.png',pixels:encode('png'):getString())
    draw() -- restore actual image after pixel-subtraction reference pass
    g.push('all');g.setCanvas(Viewport.target());g.origin();Touch:draw();g.pop()
    g.setCanvas();write(tag..'-touch.png',Viewport.target():newImageData():encode('png'):getString())
  end
  local function create(kind,speed)
    local b=kind=='trainer' and Battle.newTrainer(Game,'OPP_FIX_YOUNGSTER',1)
      or Battle.newWild(Game,'FIXMON_C',10)
    if kind=='trainer' then b.trainerPic=g.newImage('fixture/intro-trainer.png') end
    Game.stack.states={state};Game.overworld=state;Game.input:reset()
    Host.finish('jp23-next');Blend.cancel()
    Game.save.options.speedBattle=speed or 1
    Game.stack:push(b)
    return b
  end
  local function step(speed)
    now=now+1/60
    for _=1,speed or 1 do Game:step(1/60)end
  end
  local ok,err=xpcall(function()
    for _,size in ipairs({{480,800},{800,480}})do
      love.window.setMode(size[1],size[2],{vsync=0})
      Game.save.options.jpDialogScale=.75;Game.save.options.jpBattleIntro='focus'
      Game.save.options.animations=true;Game.save.options.textSpeed=3
      Game.save.options.screenPos='center';require('src.core.ScreenPosition').setMode('center')
      for _,kind in ipairs({'wild'})do
        for _,speed in ipairs({1,4})do
          now=now+10
          local b=create(kind,speed)
          local context=assert(Host.session).context
          local arena=context.arena;arena.presentationTime=1
          local tag=kind..'-'..size[1]..'x'..size[2]..'-'..speed..'x'
          local rows,first,shown,middle,last={},nil,nil,nil,nil
          local firstMarker,firstPull
          local firstPlayer,fullTextPlayer,lastPlayer
          local retainedPlayerCell={unpack(arena.player)}
          local retainedEnemyCell={unpack(arena.enemy)}
          for frame=0,720 do
            if frame>0 then step(speed)end
            local before=b.jpIntroTextShown==true
            local pixels,metrics,actual=draw()
            local intro=assert(arena.focusIntro,'focus mode installed')
            local trainer=b.showEnemyTrainer
            local pic=b:picImage(trainer and b.trainerPic or b.enemy.sprite)
            local enemy=assert(actual[1],tag..' enemy actual GL card drawn')
            local box=bounds(enemy,trainer and 124 or 80,trainer and 56 or 96,pic:getWidth(),pic:getHeight())
            local r=Renderer:frameRects();local scale=r.pw/context.services.renderSize.width
            for _,k in ipairs({'x0','y0','x1','y1','height'})do box[k]=box[k]*scale end
            local row={frame=frame,time=frame/60,introTime=intro.time,weight=Intro.weight(arena),box=box,
              phase=b.phase,chars=b.charIndex,total=b.total,textDrawn=b.jpIntroTextShown==true,
              eye={unpack(arena.lastPose.eye)},fov=arena.lastPose.fov,playerAlpha=actual[2] and actual[2].alpha}
            if frame%4==0 or row.textDrawn and not firstMarker then rows[#rows+1]=row end
            if frame==0 then
              first=row;firstPlayer=visiblePlayer(b);capture('focus-'..tag..'-first',pixels)
              check(firstPlayer==0,tag..' actual player pixels are outside initial close-up')
            end
            if not before then
              check(row.weight==1,tag..' focus holds before complete text draw '..frame)
            end
            if row.textDrawn and not firstMarker then
              firstMarker=frame;shown=row;fullTextPlayer=visiblePlayer(b)
              capture('focus-'..tag..'-text',pixels)
              check((b.charIndex or 0)>=(b.total or math.huge),tag..' marker requires complete native intro text')
              check(row.weight==1 and fullTextPlayer==0,tag..' complete text is visible before camera or player reveal')
            end
            if row.weight<1 and not firstPull then
              firstPull=frame;check(firstMarker and frame>firstMarker,tag..' pull starts after actual complete text frame')
            end
            if row.weight<.55 and row.weight>.2 and not middle then
              middle=row;middle.playerPixels=visiblePlayer(b);capture('focus-'..tag..'-pull',pixels)
            end
            check(box.x0>=-1 and box.y0>=1 and box.x1<=r.pw+1 and box.y1<=r.ph+1,
              tag..' full opponent fits visible field '..frame)
            if actual[2] and b:picOffset('back')==0 then
              check(actual[2].alpha==1,tag..' existing player has no appearance alpha ramp '..frame)
            end
            check(arena.player[1]==retainedPlayerCell[1] and arena.player[2]==retainedPlayerCell[2]
              and arena.enemy[1]==retainedEnemyCell[1] and arena.enemy[2]==retainedEnemyCell[2],tag..' actors remain on fixed field cells '..frame)
            if intro.done then
              last=row;lastPlayer=visiblePlayer(b);capture('focus-'..tag..'-settled',pixels);break
            end
          end
          check(firstMarker and firstPull and last,tag..' native typed intro completes focus and pull')
          check(lastPlayer>100,tag..' player is actually visible after camera pulls back')
          check(last.weight==0 and not arena.focusCanonical,tag..' final camera fully returns to canonical rig')
          local r=Renderer:frameRects();local m=P.metrics(r)
          local scale=r.pw/context.services.renderSize.width
          for _,side in ipairs({'enemy','player'})do
            local cell=arena[side];local px,py=V3.project(cell[1],context.groundY,cell[2])
            check(math.abs(px*scale-(m.x+m.actor[side].x*m.sx-r.vux)*r.dpiX)<.1
              and math.abs(py*scale-(m.y+m.actor[side].y*m.sy-r.vuy)*r.dpiY)<.1,
              tag..' final '..side..' feet match native move and ball anchors <0.1px')
          end
          check(first.box.height>last.box.height*1.1,tag..' camera pull provides actual field perspective')
          local normal=P.pictureScale(m,'enemy',b:picImage(b.showEnemyTrainer and b.trainerPic or b.enemy.sprite):getDimensions())
          local originalHeight=b:picImage(b.showEnemyTrainer and b.trainerPic or b.enemy.sprite):getHeight()*normal*r.Up
          if kind=='wild' then check(last.box.height<originalHeight*.85,tag..' distant opponent is visibly smaller than jp22 HUD-sized card')end
          local result={kind=kind,size=size,speed=speed,first=first,shown=shown,middle=middle,last=last,
            firstMarker=firstMarker,firstPull=firstPull,firstPlayerPixels=firstPlayer,
            fullTextPlayerPixels=fullTextPlayer,lastPlayerPixels=lastPlayer,frames=rows}
          report.cases[#report.cases+1]=result;write('focus-'..tag..'.json',assert(Json.encode(result)))
        end
      end
    end
    -- Logic can complete the typewriter between physical frames at 4x.
    -- Deliberately omit all draws until it finishes: elapsed time alone must
    -- not acknowledge text that the player has not seen yet.
    local b=create('wild',4);draw()
    local arena=Host.session.context.arena
    for _=1,400 do
      step(4)
      if b.current and b.charIndex and b.total and b.charIndex>=b.total then break end
    end
    check(b.current and b.charIndex>=b.total,'4x native typewriter completes between physical frames')
    check(not b.jpIntroTextShown and Intro.weight(arena)==1,
      'undrawn complete native text cannot release close-up')
    draw()
    check(b.jpIntroTextShown and Intro.weight(arena)==1,
      'first physical complete-text frame acknowledges without moving camera')
    step(4);draw()
    check(Intro.weight(arena)==1,'next 4x physical frame retains readable text hold')
    b.sendingOut=true;step(4);draw()
    check(Intro.weight(arena)==0 and not arena.focusCanonical,
      'skipping native intro settles exact camera before first sendout effect')
    check(#Game.mods.errors==0,'jp23 focus runs without MOD runtime errors')
    write('focus-results.json',assert(Json.encode(report)))
  end,debug.traceback)
  Host.finish('jp23-focus-finished');Blend.cancel()
  love.timer.getTime,V3.draw=rawTime,rawDraw
  if not ok then error(err,0)end
end
