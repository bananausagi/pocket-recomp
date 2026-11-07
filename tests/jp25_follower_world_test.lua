-- Real OverworldController enter/update/map/script/exit integration, using
-- authored fixture maps and a minimal sprite adapter (GL tested separately).
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('JP25 follower live world hooks')
local data=require('tests.fixture_data').load()
require('src.core.GameVersion').set('red_jp')
require('src.core.Data').seedDefaults(data,'red_jp')
data.constants.language='ja';data.field.playerSprites={walk='SPRITE_FIX_PLAYER'}
for _,ts in pairs(data.tilesets)do ts.tilesPerRow=16;ts.walkable={0,1,2}end
data.field.flyWarps={};data.field.waterTilesets={};data.field.forcedMovement={tiles={}}
data.encounters={}
local Game=require('src.core.Game');Game.data=data
Game.save=require('src.core.SaveData').newGame(data);Game.save.player.surfing=false
Game.save.flags.EVENT_GOT_STARTER=true;Game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB=true
Game.save.party={{species='FIXMON_A',hp=20}}
local held='right'
Game.input={isDown=function(_,key)return key==held or key=='b' end,
  wasPressed=function()return false end,isTouchDown=function()return false end}
Game.renderer={worldViewSize=function()return 160,144 end}
Game.stack=require('src.core.StateStack');Game.stack:init()
local released=0
package.loaded['src.render.JapaneseFollowerSprite']={new=function()
  return {draw=function()end,release=function()released=released+1 end}
end}
local OW=require('src.world.OverworldController')
Game.stack:push(OW,'FIX_TOWN',2,3,'right')
T.eq(OW.jpFollowerState,nil,'world entry has no stale companion')
for _=1,70 do OW:update(1/60)end
T.eq(OW.player.px,102,'actual world input advances player normally')
T.eq(OW.jpFollowerState.actor.px,84,'actual world update hook consumes current player pose')
T.eq(#OW.entities,3,'actual world has player, fixture NPC and one companion')
T.eq(#OW.npcs,1,'companion is absent from actual NPC registry')
local before=OW.player.px
held=nil
while OW.player.moving do OW:update(1/60)end
local landing=OW.player.cellX
local completed=false
OW:scriptMove(OW.player,'down',1,function()completed=true end)
OW:update(1/60)
T.eq(OW.jpFollowerState,nil,'script gate removes companion in actual update loop')
T.eq(OW.player.stepFramesCur,16,'held B does not accelerate scripted movement')
for _=1,20 do OW:update(1/60)end
T.eq(completed,true,'actual scripted movement completes')
T.eq(#OW.scriptMoves,0,'script queue drains normally')
T.eq(OW.player.inputLocked,false,'script completion leaves player input unlocked')
T.eq(OW.player.cellX,landing,'companion does not alter scripted destination')
held='right'
for _=1,32 do OW:update(1/60)end
T.check(OW.jpFollowerState and OW.jpFollowerState.attached,'follower resumes after completed script')
OW:setMap('FIX_TOWN',2,2,'up',{keepMusic=true})
T.eq(OW.jpFollowerState,nil,'real setMap hook resets a nonseamless trail')
held='up'
for _=1,55 do OW:update(1/60)end
T.eq(OW.map.id,'FIX_ROUTE','actual input crosses the fixture map connection')
T.check(OW.jpFollowerState and OW.jpFollowerState.attached,'actual connection keeps an active companion')
T.check(math.abs(OW.jpFollowerState.actor.py-OW.player.py-18)<.001,'actual rebase preserves seam trail separation')
T.eq(#OW.npcs,1,'new map keeps only its ordinary NPC')
local n=released
Game.stack:clear()
T.eq(OW.jpFollowerState,nil,'real world exit clears companion state')
T.eq(released,n+1,'world exit releases exactly its one companion renderer')
T.finish()
