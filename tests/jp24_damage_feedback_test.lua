-- Native damage feedback: each hit owns its blink phase, while sounds,
-- status-only moves and faint queues retain the original Gen 1 behavior.
-- ROM-free; physical-frame samples mean groups of 1 or 4 simulation ticks,
-- not a claim about Android display/audio timing.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Data=T.fixtures.fresh()
require('src.render.Font').load(Data)
require('src.battle.TypeChart').load(Data)
local Battle=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local Timing=require('src.core.Timing')
local Sound=require('src.core.Sound')
local Json=require('src.link.Json')
local report={cases={},physicalAndroid=false,assets='authored fixture',audio='native call records'}
local sounds={}
Sound.play=function(_,id)sounds[#sounds+1]={kind='sfx',id=id}end
Sound.playMove=function(_,def)sounds[#sounds+1]={kind='move',id=def.sound,pitch=def.pitch}end
Sound.playCry=function(_,id)sounds[#sounds+1]={kind='cry',id=id}end
Sound.playMoveCry=function(_,id)sounds[#sounds+1]={kind='moveCry',id=id}end
local function fresh()
  local save=Save.newGame()
  save.party={Pokemon.new(Data,'FIXMON_A',20)}
  local game={data=Data,save=save,stack={top=function()end,push=function()end}}
  local b=Battle.newWild(game,'FIXMON_C',20)
  b.queue,b.nextInsert,b.fx,b.picFx,b.frame={},0,{},{},0
  b.rng=function(a)return a end
  sounds={}
  return b
end

for phase=0,9 do
  for _,speed in ipairs({1,4})do
    local b=fresh();b.frame=phase
    b:applyHitFx({animType=4,blink=b.enemy,sfx={sound='Damage',pitch=0x20}})
    local frames,correct,otherVisible={},true,true
    -- Include the application frame: the sprite must disappear immediately,
    -- for five full native ticks, regardless of previous battle activity.
    for elapsed=0,Timing.BLINK_MON do
      local hidden=b:fxHidden(b.enemy)
      local want=elapsed<Timing.BLINK_MON and math.floor(elapsed/5)%2==0
      correct=correct and hidden==want
      otherVisible=otherVisible and not b:fxHidden(b.player)
      if elapsed%speed==0 then frames[#frames+1]={tick=elapsed,hidden=hidden}end
      b:tickFx()
    end
    T.check(correct,('phase %d at %dx starts with five hidden ticks, ends shown after six cycles'):format(phase,speed))
    T.check(otherVisible,'a hit never hides the other battler')
    T.eq(b.waitFrames,Timing.BLINK_MON,'native queue duration remains 60 simulation ticks')
    T.eq(#sounds,1,'all blink cycles use one applying-attack sound')
    T.eq(sounds[1].kind,'move','ordinary damage is not a species cry')
    report.cases[#report.cases+1]={startPhase=phase,speed=speed,correct=correct,frames=frames}
  end
end

-- Every applying-attack dispatch retains the original target/axis and sound.
for t=1,6 do
  local b=fresh()
  local damaging=t==1 or t==2 or t==4 or t==5
  local target=t<=3 and b.player or b.enemy
  b:applyHitFx({animType=t,blink=target,sfx=damaging and {sound='Damage',pitch=0x20} or nil})
  T.eq(#sounds,damaging and 1 or 0,'only damaging applying-attack types play a hit sound '..t)
  T.eq(b.fx.blink~=nil,t==4,'only plain player attacks blink the enemy '..t)
  T.eq(b.fx.shakeProg~=nil,t~=4,'other native applying-attack types retain their shake '..t)
end

local function hits(b)
  local rows={}
  for _,row in ipairs(b.queue)do if row.hit then rows[#rows+1]=row.hit end end
  return rows
end
for _,isPlayer in ipairs({true,false})do
  for _,amount in ipairs({0,1})do
    local b=fresh()
    local user,target=isPlayer and b.player or b.enemy,isPlayer and b.enemy or b.player
    b.computeDamage=function()return amount,{crit=false,typeMult=10}end
    b:performMove(user,target,{id='FIX_TACKLE',pp=10},false)
    local rows=hits(b)
    T.eq(#rows,amount,'zero damage queues no false hit, positive damage queues exactly one')
    if rows[1] then
      T.eq(rows[1].animType,isPlayer and 4 or 1,'damage feedback follows original attacker side')
      b:applyHitFx(rows[1])
      T.eq(#sounds,1,'one hit queues exactly one neutral hit sound')
      T.eq(sounds[1].id,'Damage','neutral damage retains its native sound')
    end
  end
end

Data.moves.FIX_STATUS={id='FIX_STATUS',index=98,name='FIX STATUS',type='NORMAL',
  power=0,accuracy=100,pp=20,effect='ATTACK_DOWN1_EFFECT'}
for _,isPlayer in ipairs({true,false})do
  local b=fresh()
  -- Gen 1 enemy stat-down moves miss on rolls below $40.
  b.rng=function()return 0x40 end
  local user,target=isPlayer and b.player or b.enemy,isPlayer and b.enemy or b.player
  b:performMove(user,target,{id='FIX_STATUS',pp=10},false)
  local rows=hits(b)
  T.eq(#rows,1,'successful stat-only move retains one native reaction')
  T.check(rows[1] and rows[1].sfx==nil,'status-only reaction carries no damage sound')
  if rows[1] then
    b:applyHitFx(rows[1])
    T.eq(#sounds,0,'status-only reaction does not invent a cry')
    T.eq(b.fx.blink,nil,'status-only reaction does not hide a Pokemon')
  end
end

for _,kind in ipairs({'wild','trainer'})do
  for _,isPlayer in ipairs({true,false})do
    local b=fresh();b.kind=kind
    local target=isPlayer and b.player or b.enemy
    target.mon.hp=0
    b:onFaint(target)
    local n=#b.queue;b:onFaint(target)
    T.eq(#b.queue,n,'repeated faint detection does not enqueue duplicate audio')
    T.eq(#sounds,0,'faint audio waits for native queue, after hit/HP drain')
    -- Execute only the native presentation prefix, stopping before the
    -- faint text/rewards to avoid replacing gameplay with a test shortcut.
    for _,row in ipairs(b.queue)do
      if row.text then break end
      if row.fn then row.fn()end
    end
    local cries,fall,thud=0,0,0
    for _,s in ipairs(sounds)do
      cries=cries+(s.kind=='cry' and 1 or 0)
      fall=fall+(s.id=='Faint_Fall' and 1 or 0)
      thud=thud+(s.id=='Faint_Thud' and 1 or 0)
    end
    T.eq(cries,isPlayer and 1 or 0,'only own faint retains its species cry')
    T.eq(fall,not isPlayer and kind=='trainer' and 1 or 0,'trainer foe retains one faint-fall sound')
    T.eq(thud,not isPlayer and kind=='trainer' and 1 or 0,'trainer foe retains one faint-thud sound')
    T.eq(b.fx.faint.frames,Timing.FAINT_SLIDE,'faint slide still owns original frame budget')
  end
end

local b=fresh()
Data.moves.GROWL={anim={tempo=12}}
b.animName='GROWL';b.animAttackerIsPlayer=true
b:playAnimSound('GROWL')
T.eq(#sounds,1,'Growl remains one original move cry')
T.eq(sounds[1].kind,'moveCry','Growl uses modified cry, not applying-attack damage sound')
report.checks=T.harness.checks;report.failures=T.failures()
local path=os.getenv('JP24_DAMAGE_REPORT')
if path then local file=assert(io.open(path,'w'));file:write(assert(Json.encode(report)));file:close()end
T.finish('jp24 native damage feedback')
