-- Real Game input ticks, native interaction dispatch and the installed 3D
-- movement provider. World targets are authored fixtures; no ROM is needed.
return function(Game,Renderer,check)
 local Input=require('src.core.Input');local Touch=require('src.core.TouchControls')
 local Stack=require('src.core.StateStack');local T=require('src.core.JapaneseTouchMode')
 local Save=require('src.core.SaveData');local OW=require('src.world.OverworldController')
 local Actions=require('src.world.JapaneseFieldActions')
 local V=Game.mods.exports.DRAMALESS_SHAPE.lib
 local FreeMove=V.require('FreeMove');local Voxel=V.require('VoxelState')
 local Pipeline=require('src.render.Pipelines');local Viewport=require('src.render.GameViewport')
 local saved={}
 local function bind(fn,key,value)
  for i=1,100 do
   local n,v=debug.getupvalue(fn,i);if not n then break end
   if n==key then saved[#saved+1]={fn,i,v};debug.setupvalue(fn,i,value);return end
  end
  error('missing overworld upvalue '..key)
 end
 local target,talks,reads,driver,state
 bind(OW.interact,'Game',Game)
 bind(OW.interact,'mapScripts',{get=function()return {onInteract=function()return target=='script'end}end,
  talkScript=function()end})
 local oldActions=Actions.interact
 Actions.interact=function(...)if target=='fieldmove' then return true,'CUT'end;return oldActions(...)end
 local opts=Save.defaultOptions();opts.jpTouchOptimized=true;opts.jpFieldActions=false
 opts.jpTouchStick=false;opts.jpAnalogWalk=false;opts.touchControls={enabled=true};opts.hotbar=false
 local function setup(kind)
  Game.sessionMenu=nil;Game:clearSessionInput();Stack:init()
  Game.save=Save.newGame({version='red_jp'});Game.save.options=opts;Game.input=Input;Game.stack=Stack
  Game.linkSession=nil;Game.linkNet=nil;Game.systemMenuAccum=0
  Input:init();Touch:init();Touch:ensureImages();Touch.active=true;Touch:applyOptions(opts)
  love.window.setMode(480,800);Viewport.reset();Renderer.jpLayout=nil;Renderer.jpBattleState=nil
  target=nil;talks=0;reads=0;driver=kind or 'grid'
  state={map={id='JP51_EMPTY',isCounterCell=function()return false end,
    signAtCell=function()if target=='sign' then return {text='SIGN'}end end},
   player={px=128,py=128,cellX=8,cellY=8,facing='up',facingCell=function()return 8,7 end},
   interact=OW.interact,dirHeld=OW.dirHeld,
   npcAtCell=function()if target=='npc' or target=='moving-npc' then return {def={},moving=target=='moving-npc'}end end,
   talkTo=function()talks=talks+1 end,showMapText=function()reads=reads+1 end,
   tryCardKeyDoor=function()return target=='door'end,
   tryHiddenObject=function()return target=='hidden'end,
   tryBookshelf=function()return target=='bookshelf'end,
   update=function(self)
    if Input:wasPressed('a') then
     if driver=='free' then FreeMove.tick(self)else OW.handleInput(self)end
    end
   end}
  Game.overworld=state;Stack:push(state);FreeMove.drop()
  Pipeline.setLevel('voxel',3);Voxel.level=3
 end
 local function tap()
  Game:touchpressed('tap',220,210);Game:touchreleased('tap',220,210)
 end
 local function tick()Game:step(1/60)end
 local function physicalA()Input:sourcePress('a','physical');Input:sourceRelease('a','physical')end
 for _,kind in ipairs({'grid','free'})do
  setup(kind);tap();tick()
  local root=Stack:top()
  check(root~=state and root.isSystemMenuRoot and not Game.sessionMenu,kind..': empty field tap opens unified game menu')
  check(not Input:isDown('a') and not Game.jpFieldTapPending and not Game.jpFieldTapActive,kind..': menu consumes tap and leaves no deferred input')
  tick();check(Stack:top()==root,kind..': opening tap never selects a menu item')
  Game:navigateSystemMenu();tick();physicalA();tick()
  check(Stack:top()==state,kind..': later physical A on empty field does not reopen menu')
  for _,which in ipairs({'npc','moving-npc','sign','door','hidden','script','bookshelf','fieldmove'})do
   setup(kind);target=which;tap();tick()
   check(Stack:top()==state and not Game.sessionMenu,kind..': '..which..' takes priority over menu')
   if which=='npc' then check(talks==1,kind..': native talk handler runs once')end
   if which=='sign' then check(reads==1,kind..': native sign handler runs once')end
   target=nil;physicalA();tick()
   check(Stack:top()==state,kind..': handled '..which..' cannot leak menu intent to later input')
  end
  setup(kind);Game:touchpressed('drag',220,210);Game:touchmoved('drag',280,210)
  Game:touchmoved('drag',220,210);Game:touchreleased('drag',220,210);tick()
  check(Stack:top()==state and not Input:wasPressed('a'),kind..': returning drag never opens menu')
  setup(kind);Game:touchpressed('coalesced',220,210);Game:touchreleased('coalesced',280,210);tick()
  check(Stack:top()==state,kind..': release-only movement never opens menu')
  setup(kind);Game:touchpressed('long',220,210);Touch.floatingGesture.time=love.timer.getTime()-1
  Game:touchreleased('long',220,210);tick()
  check(Stack:top()==state,kind..': held finger is not a menu tap')
 end
 for _,change in ipairs({'map','push-pop','focus','input-reset','rotation','disabled','moving','locked'})do
  setup();tap()
  if change=='map' then state.map={id='OTHER',isCounterCell=state.map.isCounterCell,signAtCell=state.map.signAtCell}
  elseif change=='push-pop' then Stack:push({});Stack:pop()
  elseif change=='focus' then Game:focus(false);Game:focus(true)
  elseif change=='input-reset' then Input:reset();physicalA()
  elseif change=='rotation' then love.window.setMode(800,480)
  elseif change=='disabled' then opts.jpTouchOptimized=false
  elseif change=='moving' then state.player.moving=true
  elseif change=='locked' then state.player.inputLocked=true end
  tick();check(Stack:top()==state,change..': stale or unavailable field tap never opens menu')
  opts.jpTouchOptimized=true;state.player.moving=false;state.player.inputLocked=false
  physicalA();tick();check(Stack:top()==state,change..': no deferred menu on next A')
 end
 setup();local advances=0
 Stack:push({update=function()if Input:wasPressed('a')then advances=advances+1;Stack:pop()end end})
 tap();tick();tick()
 check(advances==1 and Stack:top()==state,'dialogue tap advances once without opening field menu')
 setup();opts.jpTouchOptimized=false;tap();tick()
 check(Stack:top()==state and not Game.jpFieldTapPending,'ordinary touch mode keeps original empty-space behavior')
 opts.jpTouchOptimized=true;Game:clearSessionInput();Actions.interact=oldActions
 for i=#saved,1,-1 do local s=saved[i];debug.setupvalue(s[1],s[2],s[3])end
end
