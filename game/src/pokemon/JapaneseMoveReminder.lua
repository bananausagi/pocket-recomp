-- Optional party-menu move reminder. Only the current species' imported
-- level-up learnset is eligible; this does not invent cross-generation moves.
local Reminder = {}
local Rules = require("src.core.JapaneseRules")
local HM = {CUT=true,FLY=true,SURF=true,STRENGTH=true,FLASH=true}

function Reminder.available(game, mon)
  if not (Rules.enabled(game,"jpMoveReminder") and game.save
      and game.overworld and game.stack and type(mon)=="table") then return false end
  if game.linkSession then return false end
  local worldFound, inParty = false, false
  for _, state in ipairs(game.stack.states or {}) do
    if state.isBattleState or state.battle then return false end
    if state == game.overworld then worldFound = true end
  end
  for _, member in ipairs(game.save.party or {}) do if member == mon then inParty=true end end
  local ow=game.overworld
  if not worldFound or not inParty or ow.transitioning or ow.engaging
      or (ow.player and ow.player.inputLocked) then return false end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return false end
  if ow.scriptMoves and #ow.scriptMoves>0 then return false end
  return type(mon.moves)=="table" and #mon.moves<=4
    and game.data.pokemon and type(game.data.pokemon[mon.species])=="table"
end

function Reminder.candidates(game, mon)
  local out, seen, known = {}, {}, {}
  if not Reminder.available(game,mon) then return out end
  for _, move in ipairs(mon.moves) do known[move.id]=true end
  local def=game.data.pokemon[mon.species]
  local function add(id)
    local move=game.data.moves and game.data.moves[id]
    if type(id)=="string" and id~="STRUGGLE" and not seen[id] and not known[id]
        and move and type(move.pp)=="number" and move.pp>0 then
      seen[id]=true;out[#out+1]=id
    end
  end
  for _, id in ipairs(def.level1Moves or {}) do add(id) end
  for _, entry in ipairs(def.learnset or {}) do
    if type(entry.level)=="number" and entry.level<=(tonumber(mon.level) or 0) then add(entry.move) end
  end
  return out
end

function Reminder.validate(game,mon,id,index,expected)
  if not Reminder.available(game,mon) then return false,"unavailable" end
  local found=false
  for _, candidate in ipairs(Reminder.candidates(game,mon)) do if candidate==id then found=true end end
  if not found then return false,"move" end
  if type(index)~="number" or index%1~=0 or index<1 or index>4
      or index>#mon.moves+1 then return false,"slot" end
  local old=mon.moves[index]
  if expected and (old~=expected.move or (old and (old.id~=expected.id
      or old.pp~=expected.pp or old.ppUps~=expected.ppUps))) then return false,"stale" end
  if old and HM[old.id] and not Rules.enabled(game,"jpForgetHM") then return false,"hm" end
  return true
end

function Reminder.snapshot(mon,index)
  local old=mon.moves[index]
  return {move=old,id=old and old.id,pp=old and old.pp,ppUps=old and old.ppUps}
end

function Reminder.apply(game,mon,id,index,expected)
  local ok,reason=Reminder.validate(game,mon,id,index,expected)
  if not ok then return false,reason end
  local old=mon.moves[index]
  local base=math.max(1,math.floor(game.data.moves[id].pp))
  -- Filling a genuinely empty slot is finite and starts usable. Replacing
  -- an existing slot must never become unlimited free PP restoration.
  local pp=old and math.max(0,math.min(base,math.floor(tonumber(old.pp) or 0))) or base
  mon.moves[index]={id=id,pp=pp}
  return true
end

function Reminder.addEntry(menu,items,mon)
  if menu.battle or not Reminder.available(menu.game,mon) then return end
  for _, item in ipairs(items) do
    if item.id=="jpMoveReminder" or item.action=="move_reminder"
        or item.action=="relearn" or item.label=="おもいだす" then return end
  end
  local entry={id="jpMoveReminder",label="おもいだす",onSelect=function(selected,game)
    if Reminder.available(game,selected) then
      game.stack:push(require("src.ui.JapaneseMoveReminderMenu").new(game,selected))
    end
  end}
  local at=#items+1
  for i,item in ipairs(items) do if item.action=="cancel" then at=i;break end end
  table.insert(items,at,entry)
end

return Reminder
