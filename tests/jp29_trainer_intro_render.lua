-- Full Game/native battle queue -> real Japanese text -> actual voxel camera,
-- cards, shader, and foreground/HUD compositors. All art is authored fixture.
return function(Game,Renderer,V,state,check,write)
  local g,fs=love.graphics,love.filesystem
  local Battle=require('src.battle.BattleState')
  local Host=V.require('VoxelBattleStandalone')
  local Intro=V.require('BattleIntroFocus')
  local Blend=V.require('BattleCameraBlend')
  local Scene=V.require('VoxelBattleScene')
  local V3=V.require('Voxel3D')
  local P=require('src.battle.BattlePresentation')
  local Json=require('src.link.Json')
  local rawDraw,rawTime=V3.draw,love.timer.getTime
  local rawPressed,rawDown=Game.input.wasPressed,Game.input.isDown
  local pinned=V.backSpritesSetting:get();V.backSpritesSetting:sync(false)
  local now=100;love.timer.getTime=function()return now end
  -- Deliberate input mashing: every logic tick attempts to leave the text.
  Game.input.wasPressed=function(_,key)return key=='a'end
  Game.input.isDown=function(_,key)return key=='a'end
  local art=g.newCanvas(56,56,{dpiscale=1})
  g.setCanvas(art);g.clear(0,0,0,0)
  g.setColor(0,0,0,1);g.rectangle('fill',7,2,42,54)
  g.setColor(2/3,2/3,2/3,1);g.rectangle('fill',9,4,38,50)
  g.setColor(1/3,1/3,1/3,1);g.rectangle('fill',13,9,30,10)
  g.rectangle('fill',13,35,30,6);g.setCanvas()
  fs.write('fixture/trainer29.png',art:newImageData():encode('png'));art:release()
  Game.data.field.playerPics={back='fixture/trainer29.png'}
  Game.data.trainers.OPP_FIX_YOUNGSTER.pic='fixture/trainer29.png'
  Game.save.options.jpDialogScale=.75;Game.save.options.jpBattleIntro='focus'
  Game.save.options.animations=true;Game.save.options.colors='redpp'
  require('src.render.PaletteFX').setMode('redpp')
  state.isOpaque,state.isOverworld=true,true;state.player.facing='up'
  local worldArena={map=state.map,mid={136,136},player={136,136},enemy={136,88},playerCell={8,8},cam='wide'}
  local worldPose={eye={136,130,200},focus={136,0,130},fov=.8,up={0,1,0},curve=0}
  function state:draw()
    local surface=Scene.render(self,worldArena,function()end,{pose=worldPose,pitch=.7})
    if surface then Renderer:setWorldOverride(surface)end
    V3.camera=worldPose
  end
  Game.overworld=state
  local samples={}
  V3.draw=function(mesh,texture,model,...)
    if texture and texture.getWidth and texture:getWidth()==160 and texture:getHeight()==144 and model then
      local m={};for i,v in ipairs(model)do m[i]=v end
      local _,_,_,alpha=g.getColor()
      samples[#samples+1]={model=m,alpha=alpha}
    end
    return rawDraw(mesh,texture,model,...)
  end
  local function bounds(card,index)
    local m=card.model;local ax,ay=index==1 and 124 or 80,index==1 and 56 or 96
    local b={x0=math.huge,y0=math.huge,x1=-math.huge,y1=-math.huge,alpha=card.alpha}
    for _,x in ipairs({(ax-28)/160-.5,(ax+28)/160-.5})do
      for _,y in ipairs({(144-ay)/144,(144-ay+56)/144})do
        local px,py=V3.project(m[1]*x+m[2]*y+m[4],m[5]*x+m[6]*y+m[8],m[9]*x+m[10]*y+m[12])
        if not px then return {behind=true,alpha=card.alpha}end
        b.x0,b.y0,b.x1,b.y1=math.min(b.x0,px),math.min(b.y0,py),math.max(b.x1,px),math.max(b.y1,py)
      end
    end
    b.width,b.height=b.x1-b.x0,b.y1-b.y0;return b
  end
  local report={cases={},actualGL=true,android=false,assets='authored synthetic trainers and terrain'}
  local ok,err=xpcall(function()
    for _,size in ipairs({{480,800},{800,480}})do for _,spec in ipairs({{60,1,3},{20,4,1}})do
      local fps,speed,textSpeed=unpack(spec)
      love.window.setMode(size[1],size[2],{vsync=0})
      Game.save.options.textSpeed=textSpeed
      Game.stack.states={state};Host.finish('qa-next');Blend.cancel();Game:draw()
      local battle=Battle.newTrainer(Game,'OPP_FIX_YOUNGSTER',1)
      -- Observe a Japanese 3-line challenge (scroll) as well as the queue's
      -- real native string identity; rendering still uses actual ROM-free font.
      battle.introText='たんパンこぞうが\nしょうぶを\vしかけてきた！'
      Game.stack:push(battle)
      local context=assert(Host.session).context;local arena=context.arena
      check(arena.trainerIntro and not arena.focusIntro,'trainer uses dedicated challenge-first staging')
      local begun=now
      battle.jpTrainerIntroTiming={focus=true,slideStart=0,revealTime=1.2,clock={position=function()return now-begun end}}
      local tag=size[1]..'x'..size[2]..'-'..fps..'fps-'..speed..'x'
      local rows={};local textAt,pullAt,readyAt,closeBox,lastBox,firstX,enteredX,previousHeight
      local shots={}
      local function picture(name)
        if not shots[name] then
          shots[name]=true
          local pixels=require('src.render.GameViewport').target():newImageData()
          write('trainer29-'..tag..'-'..name..'.png',pixels:encode('png'):getString())
        end
      end
      for frame=0,math.ceil(fps*10)do
        if frame>0 then
          now=now+1/fps
          for _=1,60/fps*speed do Game:step(1/60)end
        end
        local before=battle.jpIntroTextShown==true
        samples={};Game:draw();g.setCanvas()
        check(#samples==2,tag..' exactly two captured cards, no stale fallback duplication')
        local foe,player=bounds(samples[1],1),bounds(samples[2],2)
        local w=Intro.weight(arena)
        local row={frame=frame,time=now-begun,weight=w,foe=foe,player=player,text=before,
          introSlide=battle.introSlide,chars=battle.charIndex,total=battle.total,eye=arena.lastPose.eye}
        rows[#rows+1]=row
        if frame==0 then
          firstX=foe.x1;check(foe.x1<0,'foe starts beyond left edge of the close camera')
          check(player.alpha==0,'player is not shown alongside initial opponent')
        end
        if not before then check(w==1,tag..' entire native text must be drawn before pull')end
        if (battle.introSlide or 0)<=44 and not shots.arrival then
          enteredX=foe.x0;closeBox=foe;picture('arrival')
          check(foe.x0>=.9 and foe.x1<=size[1]-.9,'arrived foe fully fits close-up')
          check(player.alpha==0,'near trainer stays hidden in opponent close-up')
        end
        if battle.jpIntroTextShown and not textAt then
          textAt=now-begun;picture('challenge')
          check(w==1 and player.alpha==0,'fully drawn challenge precedes camera and player reveal')
          check((battle.charIndex or 0)>=battle.total,'actual text acknowledgement requires final glyph')
        end
        if w<1 and previousHeight then
          check(foe.height<=previousHeight+.001,'pull-back never makes the opponent grow before shrinking')
        end
        previousHeight=foe.height
        if w<1 and not pullAt then
          pullAt=now-begun;check(textAt and pullAt>textAt,'first pull frame is after complete challenge draw')
        end
        if w<.55 and w>.2 then picture('pull')end
        if (battle.introSlide or 0)<=44 then
          if not (foe.y0>=1.9 and foe.x0>=.9 and foe.x1<=size[1]-.9) then write('trainer29-failure.json',assert(Json.encode({row=row,canonical=arena.cardCanonical,metrics=arena.jpMetrics,rows=rows})))end
          check(foe.y0>=1.9 and foe.x0>=.9 and foe.x1<=size[1]-.9,'whole foe stays framed during hold/pull')
        end
        if not arena.trainerIntro.done then
          check(battle.showPlayerBack and battle.showEnemyTrainer and battle:picOffset('foe')==0,
            'button mashing cannot start native retreat before camera settles')
        end
        if arena.trainerIntro.done then
          readyAt=now-begun;lastBox=foe;picture('ready')
          check(w==0 and player.alpha==1,'settled camera has both trainers visible')
          break
        end
      end
      check(textAt and pullAt and readyAt and closeBox and lastBox,'all native challenge/cinematic milestones reached')
      check(enteredX>firstX,'opponent visibly slides from left inside the enlarged camera')
      print('JP29 SIZE '..tag..' close='..closeBox.height..' final='..lastBox.height)
      check(closeBox.height>lastBox.height*1.45,'close opponent is distinctly enlarged before pull-back')
      check(readyAt-textAt>=1 and readyAt-textAt<1.2,'camera duration stays physical at both 1x and 4x')
      local r=Renderer:frameRects();local m=P.metrics(r)
      local ratio=r.pw/context.services.renderSize.width
      for _,side in ipairs({'enemy','player'})do
        local cell=arena[side];local x,y=V3.project(cell[1],context.groundY,cell[2])
        check(math.abs(x*ratio-(m.x+m.actor[side].x*m.sx-r.vux)*r.dpiX)<.1
          and math.abs(y*ratio-(m.y+m.actor[side].y*m.sy-r.vuy)*r.dpiY)<.1,
          'settled '..side..' aligns with native ball/move anchor within .1px')
      end
      report.cases[#report.cases+1]={tag=tag,textAt=textAt,pullAt=pullAt,readyAt=readyAt,closeBox=closeBox,lastBox=lastBox,frames=rows}
      write('trainer29-'..tag..'.json',assert(Json.encode(rows)))
      Host.finish('qa-next');Blend.cancel()
    end end
    check(#Game.mods.errors==0,'full trainer intro produces no MOD errors')
  end,debug.traceback)
  V3.draw,love.timer.getTime=rawDraw,rawTime
  Game.input.wasPressed,Game.input.isDown=rawPressed,rawDown
  V.backSpritesSetting:sync(pinned);Host.finish('qa-done');Blend.cancel()
  report.ok,report.error=ok,err
  write('trainer29-render.json',assert(Json.encode(report)))
  if not ok then error(err,0)end
end
