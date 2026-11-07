-- Current-slot autosaves use the same capture, MOD veto and backup/recovery
-- path as a manual report. Never capture a half-finished field event.
local A={interval=60,quietTime=.75}
local sessions=setmetatable({},{__mode="k"})
local function state(game)
  local slot=require("src.core.SaveData").activeSlot("red_jp")
  local s=sessions[game]
  if not s or s.save~=game.save or s.slot~=slot then
    s={save=game.save,slot=slot,elapsed=0,quiet=0,cooldown=0}
    sessions[game]=s
  end
  return s
end
function A.enabled(game)
  return require("src.core.GameVersion").get()=="red_jp" and game.save
    and game.save.version=="red_jp" and game.save.options and game.save.options.jpAutoSave~=false
end
function A.safe(game)
  local ow=game.overworld
  if not (ow and ow.map and ow.player and game.stack and game.stack:top()==ow)
      or game.sessionMenu or game.linkSession or not game:quickSaveAllowed() then return false end
  if ow.healAnim or ow.fishing or ow.fishPose or ow.player.fishing or ow.cutAnim or ow.dustAnim or ow.pendingWarp
      or (ow.player.hopFrames or 0)>0 or (ow.parallelRunners and next(ow.parallelRunners)) then return false end
  return true
end
function A.noteWritten(game)
  if not A.enabled(game) then sessions[game]=nil;return end
  local s=state(game)
  s.elapsed,s.pending,s.cooldown=0,false,2
end
local function write(game,s)
  local ok,written=pcall(game.writeSave,game)
  if ok and written then A.noteWritten(game);return true end
  s.cooldown=15 -- failed storage or an intentional MOD veto must not spin
  return false
end
function A.update(game,dt)
  if not A.enabled(game) then sessions[game]=nil;return end
  local ow=game.overworld
  if not (ow and ow.map and ow.player) then sessions[game]=nil;return end
  local s=state(game)
  dt=math.max(0,math.min(dt or 0,.25))
  s.elapsed=s.elapsed+dt;s.cooldown=math.max(0,s.cooldown-dt)
  local top=game.stack and game.stack:top()
  if (s.map and s.map~=ow.map) or (s.top and s.top~=ow and top==ow)
      or (s.healing and not ow.healAnim) or s.elapsed>=A.interval then s.pending=true end
  s.map,s.top,s.healing=ow.map,top,ow.healAnim
  local p=ow.player
  if A.safe(game) and s.x==p.px and s.y==p.py then s.quiet=s.quiet+dt else s.quiet=0 end
  s.x,s.y=p.px,p.py
  if s.pending and s.cooldown<=0 and s.quiet>=A.quietTime then write(game,s) end
end
function A.flush(game)
  local s=sessions[game]
  if A.enabled(game) and s and s.save==game.save and s.quiet>=A.quietTime
      and s.slot==require("src.core.SaveData").activeSlot("red_jp")
      and s.cooldown<=0 and A.safe(game) then return write(game,s) end
  return false
end
return A
