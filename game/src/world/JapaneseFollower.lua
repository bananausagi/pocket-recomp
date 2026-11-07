-- Optional Japanese companion. This is a presentation-only actor: it never
-- enters the NPC list, script runner, movement queue, or interaction system.
-- It follows the player's actual path (including analog coordinates), never
-- guesses a tile behind them through a wall. All runtime state lives on OW.
local Follower = {}
local TRAIL = 18
local MAX_JUMP = 64
local MAX_ID = 2147483646

local function validId(value)
  return type(value) == "number" and value > 0 and value <= MAX_ID and value % 1 == 0
end

local function enabled(game)
  return game and game.data and game.data.constants
    and game.data.constants.language == "ja" and game.save
    and (game.save.options or {}).jpFollower ~= false
end
Follower.enabled = enabled

local function partyIndex(game, mon)
  for index, member in ipairs(game.save and game.save.party or {}) do
    if member == mon then return index end
  end
end

function Follower.selected(game)
  local save = game and game.save
  if not save then return nil end
  local identity = save.jpFollowerIdentity
  local first, firstIndex, preferred, preferredIndex
  local matches=0
  for index, mon in ipairs(save.party or {}) do
    local matching=validId(identity) and type(mon)=="table" and mon.jpFollowerIdentity==identity
    if matching then matches=matches+1 end
    if type(mon) == "table" and (tonumber(mon.hp) or 0) > 0
        and game.data and game.data.pokemon and game.data.pokemon[mon.species] then
      if matching then preferred,preferredIndex=mon,index end
      if not first then first, firstIndex = mon, index end
    end
  end
  -- A local save-to-save trade may copy custom fields. Duplicate identities
  -- are ambiguous, so use automatic lead until the user explicitly chooses.
  if matches==1 and preferred then return preferred,preferredIndex end
  return first, firstIndex
end

function Follower.isSelected(game, mon)
  local identity = game and game.save and game.save.jpFollowerIdentity
  if not (validId(identity) and type(mon) == "table" and mon.jpFollowerIdentity == identity) then return false end
  local matches=0
  for _,member in ipairs(game.save.party or {}) do
    if member.jpFollowerIdentity==identity then matches=matches+1 end
  end
  return matches==1
end

local function blocked(game, ow)
  if not (enabled(game) and ow and ow.map and ow.player) then return true end
  local p, save = ow.player, game.save
  if game.linkSession or save.onBike or p.onBike or p.surfing or p.inputLocked
      or ow.transitioning or ow.engaging or ow.playerHidden or ow.cameraPan
      or ow.emote or ow.teleportOut or ow.flyAnim or ow.flyArrive
      or ow.spinArrive or ow.holeFall or ow.holeArrive or ow.healAnim
      or ow.fishing or ow.cutAnim or ow.pikaHop or ow.spinnerSliding then return true end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return true end
  if #(ow.scriptMoves or {}) > 0 or #(ow.pendingScripts or {}) > 0 then return true end
  -- No new companion during Oak's escort/selection/rival sequence. Never
  -- changes those flags or the native movement locks, even while B is held.
  local flags = save.flags or {}
  if not flags.EVENT_GOT_STARTER then return true end
  if ow.map.id == "OAKS_LAB" and not flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB then return true end
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.pikachuFollower then return true end -- native Yellow owns its actor
  end
  for _, state in ipairs(game.stack and game.stack.states or {}) do
    if state.isBattleState or state.isBattle or state.battle or state.trainerBattle
        or state.seamlessBattle or state.isBattleTransition then return true end
  end
  return false
end
Follower.blocked = blocked

function Follower.available(game, mon)
  if not (game and game.overworld and game.stack and partyIndex(game, mon))
      or blocked(game, game.overworld) or (tonumber(mon.hp) or 0) <= 0
      or not (game.data.pokemon and game.data.pokemon[mon.species]) then return false end
  for _, state in ipairs(game.stack.states or {}) do
    if state == game.overworld then return true end
  end
  return false
end

