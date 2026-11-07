-- Actual driver compile AND link, against the byte-pinned delivered regression.
-- validateShader(true, ...) alone accepted jp.32 and is not sufficient here.
local function run()
  local root=assert(os.getenv('JP_SHADER_ROOT'))
  local out=assert(os.getenv('JP_SHADER_OUT'))
  package.path=root..'/?.lua;'..package.path
  local T=require('tests.harness').suite('jp33 actual GLES shader regression')
  local renderer=require('tests.gles_context')(T.check)
  local function source(path)
    local f=assert(io.open(path,'rb'));local text=f:read('*a');f:close()
    return assert(text:match('local SHADER%s*=%s*%[%[(.-)%]%]'))
  end
  local current=source(root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/Voxel3D.lua')
  local previous=source(assert(os.getenv('JP_SHADER_BEFORE')))
  local cases={}
  local variants={
    {'world',''},
    {'world-grid','#define VOXEL_GRID 1\n'},
    {'battle','#define BATTLE_OCCLUSION 1\n'},
    {'battle-grid','#define BATTLE_OCCLUSION 1\n#define VOXEL_GRID 1\n'},
    {'unlit-card','#define UNLIT_ONLY 1\n'},
  }
  for i=1,4 do
    local v=variants[i]
    variants[#variants+1]={v[1]..'-receiver-plane','#define RECEIVER_PLANE_SHADOW 1\n'..v[2]}
  end
  for _,variant in ipairs(variants)do
    local oldOK,old=pcall(love.graphics.newShader,variant[2]..previous)
    T.check(not oldOK and tostring(old):find('fxWind',1,true)~=nil,
      'delivered jp32 '..variant[1]..' reproduces fxWind link failure')
    local ok,shader=pcall(love.graphics.newShader,variant[2]..current)
    T.check(ok,'jp33 '..variant[1]..' compiles and links: '..tostring(shader))
    if ok then shader:release()end
    cases[#cases+1]={variant=variant[1],previousFailed=not oldOK,
      previousError=tostring(old),currentLinked=ok}
  end
  local ok,shader=pcall(love.graphics.newShader,
    source(root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/EffectParticles.lua'))
  T.check(ok,'particle shader links on actual GLES: '..tostring(shader))
  if ok then shader:release()end
  local f=assert(io.open(out..'/results.json','wb'))
  f:write(require('src.link.Json').encode({renderer=renderer,cases=cases,
    checks=T.checks,failures=T.failures,romUsed=false}));f:close()
  T.finish()
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err)end
  love.event.quit(ok and 0 or 1)
end
