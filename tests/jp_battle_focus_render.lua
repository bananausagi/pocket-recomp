-- Real loaded MOD, scene camera, captured sprites and GL billboards. All
-- artwork/map data are authored fixtures; no retail data or Android claims.
return function(Game,Renderer,V,state,check,write,render)
  local g=love.graphics
  local Battle=require('src.battle.BattleState')
  local Host=V.require('VoxelBattleStandalone')
  local Cards=V.require('VoxelBattleCardProvider')
  local Intro=V.require('BattleIntroFocus')
  local Blend=V.require('BattleCameraBlend')
  local V3=V.require('Voxel3D')
  local P=require('src.battle.BattlePresentation')
  local rawTime,rawDraw=love.timer.getTime,V3.draw
  local now=100
  love.timer.getTime=function()return now end
  local mesh=V.require('BattleBillboard').mesh()
  local samples={}
  V3.draw=function(m,tex,model,...)
    if m==mesh then
      local copy={};for i,n in ipairs(model)do copy[i]=n end
      samples[#samples+1]={matrix=copy,texture=tex}
    end
    return rawDraw(m,tex,model,...)
  end
  local report={cases={},physicalAndroid=false,clock='fixed real presentation clock',assets='authored'}
  local function bounds(sample,anchorX,anchorY,w,h)
    local m=sample.matrix
    local out={x0=math.huge,y0=math.huge,x1=-math.huge,y1=-math.huge}
    for _,x in ipairs({(anchorX-w/2)/160-.5,(anchorX+w/2)/160-.5})do
      for _,y in ipairs({(144-anchorY)/144,(144-anchorY+h)/144})do
        local sx,sy=V3.project(m[1]*x+m[2]*y+m[4],m[5]*x+m[6]*y+m[8],m[9]*x+m[10]*y+m[12])
        assert(sx and sy,'visible card projects')
        out.x0,out.y0=math.min(out.x0,sx),math.min(out.y0,sy)
        out.x1,out.y1=math.max(out.x1,sx),math.max(out.y1,sy)
      end
    end
    out.height=out.y1-out.y0
    return out
  end
  local function create(kind)
    local b=kind=='trainer' and Battle.newTrainer(Game,'OPP_FIX_YOUNGSTER',1)
      or Battle.newWild(Game,'FIXMON_C',10)
    if kind=='trainer' then b.trainerPic=g.newImage('fixture/intro-trainer.png') end
    Game.stack.states={state};Game.overworld=state;Game.input:reset()
    Host.finish('focus-next');Blend.cancel()
    Game.stack:push(b)
    return b
  end
  local ok,err=xpcall(function()
    for _,size in ipairs({{480,800},{800,480}})do
      love.window.setMode(size[1],size[2],{vsync=0})
      Game.save.options.jpDialogScale=.75
      Game.save.options.jpBattleIntro='focus';Game.save.options.animations=true
      Game.save.options.screenPos='center';require('src.core.ScreenPosition').setMode('center')
      for _,kind in ipairs({'wild','trainer'})do
        now=now+10
        local b=create(kind)
        local context=assert(Host.session).context
        local arena=context.arena
        arena.presentationTime=1
        local tag=kind..'-'..size[1]..'x'..size[2]
        local rows,first,last={},nil,nil
        for frame=0,72 do
          if frame>0 then now=now+1/60;Game:step(1/60)end
          samples={}
          local pixels,metrics=render()
          local intro=assert(arena.focusIntro,'focus mode installed')
          local pic=b:picImage(b.showEnemyTrainer and b.trainerPic or b.enemy.sprite)
          local enemy=assert(samples[1],'enemy actual GL billboard drawn')
          local trainer=b.showEnemyTrainer
          local box=bounds(enemy,trainer and 124 or 80,trainer and 56 or 96,pic:getWidth(),pic:getHeight())
          local r=Renderer:frameRects()
          local scale=r.pw/context.services.renderSize.width
          for _,k in ipairs({'x0','y0','x1','y1','height'})do box[k]=box[k]*scale end
          local row={time=frame/60,introTime=intro.time,weight=Intro.weight(arena),box=box,
            eye={unpack(arena.lastPose.eye)},fov=arena.lastPose.fov,introSlide=b.introSlide}
          rows[#rows+1]=row
          if frame==0 then first=row elseif frame==72 then last=row end
          if frame==0 or frame==30 or frame==72 then
            write('focus-'..tag..'-'..frame..'.png',pixels:encode('png'):getString())
          end
          check(box.x0>=-1 and box.y0>=1 and box.x1<=r.pw+1 and box.y1<=r.ph+1,
            tag..' full actual opponent card fits viewport at frame '..frame)
        end
        write('focus-debug-'..tag..'.json',assert(require('src.link.Json').encode(rows)))
        check(first.box.height>last.box.height*1.45,tag..' opponent opens visibly enlarged then pulls back')
        check(first.weight==1 and last.weight==0 and arena.focusIntro.done,
          tag..' close-up ends once, after hold and smooth pullback')
        local r=Renderer:frameRects();local m=P.metrics(r)
        local px,py=V3.project(arena.enemy[1],context.groundY,arena.enemy[2])
        local scale=r.pw/context.services.renderSize.width
        check(math.abs(px*scale-(m.x+m.actor.enemy.x*m.sx-r.vux)*r.dpiX)<.1
          and math.abs(py*scale-(m.y+m.actor.enemy.y*m.sy-r.vuy)*r.dpiY)<.1,
          tag..' final opponent feet match exact native move and ball anchor')
        local resumed={encounter=true}
        Intro.begin(resumed,b)
        check(not resumed.focusIntro,tag..' rebuilding the host during the same battle never repeats focus')
        Intro.shown(arena);now=now+1;Intro.update(arena)
        check(Intro.weight(arena)==0,tag..' later draws cannot restart the completed focus')
        report.cases[#report.cases+1]={kind=kind,size=size,first=first,last=last,frames=rows}
        write('focus-'..tag..'.json',assert(require('src.link.Json').encode(rows)))
      end
    end
    local b=create('trainer');samples={};render()
    local a=Host.session.context.arena
    check(Intro.weight(a)==1,'next battle starts its own independent close-up')
    now=now+.1;Intro.update(a)
    local age=a.focusIntro.time
    now=now+60;Intro.update(a)
    check(a.focusIntro.time==age,'a suspended/background minute does not consume the intro')
    b.sendingOut=true;Intro.update(a);render()
    check(Intro.weight(a)==0 and not a.focusCanonical,'accelerated intro settles before first native send-out effect')
    Game.save.options.jpBattleIntro='original'
    b=create('trainer');render();check(not Host.session.context.arena.focusIntro,
      'original option leaves jp21 native camera and silhouette slide untouched')
    Game.save.options.jpBattleIntro='focus';Game.save.options.animations=false
    b=create('wild');render();check(not Host.session.context.arena.focusIntro,
      'animations disabled skips the added focus presentation')
    Game.save.options.animations=true;Game.save.options.reduceMotion=true
    b=create('wild');render();check(not Host.session.context.arena.focusIntro,
      'reduced motion skips the added focus presentation')
    Game.save.options.reduceMotion=nil
    local late={encounter=true}
    local delayed={kind='trainer',phase='intro',game=Game,jpTrainerIntroTiming={focus=false}}
    Intro.begin(late,delayed)
    check(not late.focusIntro,'late terrain readiness cannot replace the already clocked original trainer slide')
    check(#Game.mods.errors==0,'focus timelines have no MOD runtime errors')
    write('focus-results.json',assert(require('src.link.Json').encode(report)))
  end,debug.traceback)
  Host.finish('focus-finished');Blend.cancel()
  love.timer.getTime,V3.draw=rawTime,rawDraw
  if not ok then error(err,0)end
end
