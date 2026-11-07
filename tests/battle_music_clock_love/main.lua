-- Real queueable OpenAL Source + authored ChipAsm, never ROM/audio assets.
local Music, ChipAudio, clock, source, data, started, began, heldAt, heldPosition
local last, checks, frames, crossings = 0, 0, {}, 0
local resultPath = assert(os.getenv('JP_QA_OUT'))
local function check(value, message)
  assert(value, message); checks=checks+1
end
local function finish(ok, err)
  local Json=require('src.link.Json')
  local f=assert(io.open(resultPath..'/chip-source-clock.json','wb'))
  f:write(assert(Json.encode({ok=ok,error=err,checks=checks,frames=frames,
    backend='LOVE 11.5 OpenAL null output; real Source; authored ChipAsm',
    physicalAudioVerified=false,cue=3.9,crossings=crossings})));f:close()
  ChipAudio.shutdown()
  if not ok then print(err) else print(checks..' real chip Source clock checks passed')end
  love.event.quit(ok and 0 or 1)
end
function love.load()
  local root=assert(os.getenv('JP_QA_ROOT'))
  package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
  Music=require('src.core.Music');ChipAudio=require('src.core.ChipAudio')
  local song=require('src.audio.ChipAsm').song({channels={{hw=1,program={
    {notetype={speed=12,volume=8,fade=0}},{octave=4},
    {note='C',len=8},{loop={count=0,to=1}},
  }}}})
  data={audio={songs={QA_CHIP=song}}}
  clock=Music.playbackClock(Music.play(data,'QA_CHIP'))
  source=ChipAudio.currentSource()
  began=love.timer.getTime()
end
local accum=0
function love.update(dt)
  local ok,err=xpcall(function()
    accum=accum+dt
    while accum>=1/60 do Music.update(data);accum=accum-1/60 end
    local now=love.timer.getTime()
    local at=clock:position()
    if source:isPlaying() and not started then started=now end
    check(at+1e-9>=last,'queue removals never rewind the music clock')
    -- Multiple fast-forward logic reads must track the same physical source.
    local fast=at
    for _=1,40 do fast=clock:position(1/60)end
    check(fast-at<love.timer.getTime()-now+.04,
      'fast logic reads follow wall playback within one mixer block')
    if not heldAt and at>.65 then
      local sd=love.sound.newSoundData(8000,8000,16,1)
      local fanfare=love.audio.newSource(sd,'static')
      fanfare:play();Music.duckForFanfare(fanfare)
      heldAt,heldPosition=now,clock:position()
    end
    if heldAt and now-heldAt<.85 then
      check(math.abs(at-heldPosition)<.04,'fanfare holds the actual source phase')
    end
    if started and (not heldAt or now-heldAt>1.12) then
      local elapsed=now-started-(heldAt and 1 or 0)
      check(math.abs(at-elapsed)<.15,'consumed PCM matches real playback across unqueues')
    end
    if at>=3.9 and last<3.9 then crossings=crossings+1 end
    if #frames==0 or (now-began)-frames[#frames].wall>.05 then
      frames[#frames+1]={wall=now-began,position=at,playing=source:isPlaying(),
        queued=source:getDuration('seconds'),relativeTell=source:tell('seconds')}
    end
    last=at
    if at>4.1 then
      check(crossings==1,'appearance cue crosses once')
      check(clock.synchronized,'cue uses PCM rather than silent fallback')
      finish(true)
    elseif now-began>12 then error('real audio clock did not reach cue')end
  end,debug.traceback)
  if not ok then finish(false,err)end
  love.timer.sleep(.005)
end
function love.draw()
  love.graphics.clear(.1,.15,.2)
  love.graphics.print(('Authored chip source: %.3f s'):format(last),12,16)
  love.graphics.rectangle('fill',12,50,math.min(296,last/3.9*296),12)
end
