return function(Game,Renderer,check,write)
 local Input=require('src.core.Input');local Touch=require('src.core.TouchControls')
 local T=require('src.core.JapaneseTouchMode');local Stack=require('src.core.StateStack')
 local Save=require('src.core.SaveData');local Viewport=require('src.render.GameViewport')
 local Panels=require('src.battle.JapaneseBattlePanels');local Layout=require('src.ui.GameUILayout')
 local opts=Save.loadOptions();opts.jpTouchOptimized=true;opts.touchControls={enabled=true};opts.hotbar=false
 Game.save=Save.newGame({version='red_jp'});Game.save.options=opts;Game.sessionMenu=nil
 Input:init();Game.input=Input;Touch:init();Touch:ensureImages();Touch.active=true;Touch:applyOptions(opts)
 Stack:init();Game.stack=Stack;Viewport.reset();love.window.setMode(480,800)
 local ow={player={px=128,py=128,cellX=8,cellY=8,facing='up'},map={id='TEST'}}
 Game.overworld=ow;Stack:push(ow)
 local Pokemon=require('src.pokemon.Pokemon');local Battle=require('src.battle.BattleState')
 Game.save.party={Pokemon.new(Game.data,'FIXMON_A',15)}
 Game.save.party[1].moves={{id='FIX_TACKLE',pp=10},{id='FIX_SCRATCH',pp=15},{id='FIX_EMBERISH',pp=5},{id='FIX_CUT',pp=0}}
 local b=Battle.newWild(Game,'FIXMON_B',8)
 b.openParty=function(self)self.chosen='party';self.phase='messages'end
 b.openItems=function(self)self.chosen='item';self.phase='messages'end
 b.tryRun=function(self)self.chosen='run';self.phase='messages'end
 b.resolveTurn=function(self,move)self.chosen=move.id;self.phase='messages'end
 local realTime=love.timer.getTime;local clock=100;love.timer.getTime=function()return clock end
 local function clean()
  Game:cancelPointers();Touch:reset();Input:reset();Game.sessionMenu=nil
 end
 local function menu(phase)
  clean();Stack.states={ow,b};Stack.pointerRevision=Stack.pointerRevision+1
  b.phase=phase or 'menu';b.current=nil;b.queue={};b.introSlide=nil;b.jpEncounterAwaitDraw=nil
  b.chosen=nil;b.menuIndex=1;b.moveIndex=1;b.moveSwapIndex=nil
  opts.jpBattleSpacing='wide'
  Renderer.jpLayout='battle';Renderer.jpBattleState=b;Renderer.dialogScale=.75
 end
 local function geometry()
  local r=Renderer:frameRects();local p=r.battlePresentation.panels
  local x,y,_,_,sx,sy=Layout.place(r,{anchor='battlePresentation',w=p.width,h=p.height})
  local ox,oy=Viewport.rect and Viewport.rect.x or 0,Viewport.rect and Viewport.rect.y or 0
  return p,x+ox,y+oy,sx,sy
 end
 local function point(i,edge)
  local p,x,y,sx,sy=geometry();local c=Panels.cells(p,b.phase)[i]
  return x+(edge and p.command.x+p.command.w-5 or c.x+c.w/2)*sx,y+(c.y+10)*sy
 end
 local serial=0
 local function tap(x,y,dx,dy,seconds,releaseOnly)
  serial=serial+1;local id='reliable'..serial
  Game:touchpressed(id,x,y)
  clock=clock+(seconds or .12)
  if not releaseOnly then Game:touchmoved(id,x+(dx or 0),y+(dy or 0))end
  Game:touchreleased(id,x+(dx or 0),y+(dy or 0));Input:step()
 end

 menu();local x,y=point(2);tap(x,y,10,0)
 check(b.chosen=='party','small finger wobble still chooses the touched command')
 menu();x,y=point(2);tap(x,y,0,0,1.2)
 check(b.chosen=='party','deliberate held tap chooses once on release')

 for _,size in ipairs({{480,800},{800,480},{972,1536}})do
  love.window.setMode(size[1],size[2]);Viewport.reset()
  menu();x,y=point(2,true);tap(x,y)
  check(b.chosen=='party','command inner margin selects its adjacent item '..size[1])
  menu();local p,ox,oy,sx,sy=geometry();local c=Panels.cells(p,'menu')[2]
  x=ox+(p.command.x+p.command.w/2+1)*sx;y=oy+(c.y+10)*sy
  tap(x,y,-3*sx,0)
  check(b.chosen=='party','small boundary drift retains the pressed column '..size[1])
  menu('moveSelect');x,y=point(2);tap(x,y,8,5,1.1)
  check(b.chosen=='FIX_SCRATCH','move tap tolerates wobble and a deliberate hold '..size[1])
  menu();x,y=point(2);Game:touchpressed('preview',x,y)
  check(b.phase=='menu' and not b.chosen and b.menuIndex==1,'press feedback does not execute or mutate the native cursor '..size[1])
  check(T.previewBattleCell(Game,b)==2,'pressed command has immediate selection feedback '..size[1])
  Game:touchmoved('preview',x+80,y);Game:touchreleased('preview',x+80,y);Input:step()
  check(not b.chosen and Input:wasPressed('right') and not Input:wasPressed('a'),
    'intentional command swipe only moves the cursor '..size[1])
 end

 love.window.setMode(480,800);Viewport.reset();menu()
 x,y=point(2);Game:touchpressed('preview-shot',x,y)
 local p,ox,oy,sx,sy=geometry();local canvas=love.graphics.newCanvas(480,800)
 love.graphics.setCanvas(canvas);love.graphics.clear(.16,.22,.18,1)
 love.graphics.push();love.graphics.translate(ox,oy);love.graphics.scale(sx,sy);Panels.draw(b,p)
 love.graphics.pop();love.graphics.setCanvas()
 write('pressed-command-feedback.png',canvas:newImageData():encode('png'):getString());canvas:release()
 Game:touchreleased('preview-shot',x,y)

 menu();x,y=point(1);tap(x,y);local nx,ny=point(2);tap(nx,ny)
 check(b.chosen=='FIX_SCRATCH','consecutive deliberate taps choose command then move without cooldown')
 menu();x,y=point(2);Game:touchpressed('stale-phase',x,y);b.phase='moveSelect'
 Game:touchreleased('stale-phase',x,y)
 check(not b.chosen and b.phase=='moveSelect','phase change never reuses a pressed command')
 menu();x,y=point(2);Game:touchpressed('stale-layout',x,y);opts.jpBattleSpacing='normal'
 Game:touchreleased('stale-layout',x,y);Input:step()
 check(not b.chosen and not Input:wasPressed('a'),'changed UI geometry cancels a pending command')
 menu();x,y=point(2);Game:touchpressed('stale-viewport',x,y)
 Viewport.rect={x=20,y=10,width=440,height=780}
 Game:touchreleased('stale-viewport',x,y);Input:step()
 check(not b.chosen and not Input:wasPressed('a'),'moved viewport cancels a pending command')
 Viewport.reset()
 menu();b.jpEncounterAwaitDraw=true;tap(10,250)
 check(not Input:wasPressed('a'),'hidden command panel cannot enqueue a confirm');b.jpEncounterAwaitDraw=nil

 menu('moveSelect');x,y=point(2);Game:touchpressed('changed-move',x,y)
 local before=b.player.curMoves[2];b.player.curMoves[2]={id='FIX_TACKLE',pp=10}
 Game:touchreleased('changed-move',x,y)
 check(not b.chosen,'replaced move record cannot reuse the held command');b.player.curMoves[2]=before
 menu('moveSelect');p,ox,oy,sx,sy=geometry()
 local bounds=Panels.touchCells(p,'moveSelect')
 check(bounds[3].y+bounds[3].h<=p.command.y+(p.compact and 36 or 44),
   'larger move targets do not cover the PP and type description')
 menu('moveSelect');local fourth=b.player.curMoves[4];b.player.curMoves[4]=nil
 x,y=point(4);tap(x,y,10,0,1.1)
 check(not b.chosen and not Input:wasPressed('a'),'wobbly held tap on empty move never chooses another slot')
 b.player.curMoves[4]=fourth
 menu();x,y=point(2);Game:touchpressed('long-first',x,y);Game:touchpressed('long-second',x,y)
 clock=clock+1.2;Game:touchreleased('long-first',x,y);Game:touchreleased('long-second',x,y);Input:step()
 check(b.chosen=='party' and not Input:wasPressed('a'),'two held fingers produce only one command')

 -- jp.49 keeps the modern JP composition under the exact-pixel preference.
 -- Tap the same final placement used by the renderer (the old letterbox
 -- calculation here codified the lower HUD placement being corrected).
 local Faithful=require('src.core.FaithfulRes')
 Faithful.apply(1);menu()
 local native=Renderer:frameRects()
 local m=require('src.battle.BattlePresentation').metrics(native);p=m.panels
 local ux,uy,_,_,usx,usy=require('src.ui.GameUILayout').place(native,
   {anchor='battlePresentation',w=p.width,h=p.height})
 local c=Panels.cells(p,'menu')[2]
 x,y=ux+(c.x+c.w/2)*usx,uy+(c.y+10)*usy
 check(x>=0 and x<480 and y>=0 and y<800,'exact-pixel test taps a visible command')
 tap(x,y)
 check(b.chosen=='party','exact-pixel display follows its actual command placement')
 Faithful.apply(0)

 clean();Stack.states={ow};Renderer.jpLayout=nil;Renderer.jpBattleState=nil
 local Options=require('src.ui.OptionsMenu');local calls=0
 local custom={rows={{label='ONE',activate=function()calls=calls+1 end},
  {label='TWO',activate=function()calls=calls+10 end}},index=1}
 Options.adaptRegisteredState(custom,Game);Stack:push(custom);custom:drawWindowOverlay()
 local panel=custom.windowPanel;local l=panel:layout();local hit=l.hits[2];local v=l.viewport
 x=v.x+(hit.x+hit.w/2)*v.sx;y=v.y+(hit.y+hit.h/2)*v.sy
 tap(x,y,10,0,1.0)
 check(calls==10,'floating menu row accepts wobble and deliberate hold')
 Game:touchpressed('row-boundary',x,v.y+(hit.y+1)*v.sy)
 Game:touchreleased('row-boundary',x,v.y+(hit.y-1)*v.sy)
 check(calls==20,'floating row keeps its pressed target across tiny boundary drift')
 custom:drawWindowOverlay();l=panel:layout();hit=l.hits[2];v=l.viewport
 x=v.x+(hit.x+hit.w/2)*v.sx;y=v.y+(hit.y+hit.h/2)*v.sy
 Game:touchpressed('settings-preview',x,y)
 check(panel.pointer and panel:validTouch(panel.pointer,panel:layout()),'pressed setting retains its input context before draw')
 canvas=love.graphics.newCanvas(480,800);love.graphics.setCanvas(canvas);love.graphics.clear(.16,.22,.18,1)
 custom:drawWindowOverlay();love.graphics.setCanvas()
 check(panel.pointer and panel:validTouch(panel.pointer,panel:layout()),'pressed setting retains its input context after draw')
 local pixels=canvas:newImageData()
 local shade=pixels:getPixel(math.floor(v.x+(hit.x+hit.w/2)*v.sx),math.floor(v.y+(hit.y+2)*v.sy))
 check(shade>.1 and shade<.95,'pressed setting row visibly highlights before release')
 pixels:release()
 write('pressed-settings-feedback.png',canvas:newImageData():encode('png'):getString());canvas:release()
 Game:cancelPointers();Game:touchreleased('settings-preview',x,y)
 check(calls==20,'cancelled pressed-row feedback never executes a setting')

 -- The previous tap/swipe dead band also swallowed diagonal releases.
 clean();Stack.states={ow};local chosen
 local list=require('src.ui.Menu').new(Game,{{label='ONE',onSelect=function()chosen=1 end},
  {label='TWO',onSelect=function()chosen=2 end}},{noSound=true})
 Stack:push(list);local slop=T.stamp(Game,240,350).slop
 tap(240,350,slop*.8,slop*.9,.12,true)
 check(Input:wasPressed('down') and not Input:wasPressed('a') and not chosen,
   'diagonal release beyond tap tolerance is a cursor gesture without a dead band')
 clean();love.timer.getTime=realTime;opts.jpTouchOptimized=false
end
