local U = require('tests.drivers.util')
return function(game)
 local out=assert(os.getenv('POKEPORT_SHOT_DIR'))
 local female=os.getenv('CRYSTAL_FEMALE')=='1'
 assert(require('src.core.GameVersion').get()=='crystal_jp')
 assert(game.data.pokemon.BULBASAUR.name=='フシギダネ')
 assert(game.data.pokemon.CELEBI.name=='セレビィ')
 game:showTitle();U.wait(80);assert(U.shot(game,out..'/title.png'))
 game:newGame();U.wait(100)
 local NamePick=require('src.ui.gen2.NamePick')
 local Gender=require('src.ui.gen2.GenderSelect')
 local genderSeen=false
 local nameSeen=false
 for i=1,1800 do
  local top=game.stack:top()
  if getmetatable(top)==Gender then
   if not genderSeen then assert(U.shot(game,out..'/gender.png'));genderSeen=true end
   if female and top.cursor~=2 then U.tap(game,'down');U.wait(15) end
   U.tap(game,'a')
  elseif getmetatable(top)==NamePick then
   nameSeen=true
   if top.slide then U.wait(30)
   else
    assert(U.shot(game,out..'/names.png'))
    if top.cursor~=2 then U.tap(game,'down');U.wait(10) end
    U.tap(game,'a')
   end
  else U.tap(game,'a') end
  U.wait(4)
  if i==180 then assert(U.shot(game,out..'/oak.png')) end
  if nameSeen and game.stack:top()==game.overworld then break end
 end
 assert(genderSeen,'native gender choice not reached')
 assert(nameSeen and game.stack:top()==game.overworld,'normal intro did not finish')
 assert(game.world and game.world.map,'normal intro did not reach world')
 assert(game.save.player.name=='クリス',game.save.player.name)
 assert(game.save.player.gender==(female and 'female' or 'male'))
 U.wait(80);assert(U.shot(game,out..'/bedroom.png'))
 assert(game.world.player.spriteDef.id==(female and 'SPRITE_KRIS' or 'SPRITE_CHRIS'))
 assert(game:writeSave())
 local save=assert(require('src.core.gen2.Save').load('crystal_jp'))
 assert(save.player.gender==game.save.player.gender and save.player.name=='クリス')
 game:continueGame(save);U.wait(60);assert(U.shot(game,out..'/continued.png'))
 print('CRYSTAL_JP_FLOW_PASS',save.player.gender,save.player.name)
 game.save.pokedex.seen.BULBASAUR=true;game.save.pokedex.caught.BULBASAUR=true
 local dex=require('src.ui.gen2.PokedexMenu').new(game,{entrySpecies='BULBASAUR'})
 game.stack:push(dex);U.wait(10)
 assert(dex.dex.entries.BULBASAUR.heightM==0.7 and dex.dex.entries.BULBASAUR.weightKg==6.9)
 assert(U.shot(game,out..'/dex.png'));game.stack:pop()
 local Mon=require('src.battle.gen2.Mon')
 game.save.party={Mon.new(game.data,'CYNDAQUIL',10)}
 assert(game.world:startBattle({wild=Mon.new(game.data,'PIDGEY',3)}))
 local screen
 for i=1,600 do
  screen=game.stack:top()
  if screen and screen.battle and screen.message then break end
  U.wait(1)
 end
 assert(screen and screen.battle,'seeded battle not reached')
 U.wait(80);assert(U.shot(game,out..'/battle.png'))
 print('CRYSTAL_JP_DEX_BATTLE_PASS',screen.message)
 love.event.quit(0)
end
