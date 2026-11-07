return function(Game,Renderer,check,write)
 local Input=require('src.core.Input');local Touch=require('src.core.TouchControls')
 local T=require('src.core.JapaneseTouchMode');local Stack=require('src.core.StateStack')
 local Save=require('src.core.SaveData');local V=Game.mods.exports.DRAMALESS_SHAPE.lib
 local FP=V.require('FirstPerson');local Voxel=V.require('VoxelState')
 local Pipeline=require('src.render.Pipelines');local Viewport=require('src.render.GameViewport')
 local opts=Save.loadOptions();opts.jpTouchOptimized=true;opts.jpTouchStick=false
 opts.jpAnalogWalk=false;opts.touchControls={enabled=true};opts.hotbar=false
 Game.save=Save.newGame({version='red_jp'});Game.save.options=opts;Game.sessionMenu=nil
 Input:init();Game.input=Input;Touch:init();Touch:ensureImages();Touch.active=true;Touch:applyOptions(opts)
 Stack:init();Game.stack=Stack
 local state={player={px=128,py=128,cellX=8,cellY=8,facing='up'},map={id='TEST'}}
 Game.overworld=state;Stack:push(state);Viewport.reset()
 love.window.setMode(480,800)
 local function clean()Game:cancelPointers();Touch:reset();Input:reset()end
 local function neutral()
  local x,z=FP.moveVector();return math.abs(x)+math.abs(z)<1e-8
 end
 for _,level in ipairs({3,6,7})do
  clean();Pipeline.setLevel('voxel',level);Voxel.level=level
  local x,y=220,210
  Game:touchpressed('drag',x,y)
  check(Touch.floatingGesture and Touch:layout().dpad.cx==x and Touch:layout().dpad.cy==y,'camera '..level..' creates pad at finger origin')
  check(neutral(),'camera '..level..' press begins neutral')
  local radius=Touch:layout().dpad.w/3
  Game:touchmoved('drag',x+radius*.5,y+radius*.2)
  local mx,mz=FP.moveVector()
  check(math.abs(mx-.5)<1e-6 and math.abs(mz+.2)<1e-6,'camera '..level..' installed renderer receives arbitrary analog angle and strength')
  local pad=T.navigation()[1];local bx,by=pad.x+pad.w/2,pad.y+pad.h/2
  Game:touchpressed('button',bx,by);Game:touchreleased('button',bx,by);Input:step()
  check(Input:wasPressed('b') and not Input:isDown('b'),'camera '..level..' custom Back supplies native B with another finger')
  Game:touchmoved('drag',x,y);Game:touchreleased('drag',x,y);Input:step()
  check(neutral() and not Input:wasPressed('a') and not Touch.floatingGesture,'camera '..level..' returned drag ends without confirm or residual motion')
  clean();Game:touchpressed('tap',x,y);Game:touchreleased('tap',x,y);Input:step()
  check(Input:wasPressed('a') and not Input:isDown('a'),'camera '..level..' short tap emits one confirm edge')
  Input:step();check(not Input:wasPressed('a'),'camera '..level..' confirm is not repeated')
  clean();Game:touchpressed('cancel',x,y);Game:touchmoved('cancel',x+radius,y)
  Game:cancelPointers();Game:touchreleased('cancel',x+radius,y);Input:step()
  check(neutral() and not Input:isDown('right') and not Input:wasPressed('right') and not Input:wasPressed('a'),'camera '..level..' cancellation drops analog and queued digital movement')
 end
 clean();Pipeline.setLevel('voxel',3);Voxel.level=3
 Game:touchpressed('transition',220,210);Game:touchmoved('transition',270,210)
 Stack:push({});Stack:pop();Touch:validateGesture(Game)
 Game:touchreleased('transition',220,210);Input:step()
 check(neutral() and not Input:wasPressed('a'),'push/pop of a dialogue invalidates an old field gesture')
 clean();Game:touchpressed('map',220,210);state.map={id='OTHER'};Touch:validateGesture(Game)
 Game:touchreleased('map',220,210);Input:step()
 check(not Touch.floatingGesture and not Input:wasPressed('a'),'map handoff invalidates the old tap')
 clean();Game:touchpressed('rotate',220,210);love.window.setMode(800,480);Touch:validateGesture(Game)
 Game:touchreleased('rotate',220,210);Input:step()
 check(not Touch.floatingGesture and not Input:wasPressed('a'),'rotation cancels stale movement')
 clean();opts.jpTouchOptimized=false
 Game:touchpressed('off',400,100)
 check(not Touch.floatingGesture and not Game.jpTapPointers,'OFF keeps original controls and pointer ownership')
 Game:touchreleased('off',400,100);clean();opts.jpTouchOptimized=true
 local pref=require('src.ui.JapaneseConvenienceSettings');local row
 for _,r in ipairs(pref.rows)do if r.id=='jpTouchOptimized' then row=r end end
 check(row and require('src.ui.JapaneseSettingsCatalog').group(row.id)=='controls','touch mode is in the shared Controls settings')
 local config={jpTouchOptimized=true};pref.step(row,config,1)
 check(config.jpTouchOptimized=='buttons','mode cycles to visible A/B')
 pref.step(row,config,1);check(config.jpTouchOptimized==false,'mode can be switched off')
 local Settings=require('src.import.SettingsTransfer')
 local restored=assert(Settings.import(assert(Settings.export(opts)),Save.defaultOptions()))
 check(restored.jpTouchOptimized==true,'touch preference survives a settings/backup round trip')
 -- No invisible legacy buttons intercept direct taps or reserve the page.
 -- Menu gestures still use the real native Menu.
 clean();local Menu=require('src.ui.Menu');local selected
 local menu=Menu.new(Game,{{label='ONE',onSelect=function()selected=1 end},
  {label='TWO',onSelect=function()selected=2 end}},{noSound=true})
 Stack:push(menu)
 local old=Touch:layout().b
 check(Touch:hitTest(old.cx,old.cy)==nil,'removed B has no invisible hit target')
 local bounds=require('src.ui.GameUILayout').touchBounds()
 check(#bounds==0,'native commands are in the window and reserve no screen-edge strip')
 Game:touchpressed('swipe',200,160);Game:touchmoved('swipe',200,240)
 Game:touchreleased('swipe',200,240);Input:step();menu:update(1/60)
 check(menu.index==2 and not selected,'swipe moves native cursor without confirming')
 Game:touchpressed('choose',200,160);Game:touchreleased('choose',200,160)
 Input:step();menu:update(1/60)
 check(selected==2 and Stack:top()==state,'tap confirms native cursor selection')
 clean();local nav=T.navigation()[2];local nx,ny=nav.x+nav.w/2,nav.y+nav.h/2
 Game:touchpressed('menu-drag',nx,ny);Game:touchmoved('menu-drag',nx,ny+80)
 Game:touchreleased('menu-drag',nx,ny)
 check(not Game.sessionMenu,'dragging away from custom navigation cancels action')
 Game:touchpressed('menu',nx,ny);Game:touchreleased('menu',nx,ny)
 check(Game.sessionMenu and Game.sessionMenu.page=='touch' and not Touch.floatingGesture,'custom Menu opens paused actions and cancels field motion')
 local sheet=Game.sessionMenu;local l=sheet:layout();local selectHit
 for _,h in ipairs(l.hits)do if h.id=='touch-select' then selectHit=h end end
 -- Obtain screen coordinates from the same transform the sheet draws.
 local v=l.viewport
 local sx,sy=v.x+(selectHit.x+selectHit.w/2)*v.sx,v.y+(selectHit.y+selectHit.h/2)*v.sy
 Game:touchpressed('select',sx,sy);Game:touchreleased('select',sx,sy);Input:step()
 check(not Game.sessionMenu and Input:wasPressed('select') and Stack:top()==state,'SELECT action reaches the original state after closing the sheet')
 clean();Game:touchpressed('reopen',nx,ny);Game:touchreleased('reopen',nx,ny)
 local back=T.navigation()[1];local bx,by=back.x+back.w/2,back.y+back.h/2
 Game:touchpressed('close',bx,by);Game:touchreleased('close',bx,by);Input:step()
 check(not Game.sessionMenu and not Input:wasPressed('b'),'custom Back closes the sheet without leaking B to gameplay')
 -- Real battle semantics, with only the downstream turn/party/bag replaced.
 local Pokemon=require('src.pokemon.Pokemon');local Battle=require('src.battle.BattleState')
 Game.save.party={Pokemon.new(Game.data,'FIXMON_A',15)}
 local mon=Game.save.party[1]
 mon.moves={{id='FIX_TACKLE',pp=10},{id='FIX_SCRATCH',pp=15},{id='FIX_EMBERISH',pp=5},{id='FIX_CUT',pp=0}}
 local b=Battle.newWild(Game,'FIXMON_B',8)
 Stack.states={state,b};Stack.pointerRevision=Stack.pointerRevision+1
 b.phase='menu';b.queue={};b.introSlide=nil;b.jpEncounterAwaitDraw=nil
 b.openParty=function(self)self.chosen='party';self.phase='messages'end
 b.openItems=function(self)self.chosen='item';self.phase='messages'end
 b.tryRun=function(self)self.chosen='run';self.phase='messages'end
 b.resolveTurn=function(self,move)self.chosen=move.id;self.phase='messages'end
 Renderer.jpLayout='battle';Renderer.jpBattleState=b;Renderer.dialogScale=.75
 local Panels=require('src.battle.JapaneseBattlePanels')
 local function point(index)
  local m=Renderer:frameRects().battlePresentation;local p=m.panels or m
  local c=Panels.cells(p,b.phase)[index]
  return p.x+(c.x+c.w/2)*p.sx,p.y+(c.y+c.h/2)*p.sy,p
 end
 local function tap(index)
  local x,y=point(index)
  Game:touchpressed('command',x,y);Game:mousepressed(x,y,1,true)
  Game:touchreleased('command',x,y);Game:mousereleased(x,y,1,true)
 end
 for _,size in ipairs({{480,800},{800,480}})do
  love.window.setMode(size[1],size[2]);Viewport.reset();clean()
  for i,expected in ipairs({'fight','party','item','run'})do
   b.phase='menu';b.chosen=nil;tap(i)
   check(i==1 and b.phase=='moveSelect' or b.chosen==expected,'direct native '..expected..' command '..size[1])
  end
  b.phase='moveSelect';b.chosen=nil;tap(2)
  check(b.chosen=='FIX_SCRATCH','direct move selection uses native turn path '..size[1])
  b.phase='moveSelect';b.chosen=nil;tap(4)
  check(not b.chosen and b.phase=='messages','direct tap respects zero PP '..size[1])
  b.phase='moveSelect';b.chosen=nil;b.player.disabledSlot=2;tap(2)
  check(not b.chosen and b.phase=='messages','direct tap respects Disable '..size[1]);b.player.disabledSlot=nil
  b.phase='menu';b.chosen=nil
  local x,y,p=point(1);Game:touchpressed('drag-command',x,y);Game:touchmoved('drag-command',x+40,y)
  Game:touchreleased('drag-command',x,y)
  check(b.phase=='menu' and not b.chosen,'drag across a command never confirms '..size[1])
  Game:touchpressed('stale-command',x,y);b.phase='moveSelect';Game:touchreleased('stale-command',x,y)
  check(b.phase=='moveSelect' and not b.chosen,'phase change cancels old command tap '..size[1])
  b.phase='menu';local c=love.graphics.newCanvas(size[1],size[2]);love.graphics.setCanvas(c)
  love.graphics.clear(.16,.22,.18,1);love.graphics.push();love.graphics.translate(p.x,p.y)
  love.graphics.scale(p.sx,p.sy);Panels.draw(b,p);love.graphics.pop();Touch:draw();love.graphics.setCanvas()
  write('touch-battle-'..size[1]..'x'..size[2]..'.png',c:newImageData():encode('png'):getString());c:release()
 end
 clean();b.phase='menu';local x,y=point(1)
 Game:touchpressed('multiple1',x,y);Game:touchpressed('multiple2',x,y)
 Game:touchreleased('multiple1',x,y);Game:touchreleased('multiple2',x,y)
 check(b.phase=='moveSelect' and not Input:isDown('a'),'two fingers cannot choose a command and a move in one gesture')
 clean();Stack.states={state,{phase='text'}};Stack.pointerRevision=Stack.pointerRevision+1
 Game:touchpressed('dialogue',400,100);Game:touchreleased('dialogue',400,100);Input:step()
 check(Input:wasPressed('a'),'short dialogue tap follows native confirm input')
 clean();opts.jpTouchOptimized=false;Renderer.jpLayout=nil;Renderer.jpBattleState=nil
end