local function eachStoredMon(save, visit)
  for _, mon in ipairs(save.party or {}) do visit(mon) end
  for _, box in pairs(save.boxes or {}) do
    if type(box) == "table" then
      for _, mon in ipairs(box.mons or box) do if type(mon) == "table" then visit(mon) end end
    end
  end
  for _, mon in ipairs(save.box or {}) do visit(mon) end
  if save.daycare and type(save.daycare.mon) == "table" then visit(save.daycare.mon) end
  for _, mon in ipairs(save.orphaned and save.orphaned.mons or {}) do visit(mon) end
end

function Follower.select(game, mon)
  if not Follower.available(game, mon) then return false end
  local save, used = game.save, {}
  eachStoredMon(save, function(member)
    if member ~= mon and validId(member.jpFollowerIdentity) then used[member.jpFollowerIdentity] = true end
  end)
  local identity = mon.jpFollowerIdentity
  if not validId(identity) or used[identity] then
    identity = validId(save.jpFollowerNextIdentity) and save.jpFollowerNextIdentity + 1 or 1
    if identity > MAX_ID then identity = 1 end
    while used[identity] do identity = identity % MAX_ID + 1 end
    mon.jpFollowerIdentity = identity
    save.jpFollowerNextIdentity = identity
  end
  save.jpFollowerIdentity = identity
  return true
end

function Follower.clearSelection(game)
  if not (game and game.save) then return false end
  game.save.jpFollowerIdentity = nil
  return true
end

local function detach(ow)
  local state = ow and ow.jpFollowerState
  if not state then return end
  for i = #(ow.entities or {}), 1, -1 do
    if ow.entities[i] == state.actor then table.remove(ow.entities, i) end
  end
  state.attached = false
end

function Follower.reset(ow)
  if not ow then return end
  detach(ow)
  local state = ow.jpFollowerState
  if state and state.actor and state.actor.sprite and state.actor.sprite.release then
    state.actor.sprite:release()
  end
  ow.jpFollowerState = nil
end

local Actor = {}
Actor.__index = Actor
function Actor:pose()
  local phase = self.moving and math.floor(self.distance / 4) % 2 or 0
  -- Only BALL / HELIX keep the party list's one-pixel alternate-pose nudge.
  -- Other icons animate their own pixels, never the entire actor position.
  local dy = self.sprite.poseOffset and self.sprite:poseOffset(phase) or 0
  return self.sprite, self.px, self.py + dy, self.facing, phase,
    math.floor(self.distance / 16) % 2 == 1, false
end
function Actor:draw(camX, camY)
  local sprite, x, y, facing, phase, flip = self:pose()
  sprite:draw(x, y, camX, camY, facing, phase, flip)
end

local function start(game, ow, mon)
  local sprite = require("src.render.JapaneseFollowerSprite").new(game.data, mon)
  if not sprite then return nil end
  local p = ow.player
  local actor = setmetatable({id="jp_companion", jpFollower=true, passable=true,
    sprite=sprite, px=p.px, py=p.py, cellX=p.cellX, cellY=p.cellY,
    facing=p.facing or "down", moving=false, distance=0}, Actor)
  local state = {actor=actor, mon=mon, species=mon.species, map=ow.map,
    points={{x=p.px,y=p.py,d=0}}, total=0, attached=false}
  ow.jpFollowerState = state
  return state
end

