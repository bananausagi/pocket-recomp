-- ROM-free: run actual Gen 1 award queues, MoveLearnMenu and bag teach flows.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Data = T.fixtures.fresh()
Data.constants.language = "ja"
require("src.render.Font").load(Data)
require("src.battle.TypeChart").load(Data)
local Rules = require("src.core.JapaneseRules")
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local Growth = require("src.pokemon.Growth")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local MoveLearnMenu = require("src.ui.MoveLearnMenu")
local BagMenu = require("src.ui.BagMenu")
local Json = require("src.link.Json")

local function gameNew()
  local save = SaveData.newGame()
  save.player.id, save.player.name = 1234, "RED"
  save.options.jpPartyExp, save.options.jpForgetHM, save.options.jpReusableTM = false, false, false
  save.party = {}
  local stack = setmetatable({}, {__index = StateStack})
  stack:init()
  local game = {data=Data, save=save, stack=stack,
    input={wasPressed=function()return false end,isDown=function()return false end}}
  return game
end
local function monNew(game, level)
  local mon = Pokemon.new(Data, "FIXMON_A", level or 50, function(_,b)return b end)
  mon.otId = game.save.player.id
  game.save.party[#game.save.party+1] = mon
  return mon
end
local function expCase(convenient, expAll, trainer)
  local game = gameNew()
  game.save.options.jpPartyExp = convenient
  game.save.inventory.EXP_ALL = expAll and 1 or nil
  local p = {}
  for i=1,6 do p[i]=monNew(game,i==6 and 100 or 50) end
  p[4].otId, p[5].hp = 4321, 0
  local battle = BattleState.newWild(game,"FIXMON_C",10)
  battle.kind = trainer and "trainer" or "wild"
  battle.queue, battle.nextInsert = {},0
  battle.participants = {[p[1]]=true,[p[2]]=true}
  local before={};for i,m in ipairs(p)do before[i]=m.exp end
  battle:awardExp()
  local gain={};for i,m in ipairs(p)do gain[i]=m.exp-before[i] end
  return game,battle,gain
end

do
  local opts={displayMode="custom",battleSpacing="wide",modOptions={keep=true}}
  T.eq(Rules.preset(opts),"classic","missing options keep original behavior")
  T.check(Rules.applyPreset(opts,"convenient"),"convenience preset accepted")
  for _,k in ipairs(Rules.keys)do T.eq(opts[k],true,"preset enables "..k)end
  T.eq(Rules.preset(opts),"convenient","convenience preset detected")
  opts.jpForgetHM=false
  T.eq(Rules.preset(opts),"custom","independent override detected")
  local before=Json.encode(opts)
  T.eq(Rules.applyPreset(opts,"invalid"),false,"invalid preset refused")
  T.eq(Json.encode(opts),before,"invalid preset never mutates options")
  Rules.applyPreset(opts,"classic")
  T.eq(opts.displayMode,"custom","preset preserves display")
  T.eq(opts.battleSpacing,"wide","preset preserves layout")
  T.eq(opts.modOptions.keep,true,"preset preserves MODs")
  for _,k in ipairs(Rules.keys)do T.eq(opts[k],false,"classic clears "..k)end
end

-- Species base 66 at Lv10: classic base-first split=47; EXP.ALL first
-- half=22 and all-party pass=2. Convenience full=94, bench=47. Traded
-- bench uses floor(94*1.5)/2=70, rather than Gen1's base-first halving.
for _,trainer in ipairs({false,true})do
  for _,expAll in ipairs({false,true})do
    local _,b,g=expCase(false,expAll,trainer)
    local classic=trainer and (expAll and 36 or 70) or (expAll and 24 or 47)
    T.eq(g[1],classic,"classic participant1 "..tostring(trainer).."/"..tostring(expAll))
    T.eq(g[2],classic,"classic participant2 split retained")
    T.eq(g[3],expAll and (trainer and 3 or 2) or 0,"classic bench only EXP.ALL")
    T.eq(g[4],expAll and (trainer and 4 or 3) or 0,"classic traded EXP.ALL")
    T.eq(g[5],0,"classic fainted skipped")
    T.eq(g[6],expAll and (trainer and 3 or 2) or 0,"classic level100 behavior unchanged")
    T.eq(next(b.participants),nil,"participant flags cleared")

    local game,modern,m=expCase(true,expAll,trainer)
    T.eq(m[1],trainer and 141 or 94,"full solo EXP for participant1")
    T.eq(m[2],trainer and 141 or 94,"full solo EXP for participant2")
    T.eq(m[3],trainer and 70 or 47,"half final EXP for bench")
    T.eq(m[4],trainer and 105 or 70,"bench traded/trainer rounding")
    T.eq(m[5],0,"convenience skips fainted")
    T.eq(m[6],0,"convenience skips level100")
    T.eq(game.save.party[1].statExp.hp,44,"participant full stat EXP")
    T.eq(game.save.party[3].statExp.hp,22,"bench half stat EXP")
    T.eq(game.save.party[5].statExp.hp,0,"fainted no stat EXP")
    local lines=0
    for _,row in ipairs(modern.queue)do
      if row.text then
        lines=lines+1
        T.check(not row.text:find("EXP.ALL",1,true),"no misleading EXP.ALL line in convenience mode")
      end
    end
    T.eq(lines,4,"one experience line per eligible member, never double EXP.ALL")
  end
end

do
  local game=gameNew();game.save.options.jpPartyExp=true
  local active=monNew(game,100)
  local bench=monNew(game,6)
  bench.exp=Growth.expForLevel("MEDIUM_SLOW",7)-1
  local evolve=monNew(game,15)
  evolve.exp=Growth.expForLevel("MEDIUM_SLOW",16)-1
  local capped=monNew(game,99)
  capped.exp=Growth.expForLevel("MEDIUM_SLOW",100)-1
  local battle=BattleState.newWild(game,"FIXMON_C",10)
  battle.queue,battle.nextInsert={},0;battle.participants={[active]=true}
  battle:awardExp()
  T.eq(bench.level,6,"bench level waits for level-up queue")
  T.eq(evolve.level,15,"evolution member waits for queue")
  T.eq(capped.exp,Growth.expForLevel("MEDIUM_SLOW",100),"award clamps at level100 EXP")
  T.eq(battle.leveledUp[bench],true,"bench registered for evolution check")
  T.eq(battle.leveledUp[evolve],true,"evolution member registered")
  for _,row in ipairs(battle.queue)do if row.fn then row.fn()end end
  T.eq(bench.level,7,"bench gains level through actual commit queue")
  T.eq(bench.moves[#bench.moves].id,"FIX_EMBERISH","bench receives level-up move")
  T.eq(evolve.level,16,"bench reaches evolution level")
  T.eq(capped.level,100,"cap level commits")
  local pending=require("src.pokemon.Evolution").pendingFor(game,evolve,{kind="levelup"})
  T.eq(pending,"FIXMON_B","bench eligible for ordinary evolution flow")
  -- A full moveset must get a real replacement screen, not lose the move.
  game=gameNew();game.save.options.jpPartyExp=true
  active=monNew(game,50);bench=monNew(game,6)
  bench.exp=Growth.expForLevel("MEDIUM_SLOW",7)-1
  bench.moves={{id="FIX_TACKLE",pp=10},{id="FIX_SCRATCH",pp=10},{id="FIX_CUT",pp=10},{id="CUT",pp=10}}
  Data.moves.CUT={name="CUT",pp=30}
  battle=BattleState.newWild(game,"FIXMON_C",10)
  battle.queue,battle.nextInsert={},0;battle.participants={[active]=true}
  battle:awardExp()
  local learn
  for _,row in ipairs(battle.queue)do
    if row.fn then row.fn()end
    if row.ui then local ui=row.ui();if ui.newMoveId then learn=ui end end
  end
  T.check(learn and learn.mon==bench,"full bench moveset opens ordinary MoveLearnMenu")
  T.eq(learn and learn.newMoveId,"FIX_EMBERISH","bench choice receives correct move")
end

do
  local game=gameNew();game.save.options.jpPartyExp=true
  local active=monNew(game,50)
  local bench=monNew(game,5)
  local battle=BattleState.newWild(game,"FIXMON_C",100)
  battle.queue,battle.nextInsert={},0;battle.participants={[active]=true}
  battle:awardExp()
  local levels={}
  for _,row in ipairs(battle.queue)do
    if row.fn then
      local before=bench.level;row.fn()
      if before~=bench.level then levels[#levels+1]=bench.level end
    end
  end
  T.same(levels,{6,7,8,9,10},"multi-level bench award commits every level in order")
  T.eq(bench.moves[#bench.moves].id,"FIX_EMBERISH","multi-level bench award learns intermediate move")
  local Runtime=require("src.mods.Runtime")
  local hooks=require("src.mods.Hooks").new()
  Runtime.install(require("src.mods.Events").new(),hooks)
  local remove=hooks:wrap("exp.gain",function()return 101 end)
  local _,_,gain=expCase(true,true,false)
  T.same(gain,{101,101,50,50,0,0},"MOD gain hook runs before optional bench half")
  remove()
  remove=hooks:wrap("battle.exp_award",function(_,ctx)
    ctx.applyShare(ctx.alive[1],999,true)
  end)
  _,_,gain=expCase(true,true,false)
  T.same(gain,{1,0,0,0,0,0},"MOD award replacement remains authoritative")
  remove();Runtime.reset()
end

-- Actual forgetting input: classic refuses all five HM IDs, convenience
-- replaces them and resets PP/PP Ups as for any other newly learned move.
for _,move in ipairs({"CUT","FLY","SURF","STRENGTH","FLASH"})do
  Data.moves[move]={name=move,pp=30}
  for _,enabled in ipairs({false,true})do
    local game=gameNew();game.save.options.jpForgetHM=enabled
    local mon=monNew(game,5)
    mon.moves={{id=move,pp=1,ppUps=3},{id="FIX_TACKLE",pp=10},{id="FIX_SCRATCH",pp=10},{id="FIX_CUT",pp=10}}
    local menu=MoveLearnMenu.new(game,mon,"FIX_EMBERISH")
    game.stack:push(menu)
    local prompt=game.stack:pop();prompt.choice(true)
    game.input.wasPressed=function(_,key)return key=="a"end
    menu:update(0)
    T.eq(mon.moves[1].id,enabled and "FIX_EMBERISH" or move,"HM forget option "..move)
    T.eq(mon.moves[1].pp,enabled and Data.moves.FIX_EMBERISH.pp or 1,"PP correct "..move)
    local expectedPPUps
    if not enabled then expectedPPUps=3 end
    T.eq(mon.moves[1].ppUps,expectedPPUps,"PP Ups correct "..move)
    T.check(game.stack:top().pages~=nil,"HM feedback remains a real dialogue")
  end
end

-- Drive the real bag USE -> boot machine -> choose party -> teach path.
local function teachCase(enabled,full,accept,kind)
  local game=gameNew();game.save.options.jpReusableTM=enabled
  game.save.options.jpForgetHM=true
  local mon=monNew(game,5)
  if full then
    mon.moves={{id="CUT",pp=1},{id="FIX_TACKLE",pp=10},{id="FIX_SCRATCH",pp=10},{id="FIX_EMBERISH",pp=10}}
  end
  Data.items.FIX_TM.machine.kind=kind or "TM"
  game.save.inventory.FIX_TM=2
  local bag=BagMenu.new(game)
  game.stack:push(bag)
  local item
  for _,row in ipairs(bag.items)do if row.value=="FIX_TM"then item=row end end
  bag.onChoose(item)
  game.stack:pop().items[1].onSelect()
  game.stack:pop().choice(true)
  local picker=game.stack:top()
  picker.onSwitch(mon,picker)
  if full then
    local prompt=game.stack:pop();prompt.choice(true)
    local learn=game.stack:top()
    if accept then
      game.input.wasPressed=function(_,key)return key=="a"end
      learn:update(0)
    else
      learn:finish(false)
    end
    local result=game.stack:pop()
    if result.onDone then result.onDone()end
  end
  return game,mon
end
for _,enabled in ipairs({false,true})do
  for _,full in ipairs({false,true})do
    local game,mon=teachCase(enabled,full,true)
    T.eq(game.save.inventory.FIX_TM,enabled and 2 or 1,"TM amount: enabled="..tostring(enabled).." full="..tostring(full))
    local found=false;for _,m in ipairs(mon.moves)do if m.id=="FIX_CUT"then found=true end end
    T.check(found,"TM actually teaches through bag path")
  end
  local game=teachCase(enabled,true,false)
  T.eq(game.save.inventory.FIX_TM,2,"declined TM never consumed")
  game=teachCase(enabled,false,true,"HM")
  T.eq(game.save.inventory.FIX_TM,2,"HM remains reusable in either mode")
end
Data.items.FIX_TM.machine.kind="TM"
-- The flags live in shared Gen 1 launcher options. English and legacy
-- language-unspecified cartridges must retain original rules even when
-- those stored flags are true; their settings menus hide these controls.
for _,language in ipairs({"en",false}) do
  Data.constants.language=language or nil
  local _,_,gain=expCase(true,false,false)
  T.same(gain,{47,47,0,0,0,0},"non-JP flagged party EXP retains original participant split")
  _,_,gain=expCase(true,true,false)
  T.same(gain,{24,24,2,3,0,2},"non-JP flagged party EXP retains original EXP.ALL arithmetic")
  local game=gameNew();game.save.options.jpForgetHM=true
  local mon=monNew(game,5)
  mon.moves={{id="CUT",pp=1},{id="FIX_TACKLE",pp=10},{id="FIX_SCRATCH",pp=10},{id="FIX_CUT",pp=10}}
  local menu=MoveLearnMenu.new(game,mon,"FIX_EMBERISH")
  game.stack:push(menu);game.stack:pop().choice(true)
  game.input.wasPressed=function(_,key)return key=="a"end
  menu:update(0)
  T.eq(mon.moves[1].id,"CUT","non-JP flagged HM forgetting retains original refusal")
  T.check(game.stack:top().pages~=nil,"non-JP HM refusal remains a real dialogue")
  game,mon=teachCase(true,false,true,"TM")
  T.eq(game.save.inventory.FIX_TM,1,"non-JP flagged reusable TM still consumes machine")
  T.eq(mon.moves[#mon.moves].id,"FIX_CUT","non-JP TM still teaches normally")
end
Data.constants.language="ja"
T.eq(Rules.enabled({jpForgetHM=true},"jpForgetHM"),true,"plain options helper remains usable")
T.eq(Rules.enabled({options={jpForgetHM=true}},"jpForgetHM"),true,"plain save helper remains usable")
T.eq(Rules.enabled({save={options={jpForgetHM=true}}},"jpForgetHM"),false,"game context without language data fails closed")
T.finish("jp22 convenience rules: classic, party EXP, HM forgetting, reusable TMs")
