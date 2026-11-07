return function(Game,Renderer,check,write)
 local Input=require('src.core.Input');local Touch=require('src.core.TouchControls')
 local T=require('src.core.JapaneseTouchMode');local Stack=require('src.core.StateStack')
 local Save=require('src.core.SaveData');local Viewport=require('src.render.GameViewport')
 local opts=Save.loadOptions();opts.jpTouchOptimized=true;opts.touchControls={enabled=true};opts.hotbar=false
 Game.save=Save.newGame({version='red_jp'});Game.save.options=opts;Game.sessionMenu=nil
 Input:init();Game.input=Input;Touch:init();Touch:ensureImages();Touch.active=true;Touch:applyOptions(opts)
 Stack:init();Game.stack=Stack;Viewport.reset();love.window.setMode(480,800)
 local ow={player={px=128,py=128,cellX=8,cellY=8,facing='up'},map={id='TEST'}}
 Game.overworld=ow;Stack:push(ow)
 local serial=0
 local function clean()
  Game:cancelPointers();Touch:reset();Input:reset();Game.sessionMenu=nil
 end
 local function put(state)
  clean();Stack.states={ow};Stack:push(state)
  if state.drawWindowOverlay then state:drawWindowOverlay()end
  return state
 end
 local function flick(dx,dy,releaseOnly,x,y)
  serial=serial+1;local id='flick'..serial
  x,y=x or 240,y or 350
  Game:touchpressed(id,x,y)
  if not releaseOnly then Game:touchmoved(id,x+dx,y+dy)end
  Game:touchreleased(id,x+dx,y+dy)
  Input:step();if not Game.sessionMenu then Stack:update(1/60)end
 end
 local function tap(x,y)
  serial=serial+1;local id='tap'..serial
  Game:touchpressed(id,x,y);Game:touchreleased(id,x,y)
  Input:step();if not Game.sessionMenu then Stack:update(1/60)end
 end

 -- This failed on the delivered jp45: SessionMenu interpreted a vertical
 -- flick as page scrolling, so a single-page menu never moved its cursor.
 Game:openSessionMenu('touch');local sheet=Game.sessionMenu
 flick(0,60)
 check(sheet.focus==2,'session menu flick moves one cursor row')
 flick(0,-60,true)
 check(sheet.focus==1,'release-only fast flick moves the session cursor')
 clean()
 local Options=require('src.ui.OptionsMenu')
 local options=put(Options.new(Game));local start=options.index
 flick(0,60)
 check(options.index==start+1,'floating settings consumes flick as a cursor step')
 flick(0,-60,true)
 check(options.index==start,'floating settings accepts coalesced fast flick')
 options.index=#options.view;options:drawWindowOverlay();flick(0,60)
 check(options.index==#options.view+1,'settings footer Back is reachable by flick')
 options:drawWindowOverlay();flick(0,-60)
 check(options.index==#options.view,'flick returns from settings footer to last row')

 -- Declarative MOD screens share this floating-window adapter.
 local changed=0
 local custom={rows={{id='one',label='ONE',step=function(_,d)changed=changed+d;return true end},
  {id='two',label='TWO',step=function(_,d)changed=changed+d;return true end}},index=1}
 Options.adaptRegisteredState(custom,Game);put(custom)
 flick(0,60);check(custom.index==2 and changed==0,'registered MOD cursor moves without changing a value')
 flick(60,0);check(custom.index==2 and changed==1,'horizontal MOD flick changes selected value once')
 flick(-60,0,true);check(changed==0,'reverse fast flick uses the same MOD value callback')

 local palette=put(require('src.ui.PaletteScreen').new(Game))
 check(palette.floatingPanel and #palette:items()>1,'test uses the actual floating color menu')
 local index=palette.index;flick(0,60)
 check(palette.index==math.min(index+1,#palette:items()),'color list cursor follows flick')
 flick(0,-60,true);check(palette.index==index,'color list reverse flick returns one row')
 palette.index=1;palette:drawWindowOverlay();flick(0,-60)
 check(palette.index==0,'color footer Back is reachable by flick')
 palette:drawWindowOverlay();flick(0,60)
 check(palette.index==1,'flick returns from color footer to first row')

 local Menu=require('src.ui.Menu');local selected
 local menu=put(Menu.new(Game,{{label='ONE',onSelect=function()selected=1 end},
  {label='TWO',onSelect=function()selected=2 end}},{noSound=true}))
 flick(0,60,true);check(menu.index==2 and not selected,'native list accepts release-only flick without confirming')
 tap(240,350);check(selected==2,'tap still confirms the native list')

 local name=put(require('src.ui.NamingScreen').new(Game))
 flick(60,0,true);check(name.col==2 and name.row==1,'name grid fast flick moves horizontally')
 flick(0,60);check(name.col==2 and name.row==2,'name grid flick moves vertically')
 tap(240,350);check(name.glyphs[1]=='き','name grid tap chooses the focused character')

 local quantity=put(require('src.ui.QuantityBox').new(Game,{max=10,start=5}))
 flick(0,-60,true);check(quantity.qty==6,'quantity picker receives native up semantics')
 flick(0,60);check(quantity.qty==5,'quantity picker receives native down semantics')

 local Pokemon=require('src.pokemon.Pokemon')
 Game.save.party={Pokemon.new(Game.data,'FIXMON_A',15),Pokemon.new(Game.data,'FIXMON_B',8)}
 local party=put(require('src.ui.PartyMenu').new(Game));party.index=1
 flick(0,60,true);check(party.index==2,'party cursor accepts fast flick')
 flick(0,-60);check(party.index==1,'party cursor accepts opposite flick')

 local Battle=require('src.battle.BattleState')
 clean();local b=Battle.newWild(Game,'FIXMON_B',8)
 -- Start at the choice phase; ROM-backed trainer art/intro is outside this test.
 Stack.states={ow,b};Stack.pointerRevision=Stack.pointerRevision+1
 b.phase='menu';b.queue={};b.introSlide=nil;b.jpEncounterAwaitDraw=nil;b.menuIndex=1
 b.openParty=function(self)self.chosen='party';self.phase='messages'end
 Renderer.jpLayout='battle';Renderer.jpBattleState=b
 flick(60,0,true,10,250)
 check(b.menuIndex==2 and not b.chosen,'battle flick selects without executing a command')
 tap(10,250)
 check(not b.chosen,'blank battle tap does not execute the focused command')
 b.phase='moveSelect';b.moveIndex=1;b.player.curMoves={b.player.curMoves[1]}
 local p=Renderer:frameRects().battlePresentation;p=p.panels or p
 local empty=require('src.battle.JapaneseBattlePanels').cells(p,'moveSelect')[4]
 local ex,ey=p.x+(empty.x+empty.w/2)*p.sx,p.y+(empty.y+empty.h/2)*p.sy
 Game:touchpressed('empty-move',ex,ey);Game:touchreleased('empty-move',ex,ey);Input:step()
 check(not Input:wasPressed('a') and b.phase=='moveSelect','empty move slot never confirms another move')
 Renderer.jpLayout=nil;Renderer.jpBattleState=nil

 local choice=put(require('src.ui.ChoiceBox').new(Game,function()end,{noSound=true}))
 flick(0,60,true);check(choice.index==2 and choice.pending==nil,'yes/no cursor moves without choosing')

 -- Cancellation must release the panel's own pointer, not only the host
 -- routing table; otherwise the next contact is ignored by the panel.
 options=put(Options.new(Game));start=options.index
 Game:touchpressed('cancel-panel',240,350);Game:touchmoved('cancel-panel',240,410)
 Game:cancelPointers();Game:touchreleased('cancel-panel',240,410)
 check(options.windowPanel.pointer==nil and options.index==start,'cancel clears floating panel ownership without an action')
 flick(0,60);check(options.index==start+1,'fresh flick works immediately after cancellation')
 start=options.index
 Game:touchpressed('stale-panel',240,350);Stack:push({});Stack:pop()
 Game:touchreleased('stale-panel',240,410)
 check(options.index==start,'push/pop between press and release rejects stale floating flick')
 Game:touchpressed('rotate-panel',240,350);love.window.setMode(800,480)
 Game:touchreleased('rotate-panel',240,410)
 check(options.index==start,'rotation rejects stale floating flick')
 love.window.setMode(480,800);options:drawWindowOverlay()
 start=options.index
 flick(0,60,true,120,10)
 check(options.index==start+1 and not Game.sessionMenu,'flick begun outside configured areas moves the floating cursor')

 -- Empty surrounding space remains useful for confirming the selection.
 local calls=0
 custom={rows={{label='ONE',activate=function()calls=calls+1 end},
  {label='TWO',activate=function()calls=calls+10 end}},index=1}
 Options.adaptRegisteredState(custom,Game);put(custom)
 flick(0,60);tap(240,750)
 check(calls==10,'tap outside a floating menu confirms its focused row')
 local panel=custom.windowPanel;local l=panel:layout();local hit=l.hits[1];local v=l.viewport
 tap(v.x+(hit.x+hit.w/2)*v.sx,v.y+(hit.y+hit.h/2)*v.sy)
 check(calls==11,'direct floating row taps remain available')
 Game:touchpressed('return-drag',240,350);Game:touchmoved('return-drag',240,410)
 Game:touchreleased('return-drag',240,350)
 check(calls==11,'returning a menu drag to its start never confirms')

 for _,size in ipairs({{480,800},{800,480},{972,1536}})do
  love.window.setMode(size[1],size[2]);Viewport.reset();clean()
  local x,y,w,h=require('src.core.SafeArea').windowRect()
  local nav=T.navigation()
  check(nav[1].x>=x and nav[2].x+nav[2].w<=x+w and nav[1].w<w/2,
    'navigation uses bounded individual areas '..size[1])
  check(T.navHit(nav[1].x+nav[1].w/2,nav[1].y+nav[1].h/2)=='touch-back'
    and T.navHit(nav[2].x+nav[2].w/2,nav[2].y+nav[2].h/2)=='touch-menu'
    and not T.navHit(x+w*.25,y+5) and not T.navHit(x+w*.75,y+5),
    'configured areas work without retaining the upper strip '..size[1])
  local canvas=love.graphics.newCanvas(size[1],size[2]);love.graphics.setCanvas(canvas)
  love.graphics.clear(0,0,0,0);Touch:draw();love.graphics.setCanvas()
  local pixels=canvas:newImageData();local bytes=pixels:getString()
  check(bytes==string.rep('\0',#bytes),'idle optimized controls draw no button, label or strip '..size[1])
  pixels:release()
  love.graphics.setCanvas(canvas);love.graphics.clear(.16,.22,.18,1)
  options=put(Options.new(Game));Touch:draw();love.graphics.setCanvas()
  write('transparent-area-settings-'..size[1]..'x'..size[2]..'.png',canvas:newImageData():encode('png'):getString())
  canvas:release()
 end

 -- Exercise the installed FirstPerson wrapper and real Transition class.
 -- Map content is an authored fixture; no ROM or device timings are assumed.
 love.window.setMode(480,800);Viewport.reset()
 local V=Game.mods.exports.DRAMALESS_SHAPE.lib
 local FP=V.require('FirstPerson');local Voxel=V.require('VoxelState')
 local Pipeline=require('src.render.Pipelines');local Transition=require('src.render.Transition')
 local function field()
  clean();Stack.states={};Stack:push(ow);ow.transitioning=false
 end
 local function held(id)
  Game:touchpressed(id,220,210)
  local radius=Touch:layout().dpad.w/3
  Game:touchmoved(id,220+radius*.65,210)
  return radius
 end
 for _,level in ipairs({3,6,7})do
  field();Pipeline.setLevel('voxel',level);Voxel.level=level
  opts.jpTouchStick=false;opts.jpAnalogWalk=false;Touch:applyOptions(opts)
  local radius=held('cross-map');ow.map={id='NEIGHBOR-'..level};Touch:validateGesture(Game)
  local mx,mz=FP.moveVector()
  check(Touch.floatingGesture and math.abs(mx-.65)<1e-6 and math.abs(mz)<1e-6,
    'held drag continues across adjacent map without another motion event '..level)
  local ready=false;ow.transitioning=true
  local transition=Transition.new(Game,function()ow.map={id='DOOR-'..level}end,
    function()ow.transitioning=false end,true,{noFade=true,ready=function()return ready end})
  Stack:push(transition);Touch:validateGesture(Game);Stack:update(1/60)
  mx,mz=FP.moveVector()
  check(Touch.floatingGesture and Stack:top()==transition and mx==0 and mz==0,
    'loading pauses movement while retaining the finger '..level)
  Game:touchmoved('cross-map',220+radius*.4,210)
  check(Touch:layout().dpad.cx==220 and #Input.pressQueue==0,
    'loading keeps floating origin and never queues a menu direction '..level)
  ready=true;Stack:update(1/60);Touch:validateGesture(Game)
  mx,mz=FP.moveVector()
  check(Touch.floatingGesture and Stack:top()==ow and math.abs(mx-.4)<1e-6 and mz==0,
    'warp completion resumes the held direction without lifting or moving again '..level)
  Game:touchreleased('cross-map',220+radius*.4,210);Input:step();mx,mz=FP.moveVector()
  check(mx==0 and mz==0 and not Input:wasPressed('a'),'release after warp stops without confirming '..level)

  field();radius=held('release-loading');ow.transitioning=true;ready=false
  transition=Transition.new(Game,function()ow.map={id='RELEASED-'..level}end,
    function()ow.transitioning=false end,true,{noFade=true,ready=function()return ready end})
  Stack:push(transition);Touch:validateGesture(Game)
  Game:touchreleased('release-loading',220+radius*.65,210)
  ready=true;Stack:update(1/60);Touch:validateGesture(Game);Input:step();mx,mz=FP.moveVector()
  check(not Touch.floatingGesture and mx==0 and mz==0 and not Input:wasPressed('a'),
    'releasing during loading prevents movement after arrival '..level)
 end

 clean();opts.jpTouchOptimized=false
end
