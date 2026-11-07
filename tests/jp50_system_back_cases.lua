-- Real Game / Options / StateStack; inject only host events and authored data.
return function(Game,host,check)
 local Input=require('src.core.Input');Input:init()
 local Touch=require('src.core.TouchControls');Touch:init()
 local Stack=require('src.core.StateStack');Stack:init()
 local Options=require('src.ui.OptionsMenu')
 local Fixed=require('src.core.FixedStep')
 local Save=require('src.core.SaveData')
 require('src.core.Sound').play=function()end
 Game.data={constants={language='ja'},screens={}}
 Game.save=Save.newGame();Game.stack,Game.input=Stack,Input
 Game.updateAudio=function()end
 Game.mods=nil;Game.overworld={}
 local root={isSystemMenuRoot=true,systemMenuPause=true}
 local parent,child,cancels,changes
 local function newChild()
  return Options.new(Game,{rows={{label='ONE',step=function()changes=changes+1;return true end},
   {label='TWO'}},onCancel=function()cancels=cancels+1 end})
 end
 local function setup()
  Game.sessionMenu=nil;Game:clearSessionInput();Stack:init();Stack:push(root)
  Game.systemMenuAccum=0;Fixed.accum=0;cancels=0;changes=0
  parent=Options.new(Game,{rows={{label='PARENT'}}});Stack:push(parent)
  child=newChild();Stack:push(child)
 end
 local function tick()Game:update(Fixed.STEP)end
 local function closedOnce(label)
  tick()
  check(Stack:top()==parent and cancels==1,label..': first gesture closes one child')
  check(not Input:isDown('b') and child.index==1 and changes==0,label..': no held B or stray selection')
  for _=1,5 do tick()end
  check(Stack:top()==parent and cancels==1,label..': no replay into parent')
 end
 local function button(key)
  Input:sourcePress(key,'late-finger');Input:sourceRelease(key,'late-finger')
 end
 for _,event in ipairs({'none','focus-true','focus-cycle','focus-before','resume','late-down','late-a','late-right','combined'})do
  setup();if event=='focus-before' then host.focus(false)end;host.back()
  if event=='focus-true' then host.focus(true)
  elseif event=='focus-cycle' then host.focus(false);host.focus(true)
  elseif event=='focus-before' then host.focus(true)
  elseif event=='resume' then host.resume()
  elseif event=='late-down' then button('down')
  elseif event=='late-a' then button('a')
  elseif event=='late-right' then button('right')
  elseif event=='combined' then host.focus(false);host.focus(true);button('down');button('a')end
  closedOnce(event)
 end
 for _,hz in ipairs({60,90,120,144})do
  setup();host.back();host.focus(true)
  local elapsed=0
  repeat Game:update(1/hz);elapsed=elapsed+1/hz until elapsed>=Fixed.STEP
  check(Stack:top()==parent and cancels==1,'one gesture survives '..hz..' Hz update cadence')
  for _=1,6 do Game:update(1/hz)end
  check(Stack:top()==parent and cancels==1,'no repeat at '..hz..' Hz')
 end
 setup();host.back();host.back();closedOnce('two commits before same tick')
 setup();host.repeatBack();tick()
 check(Stack:top()==child and cancels==0,'held/repeated native key does not navigate')
 for _,change in ipairs({'replacement','push-pop','phase','screen','overlay','clear-session','background'})do
  setup();host.back()
  if change=='replacement' then Stack:pop();child=newChild();Stack:push(child)
  elseif change=='push-pop' then Stack:push({});Stack:pop()
  elseif change=='phase' then child.phase='changed'
  elseif change=='screen' then child.screen='detail'
  elseif change=='overlay' then child.overlay={}
  elseif change=='clear-session' then Game:clearSessionInput()
  elseif change=='background' then host.visible(false);host.visible(true)end
  tick()
  check(Stack:top()==child and cancels==0,change..': old gesture cannot close a different context')
  host.back();closedOnce(change..' fresh gesture')
 end
 -- Non-paused native children use Game:step instead of the system-menu clock.
 setup();child.floatingPanel=nil;child.systemMenuPause=nil;child.systemMenuBranch=true
 parent.floatingPanel=nil;parent.systemMenuPause=nil;root.systemMenuPause=nil
 host.back();host.focus(true);button('down');Game:step(Fixed.STEP)
 check(Stack:top()==parent and cancels==1,'normal gameplay input tick commits the same owned Back')
 Game:step(Fixed.STEP)
 check(Stack:top()==parent and cancels==1,'normal gameplay input tick never repeats Back')
 root.systemMenuPause=true
 setup();host.back();tick();host.back();tick()
 check(Stack:top()==root,'successive separate gestures each return one level')
 host.back()
 check(Stack:top()==nil,'root gesture closes immediately')
 check(not Game.pendingSystemBack,'closing root leaves no deferred action')
end
