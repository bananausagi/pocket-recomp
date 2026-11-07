-- Production Game:draw, renderer placement, pointer routing and native menus.
-- Synthetic data/font only; no ROM and no claim of physical Android testing.
return function(Game,Renderer,check,write)
 local g=love.graphics
 local Input=require('src.core.Input');local Touch=require('src.core.TouchControls')
 local T=require('src.core.JapaneseTouchMode');local H=require('src.ui.JapaneseTouchTargets')
 local Stack=require('src.core.StateStack');local Save=require('src.core.SaveData')
 local Viewport=require('src.render.GameViewport');local Areas=require('src.core.JapaneseTouchAreas')
 local Pokemon=require('src.pokemon.Pokemon');local Windows=require('src.ui.FloatingGameWindow')
 local opts=Save.loadOptions();opts.jpTouchOptimized='buttons';opts.jpTouchAreas=Areas.normalize()
 opts.touchControls={enabled=true};opts.jpDialogScale=.75;opts.hotbar=false
 Game.save=Save.newGame({version='red_jp'});Game.save.options=opts;Game.sessionMenu=nil
 Game.save.party={Pokemon.new(Game.data,'FIXMON_A',15),Pokemon.new(Game.data,'FIXMON_B',8)}
 Game.save.party[1].moves={{id='FIX_TACKLE',pp=10},{id='FIX_SCRATCH',pp=15},{id='FIX_EMBERISH',pp=5},{id='FIX_CUT',pp=3}}
 Game.save.pokedex={seen={FIXMON_A=true,FIXMON_B=true},owned={FIXMON_A=true}}
 Input:init();Game.input=Input;Touch:init();Touch:ensureImages();Touch.active=true;Touch:applyOptions(opts)
 Stack:init();Game.stack=Stack;Viewport.reset()
 require('src.render.DotMatrix').setLevel(0)
 local ow={isOpaque=true,isOverworld=true,map={id='TEST'},player={px=128,py=128,cellX=8,cellY=8,facing='up'}}
 function ow:draw()g.clear(.18,.27,.30,1)end
 Game.overworld=ow
 local serial=0;local geometry={};local output
 local function clean()
  Game:cancelPointers();Touch:reset();Input:reset();Game.sessionMenu=nil
 end
 local function put(state)
  clean();Windows.release();Stack.states={ow};Stack:push(state)
  return state
 end
 local function draw(label)
  local w,h=g.getDimensions()
  if output then output:release()end
  output=g.newCanvas(w,h)
  Viewport.setOutputTarget(output);g.setCanvas(output);g.clear(.12,.16,.20,1)
  Game:draw();g.setCanvas();Viewport.setOutputTarget(nil)
  local f=assert(H.frameFor(Game),'active touch frame '..tostring(label))
  for _,t in ipairs(f.targets)do
   check(t.x>=0 and t.y>=0 and t.x+t.w<=w+.1 and t.y+t.h<=h+.1,'target fits '..t.id..' '..tostring(label))
  end
  if label then
   write(label..'.png',output:newImageData():encode('png'):getString())
   local rects={};for _,t in ipairs(f.targets)do rects[#rects+1]={id=t.id,x=t.x,y=t.y,w=t.w,h=t.h}end
   geometry[#geometry+1]={screen=label,targets=rects}
  end
  return f
 end
 local function target(id)
  for _,t in ipairs(assert(H.frameFor(Game)).targets)do if t.id==id then return t end end
  error('missing visible target '..id)
 end
 local function point(t)return t.x+t.w/2,t.y+t.h/2 end
 local function tick()
  if not Game.sessionMenu then Game:step(1/60)end
 end
 local function tap(id)
  local x,y=point(target(id));serial=serial+1
  Game:touchpressed(serial,x,y);Game:touchreleased(serial,x,y);tick()
 end
 local function key(k)Input:reset();T.key(k);Input:step();Stack:update(1/60)end
 local Settings=require('src.ui.JapaneseConvenienceSettings');local row
 for _,r in ipairs(Settings.rows)do if r.id=='jpTouchOptimized'then row=r end end
 local config={jpTouchOptimized=false};Settings.step(row,config,1)
 check(config.jpTouchOptimized==true,'old gesture mode remains a separate choice')
 Settings.step(row,config,1);check(config.jpTouchOptimized=='buttons','A/B choice is available')
 assert(Save.saveOptions(opts));check(Save.loadOptions().jpTouchOptimized=='buttons','A/B choice survives disk reload')
 local Transfer=require('src.import.SettingsTransfer')
 check(assert(Transfer.import(assert(Transfer.export(opts)),Save.defaultOptions())).jpTouchOptimized=='buttons','A/B preference survives backup/import')
 for _,size in ipairs({{480,800},{800,480},{972,1536}})do
  love.window.setMode(size[1],size[2],{vsync=0});Viewport.reset();clean();Stack.states={ow}
  local suffix=size[1]..'x'..size[2]
  local x,y=size[1]*.22,size[2]*.5
  Game:touchpressed('stick',x,y);Game:touchmoved('stick',x+40,y-20)
  check(Touch.floatingGesture and Touch.floatingGesture.x==x,'left finger becomes floating stick '..suffix)
  local a,b=Touch:layout().a,Touch:layout().b
  Game:touchpressed('a',a.cx,a.cy);Input:step()
  check(Input:wasPressed('a') and Touch.floatingGesture~=nil,'A works simultaneously with left stick '..suffix)
  Game:touchreleased('a',a.cx,a.cy);Game:touchpressed('b',b.cx,b.cy);Input:step()
  check(Input:isDown('b') and Touch.floatingGesture~=nil,'B can be held with left stick '..suffix)
  Game:touchreleased('b',b.cx,b.cy);Game:touchreleased('stick',x+40,y-20);Input:step()
  check(not Input:isDown('b') and not Touch.floatingGesture,'release clears movement and B '..suffix)
  clean();Game:touchpressed('left-tap',x,y);Game:touchreleased('left-tap',x,y);Input:step()
  check(not Input:wasPressed('a') and not Game.jpFieldTapPending,'left stick tap does not confirm '..suffix)
  clean();Game:touchpressed('right-space',size[1]*.73,size[2]*.3)
  check(not Touch.floatingGesture,'right blank space never becomes a movement stick '..suffix)
  Game:touchreleased('right-space',size[1]*.73,size[2]*.3);Input:step()
  check(Game.jpFieldTapPending~=nil,'right blank tap retains inspect/empty-menu path '..suffix)
  clean();Game:touchpressed('mode-change',x,y);opts.jpTouchOptimized=true
  Game:touchreleased('mode-change',x,y);Input:step()
  check(not Input:wasPressed('a'),'mode change cancels held gesture '..suffix);opts.jpTouchOptimized='buttons'
  -- jp.59: the A/B mode also shows and presses START and SELECT.
  clean()
  for _,name in ipairs({'start','select'})do
   local z=Touch:layout()[name]
   check(Touch:hitTest(z.cx,z.cy)==name,'A/B mode hit-tests '..name..' '..suffix)
   Game:touchpressed('p-'..name,z.cx,z.cy);Input:step()
   check(Input:isDown(name) and not Touch.floatingGesture,'A/B mode presses '..name..' without starting the stick '..suffix)
   Game:touchreleased('p-'..name,z.cx,z.cy);Input:step()
   check(not Input:isDown(name),'A/B mode releases '..name..' '..suffix)
  end
  check(#require('src.ui.GameUILayout').touchBounds()==4,'A/B mode reserves A, B, START and SELECT '..suffix)
  local selected
  local Menu=require('src.ui.Menu')
  local menu=put(Menu.new(Game,{{label='どうぐ',onSelect=function()selected=1 end},{label='ポケモン',onSelect=function()selected=2 end}}, {anchor='topright',noSound=true}))
  draw('ab-menu-'..suffix);tap('row-2')
  check(selected==2 and Stack:top()==ow,'tap chooses drawn second row not cursor '..suffix)
  menu=put(Menu.new(Game,{{label='はい',onSelect=function()selected=3 end},{label='いいえ',onSelect=function()selected=4 end}},{noSound=true}))
  draw();tap('action-back');check(Stack:top()==ow,'visible back closes native window '..suffix)
  local Choice=require('src.ui.ChoiceBox');local answered
  local choice=put(Choice.new(Game,function(v)answered=v end,{noSound=true,anchor='bottom'}))
  draw('yes-no-'..suffix);tap('choice-2')
  check(choice.pending==false and choice.index==2,'NO uses native held-confirmation path '..suffix)
  for _=1,20 do Input:step();Stack:update(1/60)end
  check(answered==false and Stack:top()==ow,'NO callback runs after native hold '..suffix)
  local List=require('src.ui.ListMenu');selected=nil
  local list=put(List.new(Game,'ITEMS',{{label='キズぐすり',count=3},{label='どくけし',count=2}},{onChoose=function(it)selected=it.label end,itemBox=true}))
  draw('bag-'..suffix);tap('item-2')
  check(selected=='どくけし','bag directly chooses tapped item '..suffix)
  local party=put(require('src.ui.PartyMenu').new(Game));draw('party-'..suffix);tap('party-2')
  check(party.index==2 and party.submenu,'party tap opens tapped Pokemon actions '..suffix)
  draw('party-actions-'..suffix);tap('action-back')
  check(not party.submenu and Stack:top()==party,'back closes party submenu only '..suffix)
  local move
  local moves=put(require('src.ui.MoveSelectMenu').new(Game,Game.save.party[1],'わざを えらぶ',function(i)move=i end))
  draw('moves-'..suffix);tap('move-2');check(move==2,'move list chooses second move '..suffix)
  local qty
  local box=put(require('src.ui.QuantityBox').new(Game,{max=10,start=4,onDone=function(v)qty=v end}))
  draw('quantity-'..suffix);tap('action-more');check(box.qty==5,'visible quantity plus increments '..suffix)
  draw();tap('action-less');check(box.qty==4,'visible quantity minus decrements '..suffix)
  draw();tap('action-done');check(qty==4 and Stack:top()==ow,'quantity confirm returns selected amount '..suffix)
  local name=put(require('src.ui.NamingScreen').new(Game));draw('name-'..suffix);tap('letter-2-2')
  check(name.glyphs[1]=='き','name grid taps select actual character '..suffix)
  draw();tap('action-back');check(#name.glyphs==0,'name backspace deletes without leaving name entry '..suffix)
  local chosen
  local entries={};for i=1,12 do entries[i]={label='ITEM '..i,onSelect=function()chosen=i end} end
  local scrolled=put(Menu.new(Game,entries,{maxVisible=4,noSound=true}));scrolled.index=9;scrolled:clampScroll()
  draw('scroll-'..suffix);tap('row-8');check(chosen==8,'scrolled list selects absolute tapped index '..suffix)
  -- jp.58: a full Japanese START menu (10 rows) keeps its bottom border and
  -- its まえ／つぎ／もどる rows inside the 18-tile canvas.
  do
   Game.save.flags=Game.save.flags or {};Game.save.flags.EVENT_GOT_POKEDEX=true
   local status=Game.modStatus;Game.modStatus={available={{id='FIX'}}};Game.startMenuIndex=1
   local start=put(require('src.ui.StartMenu').new(Game));draw('start-menu-'..suffix)
   Game.modStatus=status
   check(#start.items>=10,'fixture START menu has every Japanese row '..suffix)
   check(start.ty+start.th+4<=require('src.render.Renderer').HEIGHT/8,'START menu, page and back rows fit the canvas '..suffix)
   check(target('action-back') and target('action-next'),'START menu back and page rows are drawn targets '..suffix)
   local first=start.scroll;tap('action-next')
   check(start.scroll>first and Stack:top()==start,'START menu next page stays open '..suffix)
   draw();tap('action-back');check(Stack:top()==ow,'START menu back closes it '..suffix)
  end
  local pokedex=put(require('src.ui.PokedexMenu').new(Game));draw('pokedex-'..suffix)
  local known
  for i,it in ipairs(pokedex.items)do if it.value and i<=pokedex:rows()then known=i;break end end
  check(known~=nil,'fixture has a visible known dex row')
  tap('dex-'..known);local side=Stack:top();check(side~=pokedex,'dex tap opens native side menu '..suffix)
  draw('dex-actions-'..suffix);tap('side-2');check(Stack:top()==side and side.index==2,'dex CRY uses keep-open native action '..suffix)
  draw();tap('action-back');check(Stack:top()==pokedex,'dex side Back returns to list '..suffix)
  local titleCalls=0
  local title=put(require('src.ui.PlayerStartMenu').new(Game,{onExit=function()titleCalls=titleCalls+1 end}))
  draw('title-menu-'..suffix);tap('row-'..#title.menu.items)
  check(titleCalls==1,'embedded title menu uses its drawn targets '..suffix)
  -- Same-object submenu replacement between press/release must invalidate it.
  draw();local mx,my=point(target('row-1'));Game:touchpressed('submenu-change',mx,my)
  title:confirmNew();Game:touchreleased('submenu-change',mx,my);tick()
  check(title.confirming and titleCalls==1,'replacing embedded menu cancels old target '..suffix)
  local summary=put(require('src.ui.SummaryMenu').new(Game,Game.save.party[1]));summary.whiteHold=0
  draw('summary-'..suffix);tap('action-page');check(summary.page==2,'visible page action advances summary '..suffix)
  local town=put(require('src.ui.TownMap').new(Game));town.bg=nil;town.mode='list'
  town.locs={{name='マサラ',x=1,y=1},{name='トキワ',x=2,y=2}};town.sel=1
  draw('map-'..suffix);tap('place-2');check(town.sel==2,'map location tap changes native selection '..suffix)
  local card=put(require('src.ui.TrainerCard').new(Game));draw('trainer-'..suffix);tap('action-back')
  check(Stack:top()==ow,'trainer card has visible Back '..suffix)
  local Battle=require('src.battle.BattleState')
  local battle=Battle.newWild(Game,'FIXMON_B',8);battle.phase='moveSelect';battle.queue={};battle.introSlide=0;battle.jpEncounterAwaitDraw=nil
  clean();Stack.states={ow,battle};Stack.pointerRevision=Stack.pointerRevision+1
  battle.showPlayerBack=false;battle.showEnemy=false;draw('battle-moves-'..suffix);tap('action-back')
  check(battle.phase=='menu','battle move picker visible Back returns to commands '..suffix)
  local battleChoice=require('src.ui.ChoiceBox').new(Game,function()end,{noSound=true})
  Stack:push(battleChoice);draw('battle-choice-'..suffix);tap('choice-2')
  check(battleChoice.pending==false,'battle overlay choice uses rendered command canvas '..suffix)
  -- Slot betting and stop controls use the game's original stage machine.
  Game.save.coins=20
  local slot=put(require('src.ui.SlotMachine').new(Game));slot.stage='bet';slot.betIndex=0
  draw('slots-'..suffix);tap('bet-2')
  check(slot.bet==1 and Game.save.coins==19,'slot bet tap chooses displayed amount '..suffix)
  -- Window scale/rotation and input reset invalidate a pressed/queued row.
  -- Cancellation and stale-state regressions use the real Game routes.
  selected=nil;menu=put(Menu.new(Game,{{label='ONE',onSelect=function()selected=1 end},{label='TWO',onSelect=function()selected=2 end}},{noSound=true}))
  draw();local tx,ty=point(target('row-2'))
  check(not selected,'cancel test starts without selection');Game:touchpressed('cancel',tx,ty);Game:touchcancelled('cancel');tick()
  check(not selected,'Android cancelled contact cannot choose item '..suffix)
  draw();Game:touchpressed('drag',tx,ty);Game:touchmoved('drag',tx+80,ty);Game:touchreleased('drag',tx,ty);tick()
  check(not selected,'out-and-back drag cannot become an item tap '..suffix)
  clean();draw();Game:touchpressed('stale',tx,ty);Stack:push({});Stack:pop();Game:touchreleased('stale',tx,ty);tick()
  check(not selected,'push/pop invalidates old target '..suffix)
  draw();Game:touchpressed('queued',tx,ty);Game:touchreleased('queued',tx,ty);Game:cancelPointers();tick()
  check(not selected,'cancel removes queued choice before input tick '..suffix)
  -- A custom invisible area cannot steal a visible choice.
  draw();tx,ty=point(target('row-2'));local cfg=opts.jpTouchAreas[Areas.orientation(size[1],size[2])].back
  cfg.x,cfg.y=tx/size[1],ty/size[2];draw()
  check(T.navHit(tx,ty,Game)==nil,'visible menu choice wins over custom Back '..suffix)
  tap('row-2');check(selected==2,'overlapped choice executes once '..suffix)
  opts.jpTouchAreas=Areas.normalize()
  -- Existing gesture-only mode gains the same visible choices/back.
  opts.jpTouchOptimized=true;selected=nil;put(Menu.new(Game,{{label='ONE',onSelect=function()selected=1 end},{label='TWO',onSelect=function()selected=2 end}},{noSound=true}))
  draw('gestures-menu-'..suffix);tap('row-2');check(selected==2,'gesture mode also has direct row selection '..suffix)
  if os.getenv('JP_QA_TOUCH57')=='1' then
    require('tests.jp57_touch_menus')(Game,Renderer,check,write,{put=put,draw=draw,tap=tap,target=target,tick=tick,ow=ow,opts=opts,suffix=suffix})
  end
  opts.jpTouchOptimized='buttons'
 end
 clean();if output then output:release()end
 write('touch-window-targets.json',require('src.link.Json').encode({physicalAndroid=false,romUsed=false,screens=geometry}))
end
