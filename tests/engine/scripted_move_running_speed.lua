-- Held-B/manual speed modifiers must not accelerate scripted escorts.
-- Retain bike/slope timing, explicit NPC speeds and manual ledge arcs.
package.path = './?.lua;./?/init.lua;' .. package.path
if not love then love = require('tests.love_stub') end
local T = require('tests.harness').suite('Scripted movement speed ownership')
local Game = require('src.core.Game')
local Player = require('src.world.Player')
local NPC = require('src.world.NPC')
local OW = require('src.world.OverworldController')
local Runtime = require('src.mods.Runtime')
local Hooks = require('src.mods.Hooks')
local data = require('tests.fixture_data').load()
data.field.playerSprites = { walk = 'SPRITE_FIX_PLAYER' }
Game.data, Game.save = data, { onBike = false }
Game.input = { isDown = function(_,key) return key == 'b' end }
local previous = Runtime.hooks
local hooks = Hooks.new()
local calls = 0
hooks:wrap('movement.speed', function(next, frames)
  calls = calls + 1
  return next(frames) / 2
end, 0, 'running-speed-test')
Runtime.hooks = hooks
for _,case in ipairs({
  {name='walk',bike=false,dir='down',base=16},
  {name='bike',bike=true,dir='down',base=8},
  {name='bike uphill',bike=true,slope=true,dir='up',base=16},
  {name='bike downhill',bike=true,slope=true,dir='down',base=8},
})do
  Game.save.onBike = case.bike
  local p = Player.new(data,4,4,case.dir)
  p.slopeMap = case.slope
  T.eq(p:stepLength(case.dir),case.base/2,case.name..': manual running stays available')
  local before = calls
  local ow = setmetatable({scriptMoves={}}, {__index=OW})
  local completed = false
  ow:scriptMove(p,case.dir,1,function() completed=true end)
  ow:updateScriptMoves()
  T.eq(p.stepFramesCur,case.base,case.name..': scripted move uses base duration')
  T.eq(calls,before,case.name..': scripted start never calls manual modifier')
  for _=1,case.base-1 do p:update();ow:updateScriptMoves()end
  T.check(not completed,case.name..': does not complete early')
  p:update();ow:updateScriptMoves()
  T.check(completed and #ow.scriptMoves==0,case.name..': completes on the intended frame')
end
Game.save.onBike = false
do
  local npc = NPC.new(data,'FIX_TOWN',{index=1,x=4,y=4,sprite='SPRITE_FIX_NPC',movement='STAY',range='NONE'})
  npc.stepFrames = 6
  local ow = setmetatable({scriptMoves={}}, {__index=OW})
  local completed = false
  ow:scriptMove(npc,'down',1,function() completed=true end)
  ow:updateScriptMoves()
  for _=1,5 do npc:update({},{});ow:updateScriptMoves()end
  T.check(not completed,'explicit NPC duration is not shortened')
  npc:update({},{});ow:updateScriptMoves()
  T.check(completed and npc.stepFrames==6,'explicit NPC duration remains owned by the event')
end
do
  Game.save.onBike = true
  local p = Player.new(data,4,4,'down')
  p.ledgeHop = true
  local arc = p:stepLength() * 2
  local ow = setmetatable({scriptMoves={}}, {__index=OW})
  local completed = false
  ow:scriptMove(p,'down',2,function() completed=true end)
  ow:updateScriptMoves()
  T.eq(p.stepFramesCur,8,'manual ledge hop retains running speed and ignores bike boost')
  for _=1,arc-1 do p:update();ow:updateScriptMoves()end
  T.check(not completed,'ledge movement lasts as long as its original arc')
  p:update();ow:updateScriptMoves()
  T.check(completed and p.cellY==6,'ledge arc and two-cell movement finish together')
end
Runtime.hooks = previous
T.finish()
