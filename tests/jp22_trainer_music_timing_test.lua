-- Trainer native wipe/slide use one real-time presentation clock; tests drive
-- it independently of accelerated battle ticks. Real Source/GL companion:
-- tests/jp_battle_seamless_render.lua trainer cases.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local focus=false
package.loaded['src.mods.Runtime']={
  wantsHook=function()return false end,emit=function()end,
  call=function(name,default,ctx)
    if name=='battle.transition.trainerFocus' then return focus end
    return default(ctx)
  end,
}
local S=require('tests.harness').suite('jp22 trainer music timing')
local Transition=require('src.render.BattleTransition')
local Battle=require('src.battle.BattleState')
local Music=require('src.core.Music')
local function new(stronger,dungeon,language)
  local game={data={constants={language=language or 'ja'}},save={options={}}}
  local battle=setmetatable({kind='trainer',game=game,data=game.data,frame=0,
    lowHealthAlarmActive=function()return false end,wideLayout=function()return false end,
    drawClassic=function(self)self.draws=(self.draws or 0)+1 end},{__index=Battle})
  local entered=0
  local transition
  game.stack={pop=function()transition:exit()end}
  transition=Transition.new(game,function()
    entered=entered+1
    battle.introSlide=72-(battle.jpEncounterIntroCredit or 0)
    battle.jpEncounterIntroCredit=nil
  end,{battle=battle,trainer=true,stronger=stronger,dungeon=dungeon})
  return transition,battle,function()return entered end
end
for _,mode in ipairs({'original','focus'})do
  focus=mode=='focus'
  for _,speed in ipairs({1,4})do for _,bits in ipairs({{false,false},{true,false},{false,true},{true,true}})do
    local tr,battle,entered=new(unpack(bits))
    local at=0
    local clock={position=function()return at end}
    tr:syncMusic(clock)
    S.check(tr.nativeMusicClock==clock,'trainer binds exact supplied music instance')
    local entry=tr.nativeTransferTime
    local expected=math.floor(entry*60+.5)
    for frame=0,expected-1 do
      at=frame/60
      for _=1,speed do tr:update(1/60)end
    end
    S.eq(entered(),0,'accelerated logic cannot enter before Source entry cue')
    local frozen=tr.t
    for _=1,240 do tr:update(1/60)end
    S.eq(tr.t,frozen,'paused Source freezes wipe despite extra update calls')
    at=entry;for _=1,speed do tr:update(1/60)end
    S.eq(entered(),1,'entry occurs exactly once at Source cue')
    S.check(not tr.cancelled,'ordinary transfer is not mistaken for cancellation')
    S.eq(entry,tr.trainerBattle.jpTrainerIntroTiming.slideStart,
      mode..' presents the entrance instead of spending its budget on black')
    S.eq(battle.introSlide,72,mode..' preserves native silhouette and queue duration')
    if focus then
      S.check(battle.jpEncounterAwaitDraw,'focus waits for first physical draw')
      package.loaded['src.battle.JapaneseBattleLayout']={active=function()return false end}
      battle:draw()
      S.eq(battle.jpEncounterAwaitDraw,nil,'native rendering fallback also acknowledges draw')
      S.eq(battle.draws,1,'fallback actually draws before releasing latch')
    end
    at=entry+.5
    for _=1,speed*30 do battle:updateFx()end
    S.eq(battle.introSlide,42,mode..' entrance follows half-second Source progress at any logic speed')
    at=tr.revealTime
    battle:updateFx()
    S.eq(battle.introSlide,0,mode..' colour/text reveal lands at native completed-intro musical phase')
    for _=1,300 do tr:update(1/60)end
    S.eq(entered(),1,'completed transition can never replay intro')
  end end
end
focus=true
do
  local tr,battle,entered=new(false,false)
  tr:syncMusic({position=function()return 0 end});tr:exit()
  S.eq(battle.jpTrainerIntroTiming,nil,'cancelled transition releases clock state')
  tr:update(10);S.eq(entered(),0,'cancelled transition cannot start battle later')
end
do
  local tr,battle,entered=new(false,false)
  tr:syncMusic(Music.playbackClock(nil))
  for _=1,600 do tr:update(1/60)end
  S.eq(entered(),0,'silent fallback ignores fast game ticks')
  for _=1,math.ceil(tr.nativeTransferTime*60)+1 do Music.update({});tr:update(1/60)end
  S.eq(entered(),1,'silent backend progresses from existing real-time audio ticks')
end
do
  local tr=new(false,false,'en')
  S.eq(tr.trainerBattle,nil,'non-Japanese transition contract unchanged')
  tr:syncMusic({position=function()return 999 end})
  S.eq(tr.nativeMusicClock,nil,'non-Japanese timing remains caller-owned')
end
S.finish()
