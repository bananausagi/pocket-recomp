local root=assert(os.getenv('JP_QA_ROOT'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
love.system.getOS=function()return 'Android'end
local baseline=os.getenv('JP52_BASELINE_ROOT')
if baseline then package.preload['src.core.Game']=function()return assert(loadfile(baseline..'/Game.lua'))()end end
assert(loadfile((baseline or root)..'/main.lua'))()
local Game=require('src.core.Game')
local function upvalue(fn,name,value)
 for i=1,100 do
  local n=debug.getupvalue(fn,i);if not n then break end
  if n==name then debug.setupvalue(fn,i,value);return end
 end
 error('missing host upvalue '..name)
end
upvalue(love.keypressed,'Game',Game)
local function drain()
 for name,a,b,c,d,e,f in love.event.poll()do
  if name=='touchpressed' or name=='touchreleased' or name=='touchmoved'
    or name=='keypressed' or name=='keyreleased' or name=='focus' then
   love.handlers[name](a,b,c,d,e,f)
  end
 end
end
local function event(name,...)love.event.push(name,...);drain()end
local function run()
 local checks=0
 local function check(ok,label)assert(ok,label);checks=checks+1;print('PASS '..label)end
 require('tests.jp52_cancel_cases')(Game,{
  press=function(id,x,y)event('touchpressed',id,x,y,0,0,1)end,
  move=function(id,x,y)event('touchmoved',id,x,y,0,0,1)end,
  release=function(id,x,y,p)event('touchreleased',id,x,y,0,0,baseline and math.max(0,p) or p)end,
  back=function()event('keypressed','escape','acback',false);event('keyreleased','escape','acback')end,
  focus=function(v)event('focus',v)end,
 },check)
 local tracePath=os.getenv('JP53_NATIVE_TRACES')
 if tracePath then
  local file=assert(io.open(tracePath,'rb'));local raw=file:read('*a');file:close()
  require('tests.jp53_native_trace_cases')(Game,require('src.link.Json').decode(raw),event,check)
 end
 -- Exercise SDL -> real LÖVE event conversion too: the cancellation marker
 -- must survive pressure transport, and LÖVE must retire its finger record.
 local ffi=require('ffi')
 ffi.cdef[[
 typedef struct { uint32_t type,timestamp; int64_t touchId,fingerId;
  float x,y,dx,dy,pressure; uint32_t windowID; } Jp52Touch;
 typedef union { uint32_t type; Jp52Touch tfinger; uint8_t padding[56]; } Jp52Event;
 int SDL_PushEvent(Jp52Event *event);
 ]]
 local sdl=ffi.C
 local function push(kind,pressure)
  local ev=ffi.new('Jp52Event');ev.tfinger.type=kind;ev.tfinger.fingerId=512
  ev.tfinger.touchId=20;ev.tfinger.x=.45;ev.tfinger.y=.25;ev.tfinger.pressure=pressure
  assert(sdl.SDL_PushEvent(ev)==1);love.event.pump()
  local observed
  for name,a,b,c,d,e,f in love.event.poll()do
   if name=='touchpressed' or name=='touchreleased'then
    observed=f;love.handlers[name](a,b,c,d,e,f)
   end
  end
  return observed
 end
 Game.stack:init();Game.sessionMenu=nil;local field={map={},player={}}
 Game.overworld=field;Game.stack:push(field);Game:clearSessionInput()
 check(push(0x700,1)==1,'real SDL finger-down preserves normal pressure')
 check(#love.touch.getTouches()==1,'real LÖVE tracks SDL finger')
 check(push(0x701,-1)==-1,'real SDL/LÖVE finger-up preserves cancellation marker')
 check(#love.touch.getTouches()==0,'cancelled SDL finger is removed from LÖVE')
 Game.input:step()
 check(not Game.input:wasPressed('a') and not Game.jpFieldTapPending,'real SDL cancel reaches main/Game without generating A')
 local Imp=require('src.import.RomImporter');local clicks=0
 local imp=setmetatable({_ui={hits={{id='danger',x=0,y=0,w=200,h=200,action=function()clicks=clicks+1 end}}}}, {__index=Imp})
 upvalue(love.touchpressed,'Importer',imp)
 event('touchpressed','launcher',50,50,0,0,1);event('touchreleased','launcher',50,50,0,0,-1)
 check(clicks==0 and not imp._ui.touch and not imp._ui.pressedId,'main routes launcher cancellation without clicking or retaining highlight')
 event('touchreleased','launcher',50,50,0,0,0)
 check(clicks==0,'cancelled launcher pointer cannot act on a late release')
 upvalue(love.touchpressed,'Importer',nil)
 local E=require('src.ui.JapaneseTouchAreaEditor');local closed=0
 E.load({onClose=function()closed=closed+1 end});upvalue(love.touchpressed,'TouchEditor',E)
 local save
 for _,h in ipairs(E.layout().hits)do if h.id=='save'then save=h end end
 local sx,sy=save.x+save.w*.5,save.y+save.h*.5
 event('touchpressed','save',sx,sy,0,0,1);event('touchreleased','save',sx,sy,0,0,-1)
 check(closed==0 and not E.pointer and not E.drag,'cancelled area-editor Save button does not commit')
 E.close(false);upvalue(love.touchpressed,'TouchEditor',nil)
 local out=assert(os.getenv('JP_QA_OUT'));local f=assert(io.open(out..'/host-results.json','wb'))
 f:write(require('src.link.Json').encode({checks=checks,romUsed=false,physicalAndroid=false,
  realMain=true,realGame=true,realLoveEventQueue=true,realSDLPressureConversion=true,nativeTraces=tracePath~=nil}));f:close()
 print(checks..' REAL MAIN CANCEL / NATIVE TRACE CHECKS PASSED')
end
function love.load()
 local ok,err=xpcall(run,debug.traceback);if not ok then print(err)end
 love.update=function()end;love.draw=function()end;love.quit=function()end
 love.event.quit(ok and 0 or 1)
end
function love.errorhandler(message)
 print('CANCEL FIXTURE ERROR '..tostring(message)..'\n'..debug.traceback())
 return function()return 1 end
end
