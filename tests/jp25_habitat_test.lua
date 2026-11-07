package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Japanese habitat catalogue')
local H=require('src.world.JapaneseHabitats')
local fixture=require('tests.jp25_habitat_fixture')
local Json=require('src.link.Json')
local game=fixture()
local before=Json.encode(game.data)
local rows,counts=H.entries(game,{'ROUTE_1'})
T.eq(#rows,2,'native duplicate slots produce one species each')
T.eq(rows[1].name,'ポッポ','seen name appears in Japanese')
T.eq(rows[1].minLevel,2,'level minimum across duplicate slots')
T.eq(rows[1].maxLevel,5,'level maximum across duplicate slots')
T.eq(counts.seen,2,'owned species are also seen')
T.eq(counts.owned,1,'owned count uses saved dex')
T.eq(rows[2].owned,true,'captured row marked separately')
T.eq(H.hasWater(game.data,'ROUTE_1'),false,'dry route cannot fish despite overworld tileset')
T.eq(H.hasWater(game.data,'ROUTE_2'),true,'actual water collision block enables rods')
rows,counts=H.entries(game,{'ROUTE_2'})
T.eq(#rows,4,'land surf and rods union removes duplicate species')
T.eq(rows[1].name,'？？？','unseen name is concealed')
T.eq(rows[1].minLevel,nil,'unseen level concealed')
T.eq(rows[1].maxLevel,nil,'unseen level range concealed')
local found={};for _,r in ipairs(rows)do found[r.species]=r end
T.check(found.POLIWAG.methods.water and found.POLIWAG.methods.fish,'same species retains both encounter methods')
T.eq(found.POLIWAG.minLevel,10,'Good Rod level participates')
T.eq(found.POLIWAG.maxLevel,25,'Super Rod per-map data participates')
T.eq(#H.entries(game,{'ROUTE_2'},'fish'),3,'fishing filter matches three genuine rod species')
T.eq(#H.entries(game,{'ROUTE_2'},'water'),1,'surf filter uses water table')
T.eq(#H.entries(game,{'ROUTE_2'},'land'),1,'land filter excludes fishing')
T.eq(#H.entries(game,{'ROUTE_1'},'water'),0,'zero rate table excluded')
T.eq(H.hasWater(game.data,'MISSING'),false,'unknown map cannot invent fishing')
T.eq(Json.encode(game.data),before,'catalogue does not mutate runtime encounter data')
game.data.encounters.ROUTE_1.grass.buckets={128,128,256}
T.eq(#H.entries(game,{'ROUTE_1'}),1,'zero probability encounter slots excluded')
game.data.encounters.ROUTE_1.grass.buckets=nil
T.eq(H.observe(game),true,'records actual entered route')
T.eq(H.observe(game),false,'repeat frames are constant-time no-op')
T.eq(game.save.jpHabitatVisited.ROUTE_1,true,'visit is persistent separate map set')
game.overworld.neighbors={{map={id='ROUTE_2'}}}
H.observe(game);T.eq(game.save.jpHabitatVisited.ROUTE_2,nil,'streamed neighbor is not visited')
local areas,at=H.areas(game)
T.eq(areas[at].name,'1ばんどうろ','current route opens by default')
T.eq(#areas,2,'only current route and genuine previous town included')
game.save.jpHabitatVisited.MT_MOON_1F=true;game.save.jpHabitatVisited.MT_MOON_B1F=true
game.overworld.map={id='MT_MOON_B1F',def=game.data.maps.MT_MOON_B1F}
areas,at=H.areas(game)
T.eq(areas[at].name,'おつきみやま','dungeon floors share localized region')
T.eq(#areas[at].maps,2,'only actually visited floors combined')
rows=H.entries(game,areas[at].maps)
T.eq(#rows,2,'unvisited deeper floor not scanned')
T.eq(rows[1].name,'？？？','unknown cave species stays secret')
game.overworld.map={id='ROUTE_2'};game.overworld.transitioning=true
T.eq(H.observe(game),false,'in-flight map transitions not recorded')
game.overworld.transitioning=nil;game.stack.states={game.overworld,{isTitleScreen=true}}
T.eq(H.observe(game),false,'stale overworld behind title not recorded')
game.stack.states={game.overworld,{isOpeningMovie=true}}
T.eq(H.observe(game),false,'stale overworld behind opening not recorded')
game.stack.states={game.overworld,{}}
T.eq(H.observe(game),true,'current area still recorded when ordinary menu covers it')
game.overworld.map={id='UNREGISTERED'};T.eq(H.observe(game),false,'unknown map IDs rejected')
game.data.constants.language='en';T.eq(H.observe(game),false,'English game excluded')
game.data.constants.language='ja';game.data.constants.generation=2;T.eq(H.enabled(game),false,'Gen2 excluded')
T.eq(H.enabled({}),nil,'uninitialized game safely ignored')
-- Rod content patches take effect at read time without a catalogue cache.
game=fixture();game.data.field.fishing={OLD_ROD={always={species='PIKACHU',level=17}},
  SUPER_ROD={perMap='modFish'}};game.data.field.modFish={ROUTE_2={{species='SNORLAX',level=40}}}
rows=H.entries(game,{'ROUTE_2'},'fish')
T.eq(#rows,2,'MOD rod definitions replace defaults faithfully')
game.save.pokedex.seen.SNORLAX=true
rows=H.entries(game,{'ROUTE_2'},'fish')
T.eq(rows[2].name,'カビゴン','new dex state updates on reopening')
-- Replay the bundled All151 registration through its actual authored patch
-- function; its grass slots must be reflected rather than vanilla tables.
game=fixture();local patches={}
local content=setmetatable({}, {__index=function(_,name)return {patch=function(_,id,value)
  if name=='encounters'then patches[id]=value end
end}end})
assert(loadfile('vendor/jp-mods/all_pokemon_catchable_151_mod/main.lua'))()({content=content,log={info=function()end}})
for id,patch in pairs(patches)do
  game.data.encounters[id]=patch
  if patch.grass and patch.grass.rate==nil then patch.grass.rate=25 end
  for _,slot in ipairs(patch.grass and patch.grass.slots or {})do
    game.data.pokemon[slot.species]=game.data.pokemon[slot.species] or {id=slot.species,name='？？？',dex=999}
  end
end
rows=H.entries(game,{'VIRIDIAN_FOREST'})
found={};for _,r in ipairs(rows)do found[r.species]=true end
T.check(found.CATERPIE and found.WEEDLE and found.PIKACHU,'bundled All151 version-independent wild species visible to catalogue')
rows=H.entries(game,{'CERULEAN_CAVE_2F'})
found={};for _,r in ipairs(rows)do found[r.species]=true end
T.eq(found.MACHAMP,true,'bundled All151 added evolved species included')
-- SHIP_PORT tile 0x32 is a boarding platform, never fishable shoreline.
game=fixture();game.data.maps.ROUTE_2.tileset='SHIP_PORT'
local platform={};for i=1,16 do platform[i]=0x32 end
game.data.tilesets.SHIP_PORT={blocks={platform}};game.data.field.waterTilesets={'SHIP_PORT'}
T.eq(H.hasWater(game.data,'ROUTE_2'),false,'dock boarding platform is not water')
T.finish()
