-- ROM-free transport regression: visuals follow consumed PCM, including the
-- queue-relative tell() used by LÖVE, rather than logic ticks or queued audio.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local function near(actual, expected, message)
  check(type(actual) == "number" and math.abs(actual - expected) < 1e-8,
    message .. " (got " .. tostring(actual) .. ", want " .. expected .. ")")
end

love = require("tests.love_stub")
local ChipSynth = require("src.core.ChipSynth")
local RATE, BUF = ChipSynth.SAMPLE_RATE, ChipSynth.MUSIC_BUFFER_SAMPLES
local CAPACITY = ChipSynth.MUSIC_BUFFER_COUNT
local sources = {}
local Source = {}
Source.__index = Source
function Source:play() self.playing = true end
function Source:pause() self.playing = false end
function Source:stop() self.playing = false end
function Source:isPlaying() return self.playing == true end
function Source:setLooping(v) self.looping = v end
function Source:setVolume(v) self.volume = v end
function Source:setPitch(v) self.pitch = v end
function Source:setFilter() end
function Source:getFreeBufferCount() return CAPACITY - #self.buffers end
function Source:queue(sd)
  if self.rejectQueue or #self.buffers == CAPACITY then return false end
  local samples = sd:getSampleCount()
  self.buffers[#self.buffers + 1] = samples
  self.buffered = self.buffered + samples
  return true
end
function Source:getDuration(unit)
  local samples = self.queueable and self.buffered or self.duration * self.rate
  return unit == "samples" and samples or samples / self.rate
end
function Source:tell(unit)
  if self.failTell then error("position unavailable") end
  if self.onTell then self:onTell() end
  return unit == "samples" and self.offset or self.offset / self.rate
end
function Source:advance(samples)
  if not self.playing then return end
  self.offset = self.offset + samples
end
function Source:unqueue(n)
  for _ = 1, n do
    local samples = assert(table.remove(self.buffers, 1), "no buffer to unqueue")
    assert(self.offset >= samples, "cannot unqueue unplayed samples")
    self.buffered = self.buffered - samples
    self.offset = self.offset - samples
  end
end
local function source(options)
  options.rate, options.offset = options.rate or RATE, 0
  options.duration, options.buffered = options.duration or 2, 0
  options.buffers = {}
  setmetatable(options, Source)
  sources[#sources + 1] = options
  return options
end
love.audio = {
  newSource = function(file) return source({ file = file }) end,
  newQueueableSource = function(rate) return source({ queueable = true, rate = rate }) end,
}

local channels, generation, epoch = {}, 0, 0
local Channel = {}
Channel.__index = Channel
function Channel:push(message)
  if type(message) == "table" and message.cmd == "play" then
    generation, epoch = message.gen, message.stereoEpoch
  end
  self.queue[#self.queue + 1] = message
end
function Channel:pop() return table.remove(self.queue, 1) end
function Channel:clear() self.queue = {} end
function Channel:getCount() return #self.queue end
local function channel(name)
  channels[name] = channels[name] or setmetatable({ queue = {} }, Channel)
  return channels[name]
end
love.thread = {
  getChannel = channel,
  newThread = function()
    return { start = function() end, getError = function() end, wait = function() end }
  end,
}

local ChipAsm = require("src.audio.ChipAsm")
local chipSong = ChipAsm.song({ channels = { { hw = 1, program = {
  { notetype = { speed = 12, volume = 12, fade = 0 } },
  { octave = 4 }, { note = "C", len = 8 }, { loop = { count = 0, to = 1 } },
} } } })
local data = { audio = { songs = {
  Music_Chip = chipSong,
  Music_File = { file = "battle.ogg" },
  Music_Other = { file = "victory.ogg" },
  Music_Intro = { file = "intro.ogg", loopFile = "loop.ogg" },
} } }
local ChipAudio = require("src.core.ChipAudio")
local Music = require("src.core.Music")
local function start(song)
  Music.stop()
  local playback = Music.play(data, song)
  check(playback ~= nil, song .. " has a playback identity")
  return Music.playbackClock(playback), playback.source, playback
end
local function deliver(n, gen, mix)
  for _ = 1, n do
    channel("chipaudio_out"):push({ gen = gen or generation,
      stereoEpoch = mix or epoch,
      sd = love.sound.newSoundData(BUF, RATE, 16, 2) })
  end
end
local function audioTicks(n)
  for _ = 1, n do Music.update(data) end
end

-- A file source supplies real phase; repeated logic work cannot advance it.
local clock, src, identity = start("Music_File")
check(clock.synchronized, "file position is available immediately")
for _ = 1, 600 do clock:position() end
near(clock:position(10), 0, "logic ticks and caller dt cannot outrun sounding audio")
src:advance(RATE / 4)
near(clock:position(), .25, "file clock follows samples actually played")
eq(Music.play(data, "Music_File"), identity, "deduped song retains its identity")

local fanfare = source({})
fanfare:play()
Music.duckForFanfare(fanfare)
check(not src:isPlaying(), "fanfare pauses the file source")
src:advance(RATE)
near(clock:position(1), .25, "fanfare pause retains file phase")
fanfare:stop()
Music.update(data)
check(src:isPlaying(), "file source resumes after fanfare")
src:advance(RATE / 4)
near(clock:position(), .5, "resumed file clock continues from the paused phase")

Music.play(data, "Music_Other")
audioTicks(15)
near(clock:position(.125), .75, "replaced song uses audio-clock fallback from last phase")
check(not clock.synchronized, "old encounter cannot synchronize to victory song")
for _ = 1, 600 do clock:position(1 / 60) end
near(clock:position(), .75, "fallback receives no time from fast logic updates")

clock, src = start("Music_File")
src:advance(RATE / 2)
near(clock:position(), .5, "source phase is established before a tell failure")
src.failTell = true
audioTicks(15)
near(clock:position(.125), .75, "unsupported position falls back without rewinding")
check(not clock.synchronized, "failed tell is reported as unsynchronized")
Music.stop()
audioTicks(15)
near(clock:position(.125), 1, "stopping music cannot strand the encounter")
local silent = Music.playbackClock(nil)
audioTicks(15)
near(silent:position(.25), .25, "silent encounters use real-time audio ticks")
near(silent:position(-1), .25, "negative fallback dt cannot rewind presentation")

clock, src = start("Music_File")
src.getDuration = function() return -1 end -- actual LÖVE null Source contract
audioTicks(15)
near(clock:position(), .25, "no-device null file Source cannot freeze the camera")
check(not clock.synchronized, "null file Source is explicitly unsynchronized")

-- Stream intro and loop replacement are one continuous musical playback.
clock, src = start("Music_Intro")
src:advance(RATE * 1.5)
near(clock:position(), 1.5, "intro clock reaches its current phase")
src.offset, src.playing = RATE * 2, false
Music.update(data)
local loop = sources[#sources]
loop:advance(RATE / 4)
near(clock:position(), 2.25, "intro-to-loop handoff retains intro duration")
loop.offset = RATE * 1.75
near(clock:position(), 3.75, "loop progresses after intro")
loop.offset = RATE / 4
near(clock:position(), 4.25, "loop wrap preserves accumulated musical phase")

-- Threaded startup can queue audio long before any of it reaches the device.
clock, src, identity = start("Music_Chip")
local realDuration = src.getDuration
src.getDuration = function() return -1 end
audioTicks(15)
near(clock:position(), .25, "no-device null queueable Source cannot wait forever on preroll")
src.getDuration = realDuration
clock, src, identity = start("Music_Chip")
near(clock:position(2), 0, "empty chip preroll does not spend presentation time")
deliver(ChipAudio.MUSIC_PREROLL - 1)
ChipAudio.update()
check(not src:isPlaying(), "partial preroll has not started the source")
near(clock:position(2), 0, "queued preroll is not elapsed audio")
deliver(1)
ChipAudio.update()
check(src:isPlaying(), "complete preroll starts playback")
near(clock:position(2), 0, "starting playback alone consumes no PCM")
src:advance(BUF + RATE / 60)
local played = (BUF + RATE / 60) / RATE
near(clock:position(), played, "chip clock includes processed and current buffers")
src:unqueue(1)
near(clock:position(), played, "queue-relative tell reset preserves total elapsed audio")
deliver(1)
ChipAudio.update()
near(clock:position(), played, "refilling queue does not move the playback clock")

-- LÖVE can remove processed buffers on its audio thread between observations.
src:advance(BUF)
played = played + BUF / RATE
src.onTell = function(self) self.onTell = nil; self:unqueue(1) end
near(clock:position(), played, "concurrent unqueue is retried as a coherent snapshot")
deliver(1)
ChipAudio.update()

-- Rejecting a queue, or discarding obsolete worker output, contributes no PCM.
src.rejectQueue = true
deliver(1)
ChipAudio.update()
near(clock:position(), played, "rejected queue does not inflate consumed sample count")
src.rejectQueue = false
ChipAudio.update()
near(clock:position(), played, "retrying pending buffer counts it exactly once")
deliver(1, generation - 1, epoch)
deliver(1, generation, epoch + 1)
ChipAudio.update()
near(clock:position(), played, "stale song and stereo worker buffers contribute no time")

fanfare = source({})
fanfare:play()
Music.duckForFanfare(fanfare)
src:advance(RATE)
for _ = 1, 600 do clock:position(1 / 60) end
near(clock:position(), played, "chip fanfare hold freezes through repeated fast logic reads")
check(clock.synchronized, "legitimate chip pause retains synchronization")
fanfare:stop()
Music.update(data)
src:advance(RATE / 60)
played = played + 1 / 60
near(clock:position(), played, "chip phase resumes with the source after fanfare")

ChipAudio.setSuspended(true)
near(clock:position(1), played, "device suspension does not fabricate consumed audio")
ChipAudio.setSuspended(false)
check(ChipAudio.rebuildPlayback(), "device reset replaces playback source")
Music.onDeviceReset()
audioTicks(15)
near(clock:position(.25), played + .25, "source replacement switches to audio-clock fallback")
check(not clock.synchronized, "replacement source cannot pretend to retain old PCM phase")
deliver(ChipAudio.MUSIC_PREROLL)
ChipAudio.update()
ChipAudio.currentSource():advance(RATE)
near(clock:position(), played + .25, "new source phase cannot advance the captured old clock")

-- Starting a new chip song under an existing fanfare must also retain zero.
fanfare = source({})
fanfare:play()
Music.duckForFanfare(fanfare)
clock, src = start("Music_Chip")
deliver(ChipAudio.MUSIC_PREROLL)
ChipAudio.update()
near(clock:position(3), 0, "song cued mid-fanfare stays at its first musical sample")
check(not src:isPlaying(), "prerolled chip source respects existing fanfare hold")
fanfare:stop()
Music.update(data)
check(src:isPlaying(), "held new song starts after fanfare ends")
src:advance(RATE / 60)
near(clock:position(), 1 / 60, "held new song clock starts with the source")

Music.stop()
ChipAudio.shutdown()
T.finish("battle music playback clock")
