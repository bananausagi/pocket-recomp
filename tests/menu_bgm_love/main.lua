-- Real threaded ChipAudio and OpenAL QueueableSource, authored chip notes only.
-- Native Options/MOD and SessionMenu dwell exceed the complete 22050 Hz queue.
local Game, Music, Chip, source, clock, Input, Stack, Data
local checks, frames, phase, elapsed, started = 0, {}, 1, 0, false
local worldTicks, baselineTime, trackTime, last, menuCreated, fanfareAt = 0, 321, 0, 0, false
local fanfareDone, fanfarePhase, muteSeen, holdChecked = false, 0, false, false
local out = assert(os.getenv('JP_QA_OUT'))
local stages = {
  { name = 'native-options', duration = 14 },
  { name = 'native-mod-manager', duration = 3 },
  { name = 'session-settings-files', duration = 14 },
  { name = 'resume-world', duration = 1 },
  { name = 'reopen-session', duration = 2 },
}
local function check(v, label)
  assert(v, label); checks = checks + 1; print('PASS ' .. label)
end
local function finish(ok, err)
  local f = assert(io.open(out .. '/real-source.json', 'wb'))
  f:write(require('src.link.Json').encode({ ok = ok, error = err, checks = checks,
    backend = 'LOVE 11.5; real threaded ChipAudio; real OpenAL null-output QueueableSource',
    physicalDeviceAudioVerified = false, sampleRate = 22050,
    completeQueueSeconds = 8192 * 32 / 22050,
    frames = frames, worldTicks = worldTicks, audioStats = Chip.stats(),
    stages = stages })); f:close()
  Chip.shutdown(); if not ok then print(err) end
  love.event.quit(ok and 0 or 1)
end
local function choose(id)
  local menu = Stack:top()
  for _, row in ipairs(menu.items or {}) do
    if row.id == id then row.onSelect(); return end
  end
  error('missing native START row ' .. id)
end
local function openPhase()
  local name = stages[phase].name
  if Game.sessionMenu then Game:closeSessionMenu() end
  Stack.states = { Game.overworld }
  if name == 'native-options' or name == 'native-mod-manager' then
    Game:openSessionMenu()
    check(Stack:top().isSystemMenuRoot, name .. ': opens actual native START')
    choose(name == 'native-options' and 'system-settings' or 'system-mods')
    check(Stack:top().systemMenuPause, name .. ': enters actual paused floating screen')
  elseif name ~= 'resume-world' then
    Game:openSessionMenu('settings-files')
    check(Game.sessionMenu ~= nil, name .. ': opens actual session overlay')
  end
  elapsed, trackTime, last = 0, clock:position(), clock:position()
  baselineTime = Game.save.playTime
end
function love.load()
  local root = assert(os.getenv('JP_QA_ROOT'))
  package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
  Data = require('src.core.Data'); Data.constants = { language = 'ja' }; Data.field = {}
  Data.render_pipelines = {}
  require('src.core.GameVersion').set('red_jp')
  Game = require('src.core.Game'); Input = require('src.core.Input'); Input:init()
  Stack = require('src.core.StateStack'); Stack:init()
  require('src.core.TouchControls'):init()
  Game.data, Game.stack, Game.input = Data, Stack, Input
  Game.save = require('src.core.SaveData').newGame()
  Game.save.options.musicVol = 7; Game.save.playTime = baselineTime
  Game.save.party = {}; Game.save.flags = {}
  Game.writeOptions = function() return true end
  Game.updateSync = function() end
  Game.mods = { releaseModInput = function() end,
    status = function() return { available = {}, errors = {} } end }
  Game.modStatus = { available = { { id = 'QA', enabled = true } }, errors = {} }
  Game.overworld = { isOverworld = true, player = { moving = false }, scriptMoves = {},
    runner = { isRunning = function() return false end },
    update = function() worldTicks = worldTicks + 1 end }
  require('src.core.FixedStep'):init(function(dt) Game:step(dt) end)
  require('src.render.Pipelines').install(Data)
  Music, Chip = require('src.core.Music'), require('src.core.ChipAudio')
  Chip.setSampleRate(22050)
  local song = require('src.audio.ChipAsm').song({ channels = { { hw = 1, program = {
    { notetype = { speed = 12, volume = 8, fade = 0 } }, { octave = 4 },
    { note = 'C', len = 8 }, { loop = { count = 0, to = 1 } },
  } } } })
  Data.audio = { songs = { QA_MENU = song } }
  Music.setVolumeLevel(7)
  clock = Music.playbackClock(Music.play(Data, 'QA_MENU'))
  source = Chip.currentSource()
  openPhase()
