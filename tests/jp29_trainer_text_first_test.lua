-- Native entry remains music-clocked; only complete physical text releases
-- the close-up. Uses the real presentation module, independently driven clocks.
package.path='./?.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('jp29 trainer challenge before pull-back')
local now=10;love.timer={getTime=function()return now end}
local V,modules={},{}
function V.require(n)if not modules[n]then modules[n]=assert(loadfile('vendor/jp-mods/DRAMALESS_SHAPE/lib/'..n..'.lua'))(V)end;return modules[n]end
local Intro=V.require('BattleIntroFocus')
local function fresh()
 local b={kind='trainer',phase='messages',showPlayerBack=true,showEnemyTrainer=true,introSlide=72,
  game={save={options={animations=true,jpBattleIntro='focus'}}}}
 local a={encounter=true};Intro.begin(a,b);return a,b
end
for _,fps in ipairs({20,60})do for _,speed in ipairs({1,4})do
 local a,b=fresh();local audio=3.6
 b.jpTrainerIntroTiming={focus=true,slideStart=3.6,revealTime=4.8,clock={position=function()return audio end}}
 for i=0,72 do
  audio=3.6+i/60;b.introSlide=72-i
  for _=1,speed do Intro.update(a)end
  Intro.shown(a)
  T.eq(Intro.weight(a),1,'native silhouette/music completion never pulls before challenge')
  T.eq(Intro.trainerAlpha(a,'player'),0,'player never flashes during foe-only entrance')
  if i>=28 then T.eq(Intro.entranceRemaining(a,72-i,72,'enemy'),0,'landed foe stays still while challenge waits')end
 end
 T.check(not a.trainerIntro.done,'72-frame native finish does not finish camera')
 -- Typewriter / read delays may be arbitrarily long; no guessed text timer.
 for _=1,fps*3 do now=now+1/fps;Intro.update(a);Intro.shown(a)end
 T.eq(Intro.weight(a),1,'three-second text delay retains exact close shot')
 b.jpIntroTextShown=true;Intro.update(a)
 T.eq(Intro.weight(a),1,'first complete challenge frame is still the close-up')
 local previous=1;local count=0;local playerSeen=false
 repeat
  now=now+1/fps
  for _=1,speed do Intro.update(a)end
  Intro.shown(a)
  local w=Intro.weight(a)
  T.check(w<=previous and w>=0,'pull is monotonic at every physical frame')
  if Intro.trainerAlpha(a,'player')>0 then
   T.check(w<1,'player is revealed only after camera begins pulling')
   playerSeen=true
  elseif playerSeen then T.check(false,'player never blinks off during pull')end
  previous=w;count=count+1
 until a.trainerIntro.done or count>fps*2
 T.check(a.trainerIntro.done and not a.trainerIntro.active,'bounded pull releases queue acknowledgement')
 T.check(count/fps>=1.0 and count/fps<1.1,'physical pull duration is invariant under 1x/4x')
 T.eq(Intro.entranceRemaining(a,0,72,'player'),0,'player reaches canonical native foot position')
 T.eq(Intro.entranceRemaining(a,0,72,'enemy'),0,'enemy stays in canonical native foot position')
 local rebuilt={encounter=true};Intro.begin(rebuilt,b)
 T.eq(rebuilt.trainerIntro,nil,'completed arena rebuild cannot replay entrance')
end end
for _,option in ipairs({'reduceMotion','jpReduceMotion'})do
 local a,b=fresh();b.game.save.options[option]=true;Intro.update(a)
 T.eq(Intro.weight(a),0,option..' settles camera')
 T.check(a.trainerIntro.done and not a.trainerIntro.active,option..' releases message gate')
end
for _,field in ipairs({'sendingOut','enemySendingOut'})do
 local a,b=fresh();b[field]=true;Intro.update(a)
 T.eq(Intro.weight(a),0,field..' settles before native effects')
 T.check(a.trainerIntro.done,field..' releases message gate')
end
for _,slot in ipairs({'back','foe'})do
 local a,b=fresh();b.picOffset=function(_,s)return s==slot and 4 or 0 end;Intro.update(a)
 T.eq(Intro.weight(a),0,slot..' original native exit cannot inherit moving camera')
end
do
 local a,b=fresh();Intro.shown(a);b.jpIntroTextShown=true;Intro.update(a)
 now=now+.2;Intro.update(a);local age=a.trainerIntro.time
 local beat=a.trainerIntro.heartbeat;now=now+60;Intro.update(a)
 T.eq(a.trainerIntro.time,age,'background suspension is not consumed as animation')
 T.eq(a.trainerIntro.heartbeat,beat,'logic-only updates cannot forge presentation heartbeat')
end
do
 local a,b=fresh();Intro.shown(a);local rebuilt={encounter=true};Intro.begin(rebuilt,b)
 T.eq(rebuilt.trainerIntro,a.trainerIntro,'uncompleted arena rebuild reuses one presentation state')
end
do
 local a,b=fresh();local calls=0
 b.jpTrainerIntroTiming={focus=true,slideStart=3.6,revealTime=4.8,
  clock={position=function()calls=calls+1;return 3.6+calls/60 end}}
 Intro.update(a);local t=Intro.trainerProgress(a)
 Intro.weight(a);Intro.trainerAlpha(a,'player')
 Intro.entranceRemaining(a,72,72,'player');Intro.entranceRemaining(a,72,72,'enemy')
 T.eq(calls,1,'camera and card transforms share one source-clock sample')
 T.eq(Intro.trainerProgress(a),t,'draw does not resample live audio halfway through frame')
end
T.finish()
