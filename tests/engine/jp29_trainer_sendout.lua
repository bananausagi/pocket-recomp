-- Drive the real queue for the first send-out, an AI switch and a KO
-- replacement. The clock and sound source are controlled; graphics are not
-- claimed here (the companion LÖVE suite renders the actual 3D cards).
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Data=T.fixtures.fresh()
require('src.render.Font').load(Data)
require('src.battle.TypeChart').load(Data)
local Battle=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local Send=require('src.battle.TrainerSendOut')
local Sound=require('src.core.Sound')
local now=0
love.timer.getTime=function()return now end
local events={}
local function source(seconds)
  local finish=now+seconds
  return {isPlaying=function()return now<finish end,stop=function()finish=now end}
end
Sound.play=function(_,id)
  events[#events+1]={id=id,time=now}
  return source(.08)
end
Sound.waitFrames=function()return 120 end
local function game(speed)
  local save=Save.newGame()
  save.party={Pokemon.new(Data,'FIXMON_A',30)}
  save.options.jpBattleIntro='focus';save.options.animations=true
  save.options.textSpeed=1;save.options.battleStyle='set'
  return {data=Data,save=save,logicSpeed=function()return speed end,
    input={wasPressed=function()return true end,isDown=function()return true end},
    stack={top=function()end,push=function()end,pop=function()end}}
end
local function make(speed)
  local b=Battle.newTrainer(game(speed),'OPP_FIX_YOUNGSTER',1)
  b.jpEnemySendOut3D=true
  b.playEntranceCry=function(self,who)
    events[#events+1]={id=who==self.enemy and 'enemy-cry' or 'player-cry',time=now}
    return source(.10)
  end
  return b
end
local function run(b,speed,label)
  local seen,fullDraw,firstBall,lastBall,grown=false,nil,nil,nil,nil
  events={}
  for frame=1,1800 do
    now=now+1/60
    for _=1,speed do b:update(1/60);if b.phase=='menu'then break end end
    local s=b.growIn and b.growIn.presentation
    if s then
      if not seen then firstBall=now;seen=true;T.eq(Send.scale(s),0,label..' starts with only a ball')end
      lastBall=now
      if Send.scale(s)>0 then grown=grown or now end
      if s.time>=Send.DURATION and not fullDraw then fullDraw=now end
      b:drawPicsLayer(0,0,0,'enemy',true)
      T.check(b.enemyHudPending,label..' HUD remains absent throughout ball opening')
    end
    if b.phase=='menu' then break end
  end
  T.check(seen and fullDraw and grown,label..' ball, growing mon and full physical draw all occur')
  T.check(fullDraw and math.abs(fullDraw-firstBall-Send.DURATION)<.035,label..' duration is independent of gameplay speed')
  T.eq(b.phase,'menu',label..' queue returns to commands')
  local poof,cry={},{}
  for _,e in ipairs(events)do
    T.neq(e.id,'Ball_Toss',label..' never plays a capture throw')
    if e.id=='Ball_Poof' then poof[#poof+1]=e end
    if e.id=='enemy-cry' then cry[#cry+1]=e end
  end
  -- Initial player send-out has its own unchanged POOF; count only events
  -- between the enemy's ball and its final frame.
  local count=0
  for _,e in ipairs(poof)do if e.time>=firstBall and e.time<=lastBall then
    count=count+1;T.check(e.time>=firstBall+Send.OPEN-.02,label..' release SE occurs at opening')
  end end
  T.eq(count,1,label..' exactly one enemy release SE')
  T.eq(#cry,1,label..' exactly one enemy cry')
  T.check(cry[1] and fullDraw and cry[1].time>fullDraw,label..' cry follows the actual full-size draw')
  T.eq(b.enemyHudPending,nil,label..' HUD appears after the cry')
end
for _,speed in ipairs({1,4})do
  local b=make(speed);b:enter();run(b,speed,'first '..speed..'x')
  b.queue={};b.nextInsert=0;b.phase='messages';b.afterQueue='menu'
  b:executeAction(b.enemy,b.player,{special='aiSwitch',index=2})
  run(b,speed,'AI switch '..speed..'x')
  -- A fresh fixture leaves a live reserve for the real post-KO path.
  b=make(speed);b:enter();run(b,speed,'KO setup '..speed..'x')
  b.queue={};b.nextInsert=0;b.phase='messages';b.afterQueue='menu'
  b.enemy.mon.hp=0;b.enemyParty[1].hp=0;b:enemyMonFainted()
  run(b,speed,'KO replacement '..speed..'x')
end
for _,setting in ipairs({'original','animations','reduceMotion','jpReduceMotion','2d','wild','link','demo','safari','player'})do
  local b=make(1)
  if setting=='original'then b.game.save.options.jpBattleIntro='original'
  elseif setting=='animations'then b.game.save.options.animations=false
  elseif setting=='reduceMotion'or setting=='jpReduceMotion'then b.game.save.options[setting]=true
  elseif setting=='2d'then b.jpEnemySendOut3D=nil
  elseif setting=='wild'or setting=='link'then b.kind=setting
  elseif setting=='demo'or setting=='safari'then b[setting]=true end
  b.queue={};b.nextInsert=0;b:startGrowIn(setting=='player'and b.player or b.enemy)
  T.eq(b.growIn.presentation,nil,setting..' keeps native send-out')
  T.eq(b.queue[1].wait,12,setting..' retains exact native 12-frame hold')
end
do
  local s=Send.new(now);now=now+.1;Send.advance(s,now)
  local t=s.time;now=now+10;Send.advance(s,now)
  T.eq(s.time,t,'background suspension preserves ball pose')
  T.check(not Send.done(s),'background suspension does not expire the release')
  for _=1,130 do now=now+1/60;Send.advance(s,now)end
  T.check(Send.done(s),'renderer removal has a bounded fail-open')
end
do
  local b=make(4)
  b.jpIntroTextActive=true;b.jpTrainerPresentation={active=true,done=false}
  for _=1,10 do T.check(b:trainerPresentationPending(),'same-frame A spam cannot dismiss challenge')end
  now=now+10;T.check(b:trainerPresentationPending(),'background suspension does not skip camera pull')
  for _=1,130 do now=now+1/60;b:trainerPresentationPending()end
  T.check(not b:trainerPresentationPending(),'removed camera has a bounded fail-open')
  b.jpTrainerPresentation={active=true,done=true}
  T.check(not b:trainerPresentationPending(),'completed pull releases challenge queue')
  b.jpTrainerPresentation={active=true,done=true,finalDrawPending=true}
  T.check(b:trainerPresentationPending(),'last pull frame must be drawn before native departure')
end
T.finish('jp29 trainer send-out real queue')
