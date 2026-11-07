package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('jp36 HD-2D preferences and hit impulse')
local Save=require('src.core.SaveData')
local Transfer=require('src.import.SettingsTransfer')
local C=require('src.ui.JapaneseConvenienceSettings')
local opt=Save.mergeOptions({jpAtmosphere='off',jpFxGrass=false,jpFxHitReaction=true})
local game={data={constants={language='ja'}},save={options=opt}}
package.loaded['src.core.Game']=game
local row;for _,r in ipairs(C.rows)do if r.id=='jpAtmosphere'then row=r end end
T.check(row~=nil,'reuse the existing scenery preference')
local V={require=function()end}
local atmosphere=assert(loadfile('vendor/jp-mods/DRAMALESS_SHAPE/lib/Atmosphere.lua'))(V)
for _,value in ipairs({'soft','gentle','off'})do
  opt.jpAtmosphere=value
  local copy=assert(Transfer.import(assert(Transfer.export(opt)),{}))
  T.eq(copy.jpAtmosphere,value,value..' survives portable settings')
  T.eq(copy.jpFxGrass,false,'scenery choices preserve grass OFF')
  T.eq(atmosphere.strength(),({soft=1,gentle=.35,off=0})[value],value..' selects its glow/haze amount')
end
local now=0;love.timer={getTime=function()return now end}
local A=assert(loadfile('vendor/jp-mods/DRAMALESS_SHAPE/lib/BattleActionCamera.lua'))(V)
local b={game=game,phase='messages',player={},enemy={},data={moves={}}}
game.stack={top=function()return b end}
local arena={encounter=true}
local function step(dt)now=now+(dt or .05);A.update(arena,b);return arena.actionCamera end
local s=step();T.eq(s.impulse,0,'idle camera has no impact pulse')
b.jpFxHitSerial=1;s=step();s=step()
T.check(s.impulse>0,'landed hit drives the existing camera once')
local before=s.hitAt;s=step();T.eq(s.hitAt,before,'same hit does not restart impulse')
for _=1,6 do s=step()end
T.eq(s.impulse,0,'impact settles within a quarter second')
b.jpFxHitSerial=2;opt.jpFxHitReaction=false;s=step();s=step()
T.eq(s.impulse,0,'hit reaction OFF disables impulse')
opt.jpFxHitReaction=true;opt.jpBattleCameraMotion=false;s=step()
T.eq(s,nil,'camera OFF disables all camera motion')
opt.jpBattleCameraMotion=true;s=step();s=step()
T.eq(s.impulse,0,'resume never replays a stale hit')
opt.reduceMotion=true;s=step();T.eq(s,nil,'reduce motion overrides impulse')
opt.reduceMotion=false;opt.animations=false;s=step();T.eq(s,nil,'native animations OFF overrides impulse')
opt.animations=true;s=step();game.stack.top=function()return {}end;s=step()
T.eq(s,nil,'paused battle never receives cosmetic motion')
T.finish()
