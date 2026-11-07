-- Real Game/Options/SessionMenu, with authored field data and host event seams.
return function(Game,host,check)
 local Input=require('src.core.Input');local Touch=require('src.core.TouchControls')
 local Stack=require('src.core.StateStack');local Save=require('src.core.SaveData')
 local T=require('src.core.JapaneseTouchMode');local Options=require('src.ui.OptionsMenu')
 local Panel=require('src.ui.SessionMenu');local Fixed=require('src.core.FixedStep')
 require('src.core.Sound').play=function()end
 local field,confirms,changes,root,parent,child
 local function setup()
  Game.sessionMenu=nil;Game:clearSessionInput();Stack:init();Input:init();Touch:init()
  Game.data={constants={language='ja'},screens={}};Game.save=Save.newGame({version='red_jp'})
  local o=Game.save.options;o.jpTouchOptimized=true;o.hotbar=false;o.touchControls={enabled=true}
  Game.stack=Stack;Game.input=Input;Game.mods=nil;Game.linkSession=nil;Game.linkNet=nil
  Game.updateAudio=function()end;Game.writeOptions=function()return true end
  Game.systemMenuAccum=0;Fixed.accum=0;confirms=0;changes=0
  Fixed.callback=function(dt)Game:step(dt)end
  Touch:ensureImages();Touch.active=true;Touch:applyOptions(o)
  require('src.render.GameViewport').reset()
  field={map={id='CANCEL_FIXTURE'},player={moving=false},update=function(self)
   if Input:wasPressed('a')then confirms=confirms+1;T.emptyFieldTap(Game,self)end
  end}
  Game.overworld=field;Stack:push(field)
 end
 local function tick()Game:update(Fixed.STEP)end
 local function press(x,y,id)host.press(id or 'edge',x or 220,y or 210)end
 local function cancel(x,y,id)host.release(id or 'edge',x or 220,y or 210,-1)end
 local function release(x,y,id)host.release(id or 'edge',x or 220,y or 210,0)end
 local function childSetup()
  setup();root={isSystemMenuRoot=true,systemMenuPause=true};Stack:push(root)
  parent=Options.new(Game,{rows={{label='PARENT'}}});Stack:push(parent)
  child=Options.new(Game,{rows={{label='VALUE',step=function(_,d)changes=changes+d;return true end}}})
  Stack:push(child)
  -- Use the real floating panel and its release-time row stepping. Rendering
  -- is not needed to test a gesture that starts on an actionable setting.
  local panel=Panel.new(Game,'options');child.windowPanel=panel
  panel.rows=function()return {{id='value',label='VALUE',value='1',step=function(d)changes=changes+d end}}end
  local l=panel:layout();local hit=l.hits[2];local v=l.viewport
  return v.x+(hit.x+hit.w*.5)*v.sx,v.y+(hit.y+hit.h*.5)*v.sy
 end
 for _,order in ipairs({'cancel-first','back-first','tick-between','focus-between'})do
  setup();press()
  if order=='back-first'then host.back();cancel()
  else
   cancel()
   if order=='tick-between'then tick()end
   if order=='focus-between'then host.focus(false);host.focus(true)end
   host.back()
  end
  tick();check(confirms==0,order..': cancelled edge never confirms field A')
  check(Stack:top()~=field and Stack:top().isSystemMenuRoot,order..': one Back opens menu exactly once')
  check(not Game.jpFieldTapPending and not Touch.floatingGesture,order..': no old field gesture remains')
  for _=1,3 do tick()end
  check(Stack:top().isSystemMenuRoot,order..': no late menu toggle')
  local x,y=childSetup();press(x,y)
  if order=='back-first'then host.back();cancel(x,y)
  else
   cancel(x,y);if order=='tick-between'then tick()end
   if order=='focus-between'then host.focus(false);host.focus(true)end
   host.back()
  end
  tick();check(Stack:top()==parent,order..': child Back returns one level')
  check(changes==0,order..': cancelled contact never changes a setting')
  check(child.windowPanel.pointer==nil,order..': cancelled highlight is cleared')
  for _=1,3 do tick()end
  check(Stack:top()==parent,order..': no second Back into root')
 end
 setup();press();cancel();tick()
 check(Stack:top()==field and confirms==0,'abandoned system gesture does not navigate or confirm')
 press();release();tick()
 check(confirms==1 and Stack:top().isSystemMenuRoot,'next ordinary tap works immediately without a cooldown')
 local x,y=childSetup();press(x,y);cancel(x,y);release(x,y);tick()
 check(changes==0 and Stack:top()==child,'late ordinary release after cancellation cannot act')
 press(x,y);release(x,y);tick()
 check(changes==1,'next real setting tap changes the value once')
 setup();press();host.move('edge',280,210);cancel(280,210);tick()
 check(confirms==0 and not Touch.floatingGesture and not Input:isDown('right'),'cancelled drag releases movement without a flick or tap')
 setup();press();press(310,210,'other');cancel();cancel(310,210,'other');host.back();tick()
 check(confirms==0 and Stack:top().isSystemMenuRoot,'multi-touch cancellation still permits only one Back action')
 setup();local dialog={update=function()if Input:wasPressed('a')then confirms=confirms+1 end end};Stack:push(dialog)
 press();cancel();tick()
 check(confirms==0 and Stack:top()==dialog,'cancelled dialogue tap never advances text')
 press();release();tick()
 check(confirms==1,'ordinary dialogue tap still advances text once')
 Game:clearSessionInput()
end
