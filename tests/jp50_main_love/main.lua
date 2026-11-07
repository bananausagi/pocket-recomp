-- Load real host callbacks and feed the actual LÖVE event queue. No cartridge.
local root=assert(os.getenv('JP_QA_ROOT'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
love.system.getOS=function()return 'Android'end
assert(loadfile(root..'/main.lua'))()
local Game=require('src.core.Game')
local function upvalue(fn,name,value)
 for i=1,100 do
  local n=debug.getupvalue(fn,i);if not n then break end
  if n==name then debug.setupvalue(fn,i,value);return end
 end
 error('missing host upvalue '..name)
end
upvalue(love.keypressed,'Game',Game)
local function event(name,...)
 love.event.push(name,...)
 for e,a,b,c,d,f in love.event.poll()do
  if love.handlers[e] then love.handlers[e](a,b,c,d,f)end
 end
end
local function run()
 local checks=0
 local function check(ok,label)assert(ok,label);checks=checks+1;print('PASS '..label)end
 for _,keys in ipairs({{'escape','acback'},{'appback','acback'},{'unknown','acback'}})do
  require('tests.jp50_system_back_cases')(Game,{
   back=function()event('keypressed',keys[1],keys[2],false);event('keyreleased',keys[1],keys[2])end,
   repeatBack=function()event('keypressed',keys[1],keys[2],true);event('keyreleased',keys[1],keys[2])end,
   focus=function(v)event('focus',v)end,visible=function(v)event('visible',v)end,
   resume=function()event('lowmemory')end,
  },check)
 end
 local out=assert(os.getenv('JP_QA_OUT'))
 local f=assert(io.open(out..'/host-results.json','wb'))
 f:write(require('src.link.Json').encode({checks=checks,romUsed=false,physicalAndroid=false,
  realMain=true,realGame=true,realLoveEventQueue=true,androidOSBranch=true}));f:close()
 print(checks..' JP50 REAL MAIN BACK CHECKS PASSED')
end
function love.load()
 local ok,err=xpcall(run,debug.traceback);if not ok then print(err)end
 love.update=function()end;love.draw=function()end;love.quit=function()end
 love.event.quit(ok and 0 or 1)
end
function love.errorhandler(message)
 print('BACK FIXTURE ERROR '..tostring(message)..'\n'..debug.traceback())
 return function()return 1 end
end