end
function love.update(dt)
  local ok, err = xpcall(function()
    Game:update(dt)
    if not started then
      if source:isPlaying() then
        started = true; elapsed, trackTime = 0, clock:position()
        check(Chip.stats().worker ~= 'sync', 'actual worker thread supplies PCM')
      end
      return
    end
    elapsed = elapsed + dt
    local name = stages[phase].name
    local at = clock:position()
    assert(at + 1e-6 >= last, 'consumed PCM clock must not rewind across queue removals')
    assert(Chip.currentSource() == source, 'opening/closing menus must retain source identity')
    local playing = source:isPlaying()
    if name == 'session-settings-files' then
      if not fanfareAt and elapsed > 2 then
        local silence = love.sound.newSoundData(22050, 22050, 16, 1)
        local sfx = love.audio.newSource(silence, 'static'); sfx:play()
        Music.duckForFanfare(sfx); fanfareAt, fanfarePhase = elapsed, clock:position()
      elseif fanfareAt and elapsed - fanfareAt < .85 then
        assert(math.abs(at - fanfarePhase) < .05, 'menu pump must not unpause an active fanfare')
        holdChecked = true
      elseif fanfareAt and not fanfareDone and elapsed - fanfareAt > 1.2 then
        check(playing and at > fanfarePhase, 'map music resumes when fanfare completes under menu')
        fanfareDone = true
      end
      if elapsed > 5 and not muteSeen then
        Music.setVolumeLevel(0); muteSeen = true
      end
      if muteSeen then assert(source:getVolume() == 0, 'muted setting remains silent under menu pump') end
    end
    if not fanfareAt or name ~= 'session-settings-files' or elapsed - fanfareAt > 1.2 then
      assert(playing, 'BGM must remain playing beyond entire buffered queue')
    end
    if name ~= 'resume-world' then
      assert(Game.save.playTime == baselineTime, 'audio service cannot advance gameplay playtime')
    end
    if #frames == 0 or frames[#frames].phase ~= phase or elapsed - frames[#frames].elapsed > .5 then
      frames[#frames + 1] = { phase = phase, name = name, elapsed = elapsed, position = at,
        playing = playing, volume = source:getVolume(), queueDepth = Chip.stats().depth,
        playTime = Game.save.playTime, worldTicks = worldTicks }
    end
    last = at
    if elapsed > stages[phase].duration then
      local held = name == 'session-settings-files' and 1 or 0
      check(math.abs((at - trackTime) - (elapsed - held)) < .18,
        name .. ': PCM position advances at wall-clock pace, without duplicate pumping')
      if name ~= 'resume-world' then
        check(Game.save.playTime == baselineTime, name .. ': gameplay/playtime stays paused')
      else
        check(worldTicks > 0, 'closing menu resumes actual fixed-step world')
      end
      if name == 'session-settings-files' then
        check(holdChecked and fanfareDone, 'fanfare pauses and resumes song during prolonged menu')
        check(muteSeen and source:getVolume() == 0, 'configured mute stays zero while menu streaming continues')
        Music.setVolumeLevel(7)
      end
      phase = phase + 1
      if phase > #stages then
        check(clock.synchronized, 'music cursor remains actual PCM synchronized')
        finish(true); return
      end
      openPhase()
    end
  end, debug.traceback)
  if not ok then finish(false, err) end
  love.timer.sleep(.005)
end
function love.draw()
  love.graphics.clear(.1, .15, .2)
  love.graphics.print((stages[phase] and stages[phase].name or 'complete') .. '\n'
    .. ('%.2f seconds; PCM %.2f'):format(elapsed, last), 12, 16)
end
