-- Final compositor bounds, native-ratio preferences, asymmetric insets and DPI.
return function(Game,Renderer,V,state,battle,check,write)
  local g=love.graphics
  local Viewport=require('src.render.GameViewport')
  local Faithful=require('src.core.FaithfulRes')
  local Touch=require('src.core.TouchControls')
  local T=require('src.core.JapaneseTouchMode')
  local Input=require('src.core.Input')
  local P=require('src.battle.BattlePresentation')
  local Host=V.require('VoxelBattleStandalone')
  local Provider=V.require('VoxelBattleArenaProvider')
  local Cards=V.require('VoxelBattleCardProvider')
  local opts=Game.save.options
  local original={safe=love.window.getSafeArea,os=love.system.getOS,
    dimensions=g.getDimensions,pixels=g.getPixelDimensions,dpi=g.getDPIScale,
    canvas=g.newCanvas,draw=g.draw,party=battle.openParty,resolve=battle.resolveTurn}
  love.system.getOS=function()return 'Android'end
  opts.jpDotMatrix=0;opts.jpBattleCameraMotion=false
  require('src.render.DotMatrix').setLevel(0)
  battle.openParty=function(self)self.chosen='party';self.phase='messages'end
  battle.resolveTurn=function(self,move)self.chosen=move.id;self.phase='messages'end
  local function alphaBounds(canvas)
    local pixels=canvas:newImageData()
    local minX,minY,maxX,maxY=math.huge,math.huge,-1,-1
    for y=0,pixels:getHeight()-1 do for x=0,pixels:getWidth()-1 do
      if select(4,pixels:getPixel(x,y))>.5 then
        minX,minY=math.min(minX,x),math.min(minY,y)
        maxX,maxY=math.max(maxX,x),math.max(maxY,y)
      end
    end end
    pixels:release()
    return {x=minX,y=minY,w=maxX-minX+1,h=maxY-minY+1}
  end
  local actual
  g.draw=function(drawable,...)
    if drawable==Renderer.battlePresentationCanvas then
      local x,y,_,sx,sy=...;sx,sy=sx or 1,sy or sx or 1
      x,y=g.transformPoint(x,y)
      local ink=alphaBounds(drawable)
      actual={x=x,y=y,sx=sx,sy=sy,left=x+ink.x*sx,top=y+ink.y*sy,
        right=x+(ink.x+ink.w)*sx,bottom=y+(ink.y+ink.h)*sy}
    end
    return original.draw(drawable,...)
  end
  local cases={
    {972,1536,name='reported-aspect',factor=.625,spacing='normal'},
    {972,1536,name='native-ratio',factor=.625,spacing='normal',faithful=true},
    {972,1536,name='native-ratio-upper',faithful=true,position='upper'},
    {972,1536,name='native-ratio-top',faithful=true,position='top'},
    {972,1536,name='asymmetric-top',safe={0,264,972,1272},factor=.625,spacing='normal'},
    {972,1536,name='top-and-native-ratio',safe={0,264,972,1272},faithful=true},
    {972,1536,name='large-windows',factor=1.5,spacing='wider'},
    {972,1536,name='small-windows',factor=.375,spacing='wider'},
    {972,1536,name='controls-hidden',hidden=true,faithful=true},
    {480,800,name='visible-buttons',buttons=true},
    {800,480,name='landscape-safe',safe={32,0,744,462},faithful=true},
    {1536,1160,name='wide-screen',faithful=true},
    {2160,3414,name='large-portrait',faithful=true,factor=.625,spacing='normal'},
    {990,1540,name='android-dpi-2.75',dpi=2.75,faithful=true},
    {990,1540,name='android-dpi-safe',dpi=2.75,safe={0,110,990,1375}},
    {480,800,name='return-to-portrait',faithful=true},
  }
  local report={physicalAndroid=false,romUsed=false,finalCompositor=true,cases={}}
  local function reset()
    Game:cancelPointers();Input:reset();Touch:reset();Game.sessionMenu=nil
    battle.phase='menu';battle.current=nil;battle.menuIndex=1;battle.moveIndex=1
    battle.chosen=nil;battle.queue={};battle.introSlide=0;battle.jpEncounterAwaitDraw=nil
    battle.fieldCleared=false;battle.enemySendingOut=false;battle.enemyHudPending=false
  end
  for _,c in ipairs(cases)do
    g.getDimensions,g.getPixelDimensions,g.getDPIScale,g.newCanvas=
      original.dimensions,original.pixels,original.dpi,original.canvas
    Viewport.reset();Renderer:releaseCanvases();Renderer:init()
    love.window.setMode(c[1],c[2],{vsync=0})
    local dpi=c.dpi or 1
    local uw,uh=c[1]/dpi,c[2]/dpi
    if dpi~=1 then
      g.getDimensions=function()return uw,uh end
      g.getPixelDimensions=function()return c[1],c[2]end
      g.getDPIScale=function()return dpi end
      g.newCanvas=function(w,h,settings)return original.canvas(w,h,settings or {dpiscale=dpi})end
    end
    local safe=c.safe or {0,0,c[1],c[2]}
    love.window.getSafeArea=function()return safe[1]/dpi,safe[2]/dpi,safe[3]/dpi,safe[4]/dpi end
    opts.jpTouchOptimized=not c.buttons;opts.touchControls={enabled=not c.hidden}
    opts.hotbar=false;opts.jpDialogScale=c.factor or .75;opts.jpBattleSpacing=c.spacing or 'wide'
    Touch.active=true;Touch:applyOptions(opts);Input:init();Game.input=Input
    Faithful.locked=c.faithful==true
    require('src.core.ScreenPosition').setMode(c.position or 'center')
    reset();Game.stack.states={state};Game:draw();g.setCanvas()
    Game.stack.states={state,battle}
    check(Host.begin(battle,Provider,Cards),c.name..' starts bundled 3D battle')
    Host.session.context.arena.presentationTime=10
    actual=nil;Game:draw();g.setCanvas()
    check(actual~=nil,c.name..' reaches actual HUD composite')
    local frame=actual
    local expectedX,expectedY=c[1]/2,c[2]/2
    if c.buttons then
      local b=require('src.ui.GameUILayout').usable(true)
      expectedX,expectedY=(b.x+b.w/2)*dpi,(b.y+b.h/2)*dpi
    end
    local centerX,centerY=(frame.left+frame.right)*dpi/2,(frame.top+frame.bottom)*dpi/2
    check(math.abs(centerX-expectedX)<1.01 and math.abs(centerY-expectedY)<1.01,
      c.name..' final visible pixels center on display; errors='..(centerX-expectedX)..','..(centerY-expectedY)..' draw='..require('src.link.Json').encode(frame))
    check(frame.left*dpi>=safe[1]-1 and frame.right*dpi<=safe[1]+safe[3]+1
      and frame.top*dpi>=safe[2]-1 and frame.bottom*dpi<=safe[2]+safe[4]+1,
      c.name..' final HUD stays clear of cutouts')
    local r=Renderer:frameRects();local m=P.metrics(r)
    check(r.battlePresentation and math.abs(frame.x-m.panels.x)<.001
      and math.abs(frame.y-m.panels.y)<.001,c.name..' compositor uses camera geometry')
    check(math.abs(frame.sx*dpi-m.panels.scale)<.001 and m.panels.scale==math.floor(m.panels.scale),
      c.name..' text retains integer physical pixels')
    local context=Host.session.context
    for _,side in ipairs({'player','enemy'})do
      local cell=context.arena[side]
      local x,y=context.services.project(cell[1],context.groundY,cell[2])
      local ratio=r.pw/context.services.renderSize.width
      local target=m.actor[side]
      check(math.abs(x*ratio-(m.x+target.x*m.sx-r.vux)*r.dpiX)<.1
        and math.abs(y*ratio-(m.y+target.y*m.sy-r.vuy)*r.dpiY)<.1,
        c.name..' '..side..' real 3D projection follows centered group')
    end
    local screenshot=Viewport.target():newImageData()
    local pr,pg,pb=screenshot:getPixel(math.floor((frame.left+4*frame.sx)*dpi),
      math.floor((frame.top+4*frame.sy)*dpi))
    check(pr>.95 and pg>.95 and pb>.95,c.name..' final pixels contain HUD paper at measured position')
    write(c.name..'.png',screenshot:encode('png'):getString());screenshot:release()
    report.cases[#report.cases+1]={case=c.name,window={c[1],c[2]},dpi=dpi,safe=safe,
      faithful=c.faithful==true,visible={left=frame.left*dpi,top=frame.top*dpi,right=frame.right*dpi,bottom=frame.bottom*dpi},
      center={centerX,centerY},expected={expectedX,expectedY},error={centerX-expectedX,centerY-expectedY}}
    if not c.buttons and not c.hidden then
      for _,phase in ipairs({'menu','moveSelect'})do
        reset();battle.phase=phase;Game:draw();g.setCanvas()
        check(math.abs(actual.top-frame.top)<.001 and math.abs(actual.bottom-frame.bottom)<.001,
          c.name..' '..phase..' keeps same final bounds')
        local index=phase=='menu' and 2 or 3
        local cell=require('src.battle.JapaneseBattlePanels').cells(m.panels,phase)[index]
        local x,y=actual.x+(cell.x+cell.w/2)*actual.sx,actual.y+(cell.y+8)*actual.sy
        Game:touchpressed('jp49-choice',x,y)
        check(T.previewBattleCell(Game,battle)==index,c.name..' '..phase..' hit target follows actual draw')
        Game:touchreleased('jp49-choice',x,y);Input:step()
        check(battle.chosen==(phase=='menu' and 'party' or battle.player.curMoves[index].id),
          c.name..' '..phase..' activates displayed choice once')
      end
    end
    Host.finish('jp49-center')
  end
  write('center-results.json',require('src.link.Json').encode(report))
  g.draw=original.draw;love.window.getSafeArea=original.safe;love.system.getOS=original.os
  g.getDimensions,g.getPixelDimensions,g.getDPIScale,g.newCanvas=
    original.dimensions,original.pixels,original.dpi,original.canvas
  battle.openParty,battle.resolveTurn=original.party,original.resolve
  Faithful.locked=false;Viewport.reset()
end
