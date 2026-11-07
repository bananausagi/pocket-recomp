-- Replay GameActivity/SDL-produced JNI traces through the real main callbacks.
-- Android events are authored at the native test boundary, not device captures.
return function(Game,traces,host,check)
 local Input=require('src.core.Input');local Touch=require('src.core.TouchControls')
 local Stack=require('src.core.StateStack');local Save=require('src.core.SaveData')
 local T=require('src.core.JapaneseTouchMode');local Fixed=require('src.core.FixedStep')
 require('src.core.Sound').play=function()end
 for _,name in ipairs({'claimed-up-before-back','abandoned-gesture','next-real-tap','legacy-echo'})do
  Game.sessionMenu=nil;Game:clearSessionInput();Stack:init();Input:init();Touch:init()
  Game.data={constants={language='ja'},screens={}};Game.save=Save.newGame({version='red_jp'})
  local options=Game.save.options;options.jpTouchOptimized=true;options.hotbar=false;options.touchControls={enabled=true}
  Game.stack=Stack;Game.input=Input;Game.mods=nil;Game.linkSession=nil;Game.linkNet=nil
  Game.updateAudio=function()end;Game.writeOptions=function()return true end
  Game.systemMenuAccum=0;Fixed.accum=0;Fixed.callback=function(dt)Game:step(dt)end
  Touch:ensureImages();Touch.active=true;Touch:applyOptions(options);require('src.render.GameViewport').reset()
  local confirms,transitions=0,0
  local field={map={id='NATIVE_BACK'},player={moving=false},update=function(self)
   if Input:wasPressed('a')then confirms=confirms+1;T.emptyFieldTap(Game,self)end
  end}
  Game.overworld=field;Stack:push(field)
  for _,e in ipairs(assert(traces[name],name))do
   local before=Stack:top()
   if e[1]=='tick'then Game:update(Fixed.STEP)
   elseif e[1]=='keydown'then host('keypressed','escape','acback',false)
   elseif e[1]=='keyup'then host('keyreleased','escape','acback')
   elseif e[1]=='touch'then
    local action=tonumber(e[3]);local event=({[0]='touchpressed',[5]='touchpressed',[1]='touchreleased',[6]='touchreleased',[2]='touchmoved'})[action]
    assert(event,'unexpected JNI touch action');host(event,e[2],tonumber(e[4])*480,tonumber(e[5])*800,0,0,tonumber(e[6]))
   end
   if Stack:top()~=before then transitions=transitions+1 end
  end
  if name=='abandoned-gesture'then
   check(confirms==0 and Stack:top()==field and transitions==0,name..': no decision or menu change')
  elseif name=='next-real-tap'then
   check(confirms==1 and Stack:top().isSystemMenuRoot and transitions==1,name..': normal empty tap opens menu once')
  else
   check(confirms==0,name..': no extra A reaches field')
   check(Stack:top().isSystemMenuRoot and transitions==1,name..': menu changes exactly once')
  end
  check(not Touch.floatingGesture and not Game.jpFieldTapPending,name..': no pending contact remains')
 end
 Game:clearSessionInput()
end
