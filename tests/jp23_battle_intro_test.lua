-- Presentation clock ownership: no elapsed simulation ticks release the
-- opponent shot until BOTH actual enemy and complete intro text were drawn.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('jp23 text-first opponent focus')
local time=100
love.timer={getTime=function()return time end}
local lib='vendor/jp-mods/DRAMALESS_SHAPE/lib/'
local modules={}
local V={}
function V.require(name)
  if not modules[name] then modules[name]=assert(loadfile(lib..name..'.lua'))(V)end
  return modules[name]
end
local Intro=V.require('BattleIntroFocus')
local function fresh(kind)
  local b={kind=kind or 'wild',phase='intro',showPlayerBack=true,
    game={save={options={jpBattleIntro='focus',animations=true}}}}
  local a={encounter=true};Intro.begin(a,b)
  return a,b
end
do
  local a,b=fresh('trainer')
  T.check(a.trainerIntro and not a.focusIntro,'trainer has its own challenge-first introduction')
  T.check(not Intro.nativeSlide(a),'trainer keeps native source-clocked foe entrance')
  T.eq(Intro.weight(a),1,'trainer stays close until actual complete challenge draw')
  T.eq(Intro.trainerAlpha(a,'player'),0,'near trainer waits for post-challenge pull-back')
  T.eq(Intro.entranceRemaining({},18,72),.25,'original option preserves native linear movement')
end
local function tick(a,dt,n)
  for _=1,n or 1 do time=time+dt;Intro.update(a)end
end
for _,kind in ipairs({'wild'})do
  local a,b=fresh(kind)
  tick(a,1/60,120)
  T.eq(Intro.weight(a),1,kind..' nothing advances before any enemy draw')
  Intro.shown(a);tick(a,1/60,300)
  T.eq(a.focusIntro.time,0,kind..' five real seconds still hold before complete text draw')
  T.eq(Intro.weight(a),1,kind..' holds opponent regardless of elapsed simulation')
  b.jpIntroTextShown=true;Intro.update(a)
  T.eq(Intro.weight(a),1,kind..' full text first draw preserves close shot')
  tick(a,1/60,math.floor(Intro.HOLD*60))
  T.eq(Intro.weight(a),1,kind..' text gets its short readable hold')
  local age=a.focusIntro.time
  for _=1,4 do Intro.update(a)end
  T.eq(a.focusIntro.time,age,kind..' four logic updates do not consume extra wall time')
  tick(a,1/60,20)
  T.check(Intro.weight(a)>0 and Intro.weight(a)<1,kind..' smooth pull runs after message')
  age=a.focusIntro.time;tick(a,60)
  T.eq(a.focusIntro.time,age,kind..' app suspension does not consume cinematic')
  tick(a,1/60,100)
  T.eq(Intro.weight(a),0,kind..' settles exactly once')
  T.check(a.focusIntro.done,kind..' marks complete')
  local rebuilt={encounter=true};Intro.begin(rebuilt,b)
  T.eq(rebuilt.focusIntro,nil,kind..' rebuilding arena does not replay first shot')
  Intro.shown(a);tick(a,1)
  T.eq(Intro.weight(a),0,kind..' later draw cannot restart intro')
end
for _,field in ipairs({'sendingOut','enemySendingOut'})do
  local a,b=fresh();Intro.shown(a);b[field]=true;Intro.update(a)
  T.eq(Intro.weight(a),0,field..' native effect forces canonical rig before draw')
end
for _,phase in ipairs({'menu'})do
  local a,b=fresh();Intro.shown(a);b.phase=phase;Intro.update(a)
  T.eq(Intro.weight(a),0,'command phase has no remaining cinematic')
end
for _,slot in ipairs({'back','foe'})do
  local a,b=fresh('trainer');Intro.shown(a)
  function b:picOffset(name)return name==slot and 2 or 0 end
  Intro.update(a);T.eq(Intro.weight(a),0,slot..' native trainer retreat settles camera')
end
for _,flag in ipairs({'reduceMotion','jpReduceMotion'})do
  local a,b=fresh();b.game.save.options[flag]=true;Intro.update(a)
  T.eq(Intro.weight(a),0,flag..' disables added motion')
end
for _,mode in ipairs({'original','animationsOff'})do
  local _,b=fresh()
  if mode=='original' then b.game.save.options.jpBattleIntro='original'
  else b.game.save.options.animations=false end
  local a={encounter=true};Intro.begin(a,b)
  T.eq(a.focusIntro,nil,mode..' preserves original presentation')
end
local _,b=fresh('trainer');b.jpTrainerIntroTiming={focus=false}
local a={encounter=true};Intro.begin(a,b)
T.eq(a.focusIntro,nil,'late terrain cannot replace already chosen original source-clock intro')
local c={eye={0,40,100},focus={0,0,0},fov=math.rad(46)}
local r={Up=3,ph=800};local arena={player={0,20},enemy={0,-20},mid={0,0}}
local pixel=Intro.cardWorldPixel(arena,c,'enemy',0,1,r,false)
local normal=Intro.worldPixel(c,arena.enemy,0,1,r)
T.check(pixel<normal,'foe no longer grows its world size to compensate for distance')
local player=Intro.cardWorldPixel(arena,c,'player',0,1,r,false)
T.eq(player,Intro.worldPixel(c,arena.player,0,1,r),'near-side original scale preserved')
T.finish()
