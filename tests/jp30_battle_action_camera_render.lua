-- Actual loaded MOD/camera/card geometry, native AnimPlayer tile groups and
-- final white HUD compositor. Synthetic ROM-free art and terrain only.
return function(Game,Renderer,V,state,b,check,write)
  local g,fs=love.graphics,love.filesystem
  local Host=V.require('VoxelBattleStandalone')
  local Provider,Cards=V.require('VoxelBattleArenaProvider'),V.require('VoxelBattleCardProvider')
  local Action,V3=V.require('BattleActionCamera'),V.require('Voxel3D')
  local P=require('src.battle.BattlePresentation')
  local Viewport=require('src.render.GameViewport')
  local rawTime,rawDraw,rawVoxelDraw=love.timer.getTime,g.draw,V3.draw
  local cards
  local now=100;love.timer.getTime=function()return now end
  local pinned=V.backSpritesSetting:get()
  Game.save.options.jpDialogScale=.75;Game.save.options.animations=true
  Game.save.options.jpBattleCameraMotion=true;Game.save.options.reduceMotion=false;Game.save.options.jpReduceMotion=false
  local tile=g.newCanvas(8,8,{dpiscale=1});g.setCanvas(tile);g.clear(0,0,0,0)
  g.setColor(0,0,0,1);g.rectangle('fill',0,2,8,4);g.setCanvas()
  fs.write('fixture/action-motion-oam.png',tile:newImageData():encode('png'));tile:release()
  local data=b.animPlayer.data
  data.tilesheets.MOTION={path='fixture/action-motion-oam.png',width=8,height=8,tiles=1}
  data.frameBlocks=data.frameBlocks or {}
  data.frameBlocks.MOTION={{x=0,y=0,tile=0},{x=8,y=0,tile=0}}
  data.baseCoords.MOTION={x=124,y=64}
  data.subanims.MOTION={type='HVFLIP',blocks={{block='MOTION',coord='MOTION',mode=0}}}
  data.moveAnims.FIX_TACKLE={seq={{subanim='MOTION',tileset='MOTION',delay=12000}},source='authored QA'}
  local image,tiles
  g.draw=function(texture,quad,x,y,rot,sx,sy,...)
    if tiles and texture==image then tiles[#tiles+1]={x=x,y=y,rot=rot,sx=sx,sy=sy}end
    return rawDraw(texture,quad,x,y,rot,sx,sy,...)
  end
  V3.draw=function(mesh,texture,model,...)
    if cards and texture and texture.getWidth and texture:getWidth()==160 and texture:getHeight()==144 and model then
      local m={};for i,v in ipairs(model)do m[i]=v end;cards[#cards+1]=m
    end
    return rawVoxelDraw(mesh,texture,model,...)
  end
  local report={cases={},actualGL=true,android=false,assets='authored synthetic map, sprites and two-tile attack'}
  local function delta(a,c)
    return math.sqrt((a[1]-c[1])^2+(a[2]-c[2])^2+(a[3]-c[3])^2)
  end
  local function copy(p)return {p[1],p[2],p[3]}end
  local ok,err=xpcall(function()
    for _,size in ipairs({{480,800},{800,480}})do for _,pin in ipairs({false,true})do
      V.backSpritesSetting:sync(pin);love.window.setMode(size[1],size[2],{vsync=0})
      Game.stack.states={state};Game:draw()
      b.phase='menu';b.queue={};b.current=nil;b.waitFrames=nil;b.afterQueue=nil;b.nextInsert=0;b.animName=nil
      b.animPlaying=false;b.introBalls=false;b.introSlide=0;b.showPlayerBack=false;b.showEnemyTrainer=false
      b.enemyHudPending=false;b.enemySendingOut=false;b.sendingOut=false;b.growIn=nil;b.shrinkOut=nil
      b.fx={};b.picFx={};b.enemyHidden=false;b.fieldCleared=false
      b.jpCameraMoveTarget=nil;b.jpCameraHitTarget=nil;b.pendingHit=nil
      Game.stack.states={state,b};assert(Host.begin(b,Provider,Cards))
      local a=Host.session.context.arena;a.presentationTime=1
      local tag=size[1]..'x'..size[2]..'-'..(pin and 'pinned' or 'world')
      local rows={};local phaseHUD={};local maxAnchorError=0;local tileChecks=0
      local function render(label,phase)
        tiles={};cards={};Game:draw();g.setCanvas()
        local r=Renderer:frameRects();local m=P.metrics(r)
        local pose=a.lastPose
        local row={time=now,eye=copy(pose.eye),focus=copy(pose.focus),fov=pose.fov,phase=phase,
          kind=a.actionCamera and a.actionCamera.kind,aim=a.actionCamera and a.actionCamera.aim,
          yaw=a.actionCamera and a.actionCamera.yaw}
        local bottom=(m.y+m.command.y*m.sy-r.vuy)*r.dpiY
        local ratio=r.pw/Host.session.context.services.renderSize.width
        for _,model in ipairs(phase=='bounce' and {} or cards)do
          for _,x in ipairs({-28/160,28/160})do for _,y in ipairs({48/144,104/144})do
            local px,py=V3.project(model[1]*x+model[2]*y+model[4],model[5]*x+model[6]*y+model[8],model[9]*x+model[10]*y+model[12])
            check(px and px*ratio>=-.01 and px*ratio<=r.pw+.01 and py*ratio>=-.01 and py*ratio<=bottom+.01,
              'every actual 3D card corner stays inside field and above commands')
          end end
        end
        local lens=m.sceneLens
        if lens then
          check(lens.zoom==1,'true 3D motion never zooms the native OAM/HUD surface')
          for _,side in ipairs({'player','enemy'})do
            local oldX,oldY=side=='player' and 26 or 124,side=='player' and 96 or 56
            local x,y=P.effectPoint(m,oldX,oldY)
            local expectedX,expectedY
            if side=='player' and pin then
              expectedX=(m.x+m.actor.player.x*m.sx-r.vux)*r.dpiX
              expectedY=(m.y+m.actor.player.y*m.sy-r.vuy)*r.dpiY
            else
              local foot=a[side];expectedX,expectedY=V3.project(foot[1],a.groundY,foot[2])
              local ratio=r.pw/Host.session.context.services.renderSize.width
              expectedX,expectedY=expectedX*ratio,expectedY*ratio
            end
            local actualX=(m.x+(x+m.native.x)*m.sx-r.vux)*r.dpiX
            local actualY=(m.y+(y+m.native.y)*m.sy-r.vuy)*r.dpiY
            local e=math.max(math.abs(actualX-expectedX),math.abs(actualY-expectedY))
            maxAnchorError=math.max(maxAnchorError,e);check(e<.001,'world/card and native effect '..side..' target agree <.001px')
          end
          if pin then check(lens.actors.player.x==m.actor.player.x and lens.actors.player.y==m.actor.player.y,
            'pinned player native foot remains unchanged')end
        end
        if #tiles>=2 then
          local p,q=tiles[1],tiles[2]
          check(math.abs(p.x-q.x)==8 and p.y==q.y,'native adjacent OAM tiles retain exact 8px rigid spacing')
          check(p.rot==0 and q.rot==0 and math.abs(p.sx)==1 and math.abs(q.sx)==1,'native effect tiles never rotate or stretch')
          tileChecks=tileChecks+1
        end
        local hud=Renderer.battlePresentationCanvas:newImageData():getString()
        if phaseHUD[phase] then check(hud==phaseHUD[phase],phase..' white HUD/labels stay byte-identical while camera moves')else phaseHUD[phase]=hud end
        if label then write('motion30-'..tag..'-'..label..'.png',Viewport.target():newImageData():encode('png'):getString())end
        if pin and size[1]==800 and os.getenv('JP_QA_CAMERA_MOVIE')=='1' then
          write(('movie/frame-%04d.png'):format(#rows+1),Viewport.target():newImageData():encode('png'):getString())
        end
        rows[#rows+1]=row;return row
      end
      local base=render('base','menu')
      for _=1,50 do now=now+.1;render(nil,'menu')end
      local orbit=render('orbit','menu')
      check(delta(base.eye,orbit.eye)>.3,'physical camera eye orbits the arena in '..tag)
      check(delta(base.focus,orbit.focus)>.05,'resting camera gently changes actual point of attention')
      check(base.fov==orbit.fov,'resting movement is not a FOV zoom')
      local sourcePixels=Viewport.target():newImageData():getString()
      for _=1,40 do now=now+.1;render(nil,'menu')end
      local second=render('orbit-other','menu')
      check(sourcePixels~=Viewport.target():newImageData():getString(),'actual rendered terrain parallax changes')
      local retained=a.actionCamera
      b.phase='moveSelect';now=now+.1;render('moves','moves')
      check(a.actionCamera==retained,'opening the move list continues the same camera without reset')
      b.phase='messages';b:animNext('FIX_TACKLE',true)
      for _=1,25 do b:updateQueue();if b.animPlaying then break end end
      for _=1,25 do local st=b.animPlayer.steps[b.animPlayer.stepIndex];if st and #st.sprites==2 then break end;b:updateQueue()end
      image=b.animPlayer:sheetImage('MOTION')
      check(b.animPlaying and b.animName=='FIX_TACKLE','real native move queue starts the authored two-tile attack')
      for _=1,16 do now=now+.1;b:updateQueue();render(nil,'attack')end
      local attack=render('player-attack','attack')
      check(attack.kind=='attack' and attack.aim<-.8,'player attack follows the opposing recipient')
      b.animPlaying=false;b:applyHitFx({blink=b.enemy,animType=4})
      for _=1,16 do now=now+.1;render(nil,'hit')end
      local hit=render('target','hit')
      check(hit.kind=='hit' and hit.aim<-.8,'hit shifts attention toward the actual target')
      check(attack.aim*hit.aim>0,'move and impact retain the same attacked side')
      check(attack.fov==base.fov and hit.fov==base.fov,'attack and hit attention never changes FOV')
      check(tileChecks>=16,'native tile-group rigidity verified while true camera motion is active')
      local nativeHits={}
      for _,animType in ipairs({1,2,4,5})do
        local recipient=animType<=2 and b.player or b.enemy
        local expected=animType<=2 and 1 or -1
        b.phase='messages';b.animPlaying=true;b.animName='FIX_TACKLE'
        b.animAttackerIsPlayer=animType>=4;b.pendingHit={blink=recipient}
        b.jpCameraMoveTarget=recipient;b.jpCameraHitTarget=nil;b.fx={}
        for _=1,18 do now=now+.1;render(nil,'native-move-'..animType)end
        b.animPlaying=false;b.pendingHit=nil;b:applyHitFx({blink=recipient,animType=animType})
        local impact=render('native-hit-'..animType,'native-hit-'..animType)
        check(impact.kind=='hit' and impact.aim*expected>.9,'native hit type '..animType..' retains recipient through actual blink/shake')
        check((animType==4 and b.fx.blink~=nil) or (animType~=4 and b.fx.shakeProg~=nil),'actual native hit feedback is active')
        nativeHits[#nativeHits+1]=impact
      end
      Game.save.options.jpBattleCameraMotion=false;b.fx={};b.phase='menu'
      now=now+.1;local off=render('off','off')
      now=now+.1;local off2=render(nil,'off')
      check(delta(off.eye,off2.eye)==0 and delta(off.focus,off2.focus)==0 and not a.actionCamera,
        'OFF keeps the original camera perfectly fixed')
      Game.save.options.jpBattleCameraMotion=true
      for _,flag in ipairs({'reduceMotion','jpReduceMotion'})do
        Game.save.options[flag]=true;now=now+.1;local quiet=render(nil,'quiet-'..flag)
        check(not a.actionCamera and delta(quiet.eye,off.eye)<1e-8,flag..' forces canonical still camera')
        Game.save.options[flag]=false
      end
      Game.save.options.animations=false;now=now+.1;render(nil,'animationsOff')
      check(not a.actionCamera,'animations OFF suppresses camera motion');Game.save.options.animations=true
      b.phase='messages';b.animPlaying=true;b.animName='TOSS_ANIM'
      now=now+.1;local ball=render(nil,'ball')
      check(not a.actionCamera and delta(ball.eye,off.eye)<1e-8,'capture toss uses exact still native camera')
      b.animPlaying=false;now=now+.1;render(nil,'ballgap')
      check(not a.actionCamera,'capture queue gaps do not restart a camera')
      b.phase='menu';now=now+.1;render(nil,'restart');now=now+.1;render(nil,'restart')
      check(a.actionCamera~=nil,'return to menu resumes motion despite stale capture animation name')
      b.phase='messages';now=now+.1;render(nil,'announcement')
      check(a.actionCamera~=nil,'next move announcement does not snap due to stale ball name')
      b.picFx={[b.player]={kind='bounce',t=12}};now=now+.1;render(nil,'bounce')
      check(not a.actionCamera,'native high jump effects retain the fixed original shot')
      b.picFx={};b.phase='menu';b.animName=nil
      report.cases[#report.cases+1]={tag=tag,base=base,orbit=orbit,other=second,attack=attack,hit=hit,
        nativeHits=nativeHits,maxAnchorError=maxAnchorError,tileChecks=tileChecks,frames=rows}
      Host.finish('motion30-next')
    end end
    check(#Game.mods.errors==0,'live MOD motion generated no runtime errors')
  end,debug.traceback)
  g.draw,love.timer.getTime,V3.draw=rawDraw,rawTime,rawVoxelDraw;V.backSpritesSetting:sync(pinned)
  Host.finish('motion30-finished')
  report.ok,report.error=ok,err
  write('motion30-results.json',assert(require('src.link.Json').encode(report)))
  if not ok then error(err,0)end
end
