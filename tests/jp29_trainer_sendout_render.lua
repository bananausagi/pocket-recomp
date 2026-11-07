-- Actual ROM-free Game -> BattleState -> native card capture -> world mesh.
-- Art and ball sheet are authored fixtures, not retail ROM imagery.
return function(Game,Renderer,V,state,check,write)
  local g,fs=love.graphics,love.filesystem
  local Battle=require('src.battle.BattleState')
  local Send=require('src.battle.TrainerSendOut')
  local Host=V.require('VoxelBattleStandalone')
  local Cards=V.require('VoxelBattleCardProvider')
  local V3=V.require('Voxel3D')
  local Atmosphere=V.require('Atmosphere')
  local Blend=V.require('BattleCameraBlend')
  local Viewport=require('src.render.GameViewport')
  local Sound=require('src.core.Sound')
  local now=100
  local rawTime,rawSound,rawDraw,rawContact,rawSendDraw=love.timer.getTime,Sound.play,V3.draw,Atmosphere.drawContact,Send.draw
  love.timer.getTime=function()return now end
  local events={}
  Sound.play=function(_,id)
    events[#events+1]={id=id,time=now}
    return {isPlaying=function()return false end}
  end
  Game.save.options.jpBattleIntro='focus';Game.save.options.animations=true
  Game.save.options.jpDialogScale=.75;Game.save.options.jpBattleSpacing='wide'
  Game.save.options.reduceMotion=false;Game.save.options.jpReduceMotion=false
  Game.save.options.textSpeed=1;Game.save.options.battleStyle='set'
  -- The same fixture front artwork serves all the trainer's party species.
  for _,p in pairs(Game.data.pokemon)do p.spriteFront='fixture/battle-front.png';p.frontSize=7 end
  Game.data.trainers.OPP_FIX_YOUNGSTER.pic='fixture/intro-trainer.png'
  local ball=g.newCanvas(32,8,{dpiscale=1})
  g.setCanvas(ball);g.clear(0,0,0,0)
  for i=0,3 do
    g.setColor(0,0,0,1);g.rectangle('fill',i*8+1,1,6,6)
    g.setColor(1,1,1,1);g.rectangle('fill',i*8+2,2,4,4)
    g.setColor(0,0,0,1);g.rectangle('fill',i*8+1,3,6,2)
    g.setColor(1,1,1,1);g.rectangle('fill',i*8+3,3,2,2)
  end
  g.setCanvas();fs.createDirectory('assets/generated/battle')
  fs.write('assets/generated/battle/balls.png',ball:newImageData():encode('png'));ball:release()
  local report={cases={},physicalAndroid=false,assets='authored fixtures',audio='event order only'}
  local frameCards,enemyCapture,contacts,picCalls=0,nil,0,0
  local observing
  Send.draw=function(...)
    if observing then picCalls=picCalls+1 end
    return rawSendDraw(...)
  end
  V3.draw=function(mesh,texture,model,...)
    if observing and texture and texture.getWidth and texture:getWidth()==160 and texture:getHeight()==144 and model then
      frameCards=frameCards+1
      if frameCards==1 then enemyCapture=texture:newImageData()end
    end
    return rawDraw(mesh,texture,model,...)
  end
  Atmosphere.drawContact=function(...)
    if observing then contacts=contacts+1 end
    return rawContact(...)
  end
  local function render()
    frameCards,enemyCapture,contacts,picCalls=0,nil,0,0
    Game:draw();g.setCanvas()
  end
  local function save(tag)
    write(tag..'.png',Viewport.target():newImageData():encode('png'):getString())
    if enemyCapture then write(tag..'-card.png',enemyCapture:encode('png'):getString())end
  end
  local function dimensions(data)
    local loX,hiX,loY,hiY,n=160,-1,144,-1,0
    for y=0,143 do for x=0,159 do local _,_,_,a=data:getPixel(x,y)
      if a>.1 then n=n+1;loX=math.min(loX,x);hiX=math.max(hiX,x);loY=math.min(loY,y);hiY=math.max(hiY,y)end
    end end
    return {width=hiX-loX+1,height=hiY-loY+1,pixels=n}
  end
  local function run(b,speed,tag)
    local row={tag=tag,stages={},events={}}
    local first,full,seen=false,nil,{}
    events={}
    for frame=1,1800 do
      now=now+1/60
      if frame%12==0 then Game.input:sourcePress('a','sendout-qa')
      elseif frame%12==1 then Game.input:sourceRelease('a','sendout-qa')end
      for _=1,speed do Game:step(1/60);if b.phase=='menu'then break end end
      observing=b.growIn and b.growIn.presentation
      render()
      if observing then
        first=first or now
        local phase=observing.time<Send.OPEN and 'ball'
          or observing.time<Send.REVEAL and 'opening'
          or observing.time<Send.DURATION and 'materializing' or 'full'
        if not seen[phase]then
          seen[phase]=true
          check(Cards:covers(Host.session.context,'enemy'),tag..' '..phase..' really draws the world card')
          check(enemyCapture~=nil and frameCards>=1,tag..' '..phase..' reaches actual GL mesh')
          check(picCalls==1,tag..' '..phase..' captures the enemy exactly once without native duplicate (calls='..picCalls..')')
          local box=dimensions(enemyCapture)
          check(box.pixels>30,tag..' '..phase..' has nonempty card pixels')
          if phase=='ball'then
            check(box.width<30 and box.height<30,tag..' contains ball only before opening')
            check(contacts<=1,tag..' no full-size enemy contact shadow before emergence')
          end
          if phase=='full'then full=now end
          row.stages[#row.stages+1]={phase=phase,time=now-first,box=box,contacts=contacts}
          save(tag..'-'..phase)
        end
      end
      if b.phase=='menu'then break end
    end
    Game.input:sourceRelease('a','sendout-qa')
    check(seen.ball and seen.opening and seen.materializing and seen.full,tag..' all four stages are physically rendered')
    check(b.phase=='menu',tag..' actual queue returns to command UI')
    check(full and math.abs(full-first-Send.DURATION)<.035,tag..' physical release length survives gameplay speed')
    local poof,cry=0,0
    for _,e in ipairs(events)do
      check(e.id~='Ball_Toss',tag..' no capture throw sound at encounter or release')
      if e.id=='Ball_Poof'and e.time>=first and e.time<=full then poof=poof+1 end
      if e.id=='enemy-cry'then cry=cry+1;check(e.time>full,tag..' cry follows full displayed monster')end
      row.events[#row.events+1]={id=e.id,time=e.time-first}
    end
    check(poof==1 and cry==1,tag..' one release sound and one cry, no capture throw')
    report.cases[#report.cases+1]=row
  end
  local ok,err=xpcall(function()
    for _,size in ipairs({{480,800},{800,480}})do
      love.window.setMode(size[1],size[2],{vsync=0})
      for _,speed in ipairs({1,4})do
        Host.finish('sendout-next');Blend.cancel()
        Game.stack.states={state};Game.overworld=state;Game.input:reset()
        Game.save.options.speedBattle=speed
        local b=Battle.newTrainer(Game,'OPP_FIX_YOUNGSTER',1)
        b.playEntranceCry=function(self,battler)
          events[#events+1]={id=battler==self.enemy and 'enemy-cry'or'player-cry',time=now}
          return {isPlaying=function()return false end}
        end
        Game.stack:push(b)
        check(b.jpEnemySendOut3D==true,'modern actual voxel provider enables enemy ball presentation')
        local tag=size[1]..'x'..size[2]..'-'..speed..'x'
        run(b,speed,tag..'-first')
        b.queue={};b.nextInsert=0;b.phase='messages';b.afterQueue='menu'
        b:executeAction(b.enemy,b.player,{special='aiSwitch',index=2})
        run(b,speed,tag..'-switch')
        Host.finish('sendout-finished');Blend.cancel()
        check(not b.jpEnemySendOut3D,'provider teardown removes special presentation ownership')
      end
    end
  end,debug.traceback)
  love.timer.getTime,Sound.play,V3.draw,Atmosphere.drawContact,Send.draw=rawTime,rawSound,rawDraw,rawContact,rawSendDraw
  report.ok,report.error=ok,err
  write('trainer-sendout.json',assert(require('src.link.Json').encode(report)))
  if not ok then error(err,0)end
end
