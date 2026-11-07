-- Actual OpenAL file Source with low-cost drawing isolates presentation
-- clock accuracy from the full renderer's software-GL/readback overhead.
local Music,Transition,Battle,Json,data,current,out,started,accum= nil,nil,nil,nil,nil,nil,nil,nil,0
local checks,results,index=0,{},0
local cases={{'original',1},{'original',4},{'focus',1},{'focus',4}}
local focus=false
function love.errorhandler(message)
  print(debug.traceback(message));io.stdout:flush()
  return function()return 1 end
end
local function check(ok,msg)assert(ok,msg);checks=checks+1;print('PASS '..msg)end
local function finish(ok,err)
  local f=assert(io.open(out..'/low-cost-source.json','wb'))
  f:write(Json.encode({ok=ok,error=err,checks=checks,cases=results,
    backend='Love 11.5 actual OpenAL Source, null output; authored PCM',physicalAudioVerified=false}));f:close()
  Music.stop();if err then print(err)end;love.event.quit(ok and 0 or 1)
end
local function nextCase()
  index=index+1
  if not cases[index] then finish(true);return end
  local mode,speed=unpack(cases[index]);focus=mode=='focus';Music.stop()
  local game={data=data,save={options={}},renderer={}}
  local battle=setmetatable({kind='trainer',game=game,data=data,frame=0,
    lowHealthAlarmActive=function()return false end,wideLayout=function()return false end,
    drawClassic=function()end},{__index=Battle})
  local rec={mode=mode,speed=speed,game=game,battle=battle,sourceStarts=0}
  local transition
  game.stack={pop=function()transition:exit()end}
  transition=Transition.new(game,function()
    rec.inBattle=true;rec.entry=rec.clock:position()
    battle.introSlide=72-(battle.jpEncounterIntroCredit or 0);battle.jpEncounterIntroCredit=nil
    check(Music.play(data,'QA_TRAINER')==rec.playback,'enter deduplicates exact existing Source')
  end,{battle=battle,trainer=true})
  rec.playback=Music.play(data,'QA_TRAINER');check(rec.playback~=nil,'authored PCM starts a real source')
  rec.sourceStarts=rec.sourceStarts+1
  rec.clock=Music.playbackClock(rec.playback);transition:syncMusic(rec.clock)
  rec.transition=transition;rec.cue=transition.revealTime;rec.expectedEntry=transition.nativeTransferTime
  rec.began=love.timer.getTime();current=rec
end
function love.load()
  local root=assert(os.getenv('JP_QA_ROOT'));out=assert(os.getenv('JP_QA_OUT'))
  package.path=root..'/?.lua;'..package.path
  package.loaded['src.mods.Runtime']={wantsHook=function()return false end,wants=function()return false end,emit=function()end,
    call=function(name,default,ctx)
      if name=='battle.transition.trainerFocus' then return focus end
      return default(ctx)
    end}
  package.loaded['src.battle.JapaneseBattleLayout']={active=function()return false end}
  Music=require('src.core.Music');Transition=require('src.render.BattleTransition')
  Battle=require('src.battle.BattleState');Json=require('src.link.Json')
  local samples={};for i=0,80000-1 do samples[#samples+1]=love.data.pack('string','<i2',math.floor(math.sin(i*math.pi*440/4000)*2000))end
  local pcm=table.concat(samples)
  local wav='RIFF'..love.data.pack('string','<I4',36+#pcm)..'WAVEfmt '..love.data.pack('string','<I4I2I2I4I4I2I2',16,1,1,8000,16000,2,16)
    ..'data'..love.data.pack('string','<I4',#pcm)..pcm
  assert(love.filesystem.write('trainer.wav',wav))
  data={constants={language='ja'},audio={songs={QA_TRAINER={file='trainer.wav'}}}}
  started=love.timer.getTime();nextCase()
end
function love.update(dt)
  local ok,err=xpcall(function()
    local r=current;if not r then return end
    accum=accum+dt;while accum>=1/60 do Music.update(data);accum=accum-1/60 end
    for _=1,r.speed do
      if r.inBattle then r.battle:updateFx()else r.transition:update(1/60)end
    end
    if r.inBattle and r.battle.introSlide==0 and not r.landed then r.landed=r.clock:position()end
    if r.firstDraw and r.landed and r.clock:position()>r.cue+.10 then
      check(r.clock.synchronized,'trainer uses actual source phase')
      check(r.entry>=r.expectedEntry-1e-6 and r.entry-r.expectedEntry<.08,'entry within80ms of physical Source cue')
      check(r.landed>=r.cue-1e-6 and r.landed-r.cue<.08,'complete intro within80ms of same physical music phase')
      check(r.firstDraw>=r.expectedEntry-1e-6 and r.firstDraw-r.expectedEntry<.08,'first physical draw on entry cue')
      results[#results+1]={mode=r.mode,speed=r.speed,cue=r.cue,expectedEntry=r.expectedEntry,
        entry=r.entry,firstDraw=r.firstDraw,landed=r.landed,sourceStarts=r.sourceStarts}
      nextCase()
    end
    assert(love.timer.getTime()-started<35,'source test timed out')
  end,debug.traceback)
  if not ok then finish(false,err)end
  love.timer.sleep(.003)
end
function love.draw()
  if not current then return end
  local r=current
  love.graphics.clear(.1,.15,.2)
  if r.inBattle then
    r.battle:draw();r.firstDraw=r.firstDraw or r.clock:position()
  else r.transition:draw()end
  love.graphics.print(r.mode..' '..r.speed..'x '..string.format('%.3f',r.clock:position()),12,16)
end