local function attach(ow, state)
  if state.attached then return end
  ow.entities = ow.entities or {}
  for _, e in ipairs(ow.entities) do if e == state.actor then state.attached=true;return end end
  ow.entities[#ow.entities+1] = state.actor
  state.attached = true
end

local function facing(dx, dy, previous)
  if math.abs(dx) + math.abs(dy) < .0001 then return previous end
  if math.abs(dx) > math.abs(dy) then return dx > 0 and "right" or "left" end
  return dy > 0 and "down" or "up"
end

-- One call AFTER the authoritative player movement update. Neither this nor
-- draw preparation ever advances game logic, NPCs, input, audio, or a script.
function Follower.update(game, ow)
  if blocked(game, ow) then Follower.reset(ow);return end
  local mon = Follower.selected(game)
  if not mon then Follower.reset(ow);return end
  local state = ow.jpFollowerState
  if state and (state.mon ~= mon or state.species ~= mon.species or state.map ~= ow.map) then
    Follower.reset(ow);state=nil
  end
  if not state then state=start(game,ow,mon) end
  if not state then return end
  local p, points, actor = ow.player, state.points, state.actor
  local last = points[#points]
  local dx,dy = p.px-last.x,p.py-last.y
  local moved = math.sqrt(dx*dx+dy*dy)
  if moved > MAX_JUMP then
    Follower.reset(ow);start(game,ow,mon);return
  end
  -- Coalesce tiny analog samples. The error is below one eighth of a world
  -- pixel and limits the retained 18px path to at most 146 samples, even at
  -- the smallest stick deflection; no growing frame history or map search.
  if moved >= .125 then
    state.total=state.total+moved
    points[#points+1]={x=p.px,y=p.py,d=state.total}
  end
  local target = math.max(0,state.total-TRAIL)
  while #points > 2 and points[2].d <= target do table.remove(points,1) end
  local a,b=points[1],points[2] or points[1]
  local span=b.d-a.d
  local t=span>0 and math.max(0,math.min(1,(target-a.d)/span)) or 0
  local x,y=a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t
  local ax,ay=x-actor.px,y-actor.py
  actor.moving=math.abs(ax)+math.abs(ay)>.001
  actor.facing=facing(ax,ay,actor.facing)
  actor.px,actor.py,actor.distance=x,y,target
  actor.cellX,actor.cellY=math.floor((x+8)/16),math.floor((y+8)/16)
  -- A follower emerges from the player's own position after walking starts;
  -- never materialize one tile away through a wall on a load/warp/cutscene.
  if state.total >= 8 then attach(ow,state) end
end

-- Menus freeze OW:update while still rendering the world. Reconcile setting
-- changes, fainting, battle transitions, and scripts here too, so one stale
-- actor cannot leak into a new scene for a frame. Ordinary menus retain it.
function Follower.prepareDraw(game, ow)
  local state=ow and ow.jpFollowerState
  if not state then return end
  local mon=Follower.selected(game)
  if blocked(game,ow) or state.mon~=mon or state.species~=(mon and mon.species) then
    Follower.reset(ow)
  end
end

function Follower.onMapEntered(game, ow, opts)
  local state=ow.jpFollowerState
  if not state then return end
  if opts and opts.seamless then
    -- setMap has recreated entities. crossConnection rebases the preserved
    -- history immediately afterward, using exactly the player's translation.
    state.map=ow.map;state.attached=false
  else Follower.reset(ow) end
end

function Follower.rebase(ow, cellDX, cellDY)
  local state=ow and ow.jpFollowerState
  if not state then return end
  local dx,dy=cellDX*16,cellDY*16
  for _, point in ipairs(state.points) do point.x,point.y=point.x+dx,point.y+dy end
  local a=state.actor
  a.px,a.py=a.px+dx,a.py+dy
  a.cellX,a.cellY=a.cellX+cellDX,a.cellY+cellDY
  if state.total>=8 then attach(ow,state) end
end

function Follower.addEntry(menu, items, mon)
  local game=menu.game
  if menu.battle or not Follower.available(game,mon) then return end
  for _, item in ipairs(items) do if item.id=="jpFollower" then return end end
  local automatic=Follower.isSelected(game,mon)
  local entry={id="jpFollower",label=automatic and "せんとうに おまかせ" or "つれてあるく",
    onSelect=function(selected,currentGame)
      if not Follower.available(currentGame,selected) then return end
      if automatic and Follower.isSelected(currentGame,selected) then
        Follower.clearSelection(currentGame)
      elseif not Follower.select(currentGame,selected) then return end
      menu.submenu=nil
    end}
  local at=#items+1
  for index,item in ipairs(items) do if item.action=="cancel" then at=index;break end end
  table.insert(items,at,entry)
end

return Follower
