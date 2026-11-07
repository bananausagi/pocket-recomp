-- Run against the packaged .love; this helper is external to the archive.
local U = dofile(assert(os.getenv('JP_TEST_ROOT')) .. '/tests/drivers/util.lua')
return function(game)
  local DIR = assert(os.getenv('SHOT_DIR'))
  local function shot(name) assert(U.shot(game, DIR .. '/' .. name .. '.png')) end
  local function check(ok, name) assert(ok, name); print('JP PASS: ' .. name) end
  local Naming = require('src.ui.NamingScreen')
  local Title = require('src.ui.TitleState')
  local SaveData = require('src.core.SaveData')
  check(game.data.constants.language == 'ja', 'Japanese cache loaded')
  check(game.data.pokemon.PIKACHU.name == 'ピカチュウ', 'Pokemon name decoding')
  check(game.data.pokemon.BULBASAUR.dexEntry.heightM == 0.7, 'metric height')
  check(game.data.field.presetNames.player[1] == 'レッド', 'preset names from ROM')
  local count = 0
  for label, text in pairs(game.data.text) do
    assert(not text:find('{BYTE:',1,true), 'unmapped bytes: ' .. label)
    count = count + 1
  end
  print('JP text count: ' .. count)
  local didTitle = false
  for i=1,4000 do
    local top = game.stack:top()
    if getmetatable(top) == Title and top.phase == 'loop' and not didTitle then
      U.wait(30); shot('01-title'); didTitle = true
    end
    if getmetatable(top) == Naming then U.tap(game,'start') else U.tap(game,'a') end
    U.wait(5)
    if game.stack:top() == game.overworld then break end
  end
  check(game.stack:top() == game.overworld, 'intro and new game completed')
  check(game.save.player.name == 'レッド', 'Japanese player name')
  shot('02-bedroom')
  U.tap(game,'start'); U.wait(10); shot('03-menu'); U.tap(game,'b'); U.wait(5)
  local entered
  local naming=Naming.new(game,{onDone=function(name) entered=name end})
  game.stack:push(naming)
  naming.row,naming.col=1,6; U.tap(game,'a') -- は
  naming.row,naming.col=6,5; U.tap(game,'a') -- ば
  check(table.concat(naming.glyphs)=='ば','dakuten input')
  naming.row,naming.col=6,6; U.tap(game,'a') -- ぱ
  check(table.concat(naming.glyphs)=='ぱ','handakuten input')
  U.tap(game,'select')
  naming.row,naming.col=1,2; U.tap(game,'a') -- カ
  naming.row,naming.col=6,5; U.tap(game,'a') -- ガ
  check(table.concat(naming.glyphs)=='ぱガ','katakana input')
  shot('04-naming'); U.tap(game,'start')
  check(entered=='ぱガ','UTF-8 name confirmation')
  U.teleport(game,'PALLET_TOWN',10,5,'right')
  local ow=game.overworld
  local x,y=ow.player.cellX,ow.player.cellY
  local direction
  for _, d in ipairs({{1,0,'right'},{-1,0,'left'},{0,1,'down'},{0,-1,'up'}}) do
    if ow.map:isWalkableCell(x+d[1],y+d[2]) then direction=d[3]; break end
  end
  print('movement direction',direction,'runner',ow.runner and ow.runner:isRunning())
  assert(direction, 'no walkable neighbor at test position')
  U.hold(game,direction,25); U.wait(20)
  shot('05-pallet')
  check(ow.player.cellX ~= x or ow.player.cellY ~= y,'overworld movement')
  shot('05-pallet')
  local Pokemon=require('src.pokemon.Pokemon')
  local Battle=require('src.battle.BattleState')
  game.save.party={Pokemon.new(game.data,'CHARMANDER',12)}
  local battle=Battle.newWild(game,'PIDGEY',2)
  battle.onFinish=function() end
  game.overworld:pushBattle(battle)
  for i=1,500 do
    if battle.phase=='menu' then break end
    U.tap(game,'a'); U.wait(6)
  end
  check(battle.phase=='menu','wild battle reached command menu')
  shot('06-battle')
  local hp=battle.enemy.mon.hp
  U.tap(game,'a'); U.wait(12); shot('07-moves'); U.tap(game,'a')
  for i=1,500 do
    U.tap(game,'a'); U.wait(6)
    if battle.enemy.mon.hp < hp then break end
  end
  check(battle.enemy.mon.hp < hp,'battle attack dealt damage')
  for i=1,500 do
    if game.stack:top()==game.overworld then break end
    U.tap(game,'a'); U.wait(6)
  end
  check(game.stack:top()==game.overworld,'battle finished')
  local Dex=require('src.ui.DexEntryMenu')
  local dex=Dex.new(game,{species='BULBASAUR',forceOwned=true})
  game.stack:push(dex)
  for i=1,12000 do
    U.wait(1)
    if dex.picDelay==0 and not dex:crying() then break end
  end
  check(dex.picDelay==0 and not dex:crying(),'Pokedex cry completed')
  check(dex.pageCount>=1,'Pokedex description decoded')
  shot('08-pokedex'); U.tap(game,'b'); U.wait(5)
  game.save.player.name='ぱガ'
  check(SaveData.save(game.save) ~= false,'in-game save written')
  local loaded=SaveData.load('red_jp')
  check(loaded and loaded.player.name=='ぱガ','Japanese save round trip')
  check(loaded.version=='red_jp','save version isolation')
  print('JAPANESE RED SMOKE PASSED')
  love.event.quit(0)
end
