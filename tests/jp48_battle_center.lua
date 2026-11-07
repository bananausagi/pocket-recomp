-- Exercise the real host, bundled renderer, camera projection and touch router.
-- No cartridge data: the parent fixture authors its sprites and map.
return function(Game,Renderer,V,state,battle,check,write)
  local g=love.graphics
  local P=require('src.battle.BattlePresentation')
  local Layout=require('src.ui.GameUILayout')
  local Panels=require('src.battle.JapaneseBattlePanels')
  local Touch=require('src.core.TouchControls')
  local T=require('src.core.JapaneseTouchMode')
  local Viewport=require('src.render.GameViewport')
  local Input=require('src.core.Input')
  local Safe=require('src.core.SafeArea')
  local Stack=Game.stack
  local Host=V.require('VoxelBattleStandalone')
  local Provider=V.require('VoxelBattleArenaProvider')
  local Cards=V.require('VoxelBattleCardProvider')
  local opts=Game.save.options
  -- Compare the solved camera at rest. Idle orbit intentionally moves the
  -- cards between draws; this suite tests placement, not that animation.
  opts.jpBattleCameraMotion=false
  local originalSafe=love.window.getSafeArea
  local baseline=os.getenv('JP_QA_CENTER_BASELINE')=='1'
  local report={baseline=baseline,physicalAndroid=false,cases={}}
  local cases={
    {972,1536,'optimized'}, {480,800,'optimized'}, {800,480,'optimized'},
    {360,800,'optimized'}, {1536,1160,'optimized'},
    {480,800,'buttons'}, {800,480,'buttons'}, {972,1536,'hidden'},
    {972,1536,'optimized',safe={0,36,972,1470}},
    {800,480,'optimized',safe={32,0,744,462}},
  }
  local function reset()
    Game:cancelPointers();Input:reset();Touch:reset()
    battle.phase='menu';battle.current=nil;battle.menuIndex=1
    battle.moveIndex=1;battle.moveSwapIndex=nil;battle.queue={}
    battle.chosen=nil;battle.introSlide=0;battle.jpEncounterAwaitDraw=nil
    battle.fieldCleared=false;battle.enemySendingOut=false;battle.enemyHudPending=false
  end
  local originalParty,originalResolve=battle.openParty,battle.resolveTurn
  battle.openParty=function(self)self.chosen='party';self.phase='messages'end
  battle.resolveTurn=function(self,move)self.chosen=move.id;self.phase='messages'end
  for ci,c in ipairs(cases)do
    love.window.setMode(c[1],c[2],{vsync=0});Viewport.reset()
    love.window.getSafeArea=function()return unpack(c.safe or {0,0,c[1],c[2]})end
    opts.jpTouchOptimized=c[3]=='optimized';opts.touchControls={enabled=c[3]~='hidden'}
    opts.hotbar=false;opts.jpBattleSpacing='wide';opts.jpDialogScale=.75
    Touch.active=true;Touch:applyOptions(opts);Input:init();Game.input=Input
    require('src.core.ScreenPosition').setMode('center')
    reset();Stack.states={state};Game:draw();g.setCanvas()
    Stack.states={state,battle}
    check(Host.begin(battle,Provider,Cards),'center case '..ci..' starts bundled 3D battle')
    local context=Host.session.context;context.arena.presentationTime=10
    for _,factor in ipairs(baseline and {.75} or {.5,.75,1.5})do
      for _,spacing in ipairs(baseline and {'wide'} or {'normal','wide','wider'})do
        opts.jpDialogScale=factor;opts.jpBattleSpacing=spacing;reset()
        Game:draw();g.setCanvas()
        local r=Renderer:frameRects();local m=P.metrics(r);local p=m.panels
        local x,y,w,h,sx,sy=Layout.place(r,{anchor='battlePresentation',w=p.width,h=p.height})
        local top=y+p.enemyHUD.y*sy
        local bottom=y+(p.command.y+p.command.h)*sy
        local cx=x+(p.command.x+p.command.w/2)*sx
        local cy=(top+bottom)/2
        local target=r.body
        if c[3]~='buttons' then
          local tx,ty,tw,th=Safe.rect();target={x=tx,y=ty,w=tw,h=th}
        end
        local tag=c[1]..'x'..c[2]..'-'..c[3]..'-'..factor..'-'..spacing..(c.safe and '-safe' or '')
        local errorX=math.abs(cx-target.x-target.w/2)*r.dpiX
        local errorY=math.abs(cy-target.y-target.h/2)*r.dpiY
        local projectionError=0
        for _,side in ipairs({'player','enemy'})do
          local cell=context.arena[side]
          local px,py=context.services.project(cell[1],context.groundY,cell[2])
          local ratio=r.pw/context.services.renderSize.width
          -- Idle/action camera motion remaps native FX to the live feet.
          local fx,fy=P.effectPoint(m,side=='player' and 26 or 124,side=='player' and 96 or 56)
          local a={x=fx+m.native.x,y=fy+m.native.y}
          projectionError=math.max(projectionError,
            math.abs(px*ratio-(m.x+a.x*m.sx-r.vux)*r.dpiX),
            math.abs(py*ratio-(m.y+a.y*m.sy-r.vuy)*r.dpiY))
        end
        if factor==.75 and spacing=='wide' then
          g.push('all');g.setCanvas(Viewport.target());Touch:draw();g.pop()
          write('center-'..tag..'.png',Viewport.target():newImageData():encode('png'):getString())
        end
        report.cases[#report.cases+1]={case=tag,top=top,bottom=bottom,center={cx,cy},
          target={target.x+target.w/2,target.y+target.h/2},
          errorPixels={errorX,errorY},projectionErrorPixels=projectionError,
          glyphScale=p.scale,sceneScale=m.scale}
        if baseline then
          write('center-results.json',assert(require('src.link.Json').encode(report)))
          Host.finish('center-baseline');love.window.getSafeArea=originalSafe
          battle.openParty,battle.resolveTurn=originalParty,originalResolve
          return
        end
        check(errorX<1.01 and errorY<1.01,tag..' visible battle bounds center on usable screen within one pixel')
        check(top>=target.y-.01 and bottom<=target.y+target.h+.01,tag..' full command and HUD stay in safe bounds')
        check(math.abs(x-p.x)<.01 and math.abs(y-p.y)<.01,tag..' final composition does not reclamp panels away from actors')
        check(projectionError<.1,tag..' 3D battler feet follow the same shifted FX anchors; error='..projectionError)
        check(p.scale==math.floor(p.scale),tag..' retains integer pixel glyphs')
        if c[3]=='optimized' then
          local beforeY=p.y
          for _,phase in ipairs({'menu','moveSelect'})do
            reset();battle.phase=phase;Game:draw();g.setCanvas()
            local after=P.metrics(Renderer:frameRects()).panels
            check(after.y==beforeY,tag..' '..phase..' keeps a stable battle center')
            -- Slot 2 deliberately has zero PP in the shared fixture.
            local index=phase=='menu' and 2 or 3
            local cell=Panels.cells(after,phase)[index]
            local px,py=x+(cell.x+cell.w/2)*sx,y+(cell.y+8)*sy
            check(not T.navHit(px,py),tag..' '..phase..' visible choice owns its tap')
            Game:touchpressed('center-test',px,py)
            check(T.previewBattleCell(Game,battle)==index,tag..' '..phase..' touch preview follows displayed choice')
            Game:touchreleased('center-test',px,py);Input:step()
            check(battle.chosen==(phase=='menu' and 'party' or battle.player.curMoves[index].id),
              tag..' '..phase..' tap executes the displayed choice once')
          end
          reset();local nav=T.navigation(Game)[1];local nx,ny=nav.x+nav.w/2,nav.y+nav.h/2
          Game:touchpressed('center-back',nx,ny)
          Game:touchreleased('center-back',nx,ny);Input:step()
          check(Input:wasPressed('b'),'center case '..ci..' supports configured Back area')
        end
      end
    end
    Host.finish('center-qa')
  end
  love.window.getSafeArea=originalSafe
  battle.openParty,battle.resolveTurn=originalParty,originalResolve
  write('center-results.json',assert(require('src.link.Json').encode(report)))
end
