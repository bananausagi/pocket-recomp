-- Real bag/input/use/save paths for the Japanese SELECT field shortcut.
package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local T = require('tests.harness').suite('Japanese registered field items')
package.loaded['src.core.Sound'] = { play=function()end }
package.loaded['src.core.Music'] = { playMap=function()end }
package.loaded['src.render.TextBox'] = {
  new=function(_, text, done) return { text=text, done=done } end,
  soundOpts=function()end,
}
local Version=require('src.core.GameVersion')
local Strings=require('src.core.Strings')
local Save=require('src.core.SaveData')
local Game=require('src.core.Game')
local OW=require('src.world.OverworldController')
-- enter normally binds the shared Game upvalue while loading the ROM map.
for i=1,20 do
  local name=debug.getupvalue(OW.handleRegisteredItem,i)
  if not name then break end
  if name=='Game' then debug.setupvalue(OW.handleRegisteredItem,i,Game);break end
end
local Input=require('src.core.Input')
local Bag=require('src.inventory.Bag')
local BagMenu=require('src.ui.BagMenu')
local Registered=require('src.inventory.RegisteredItem')
local Data=require('tests.modkit.fixtures').fresh()
Data.constants.language='ja'
for i,id in ipairs({'BICYCLE','OLD_ROD','GOOD_ROD','SUPER_ROD','ITEMFINDER','POKE_FLUTE','TOWN_MAP'})do
  Data.items[id]={id=id,index=i,name=id,keyItem=true}
end
Strings.load(Data)
Version.set('red_jp')
Game.data=Data
Game.save={version='red_jp',player={name='レッド'},party={},inventory={},flags={},options=Save.defaultOptions()}
Game.stack={states={},push=function(s,v)s.states[#s.states+1]=v end,
  pop=function(s)return table.remove(s.states)end,top=function(s)return s.states[#s.states]end}
Game.input=Input
Game.overworld=setmetatable({map={id='FIX_TOWN',def={tileset='OVERWORLD'}},
  player={surfing=false}}, {__index=OW})
for _,id in ipairs({'BICYCLE','OLD_ROD','ITEMFINDER','POKE_FLUTE','TOWN_MAP'})do Bag.add(Game.save,id,1)end
Bag.add(Game.save,'FIX_POTION',2)
local function row(list,id)
  for i,item in ipairs(list.items)do if item.value==id then return i end end
end
local function open(id,options)
  Input:init();Game.stack.states={Game.overworld}
  local list=BagMenu.new(Game,options)
  Game.stack:push(list);list.index=assert(row(list,id));return list
end
local function selectKey(source)
  Input:reset()
  if source=='keyboard' then Input:keypressed('tab')
  elseif source=='pad' then Input:gamepadpressed(nil,'back')
  else Input:overlayPressed('select') end
  Input:step()
end
for _,source in ipairs({'keyboard','pad','touch'})do
  Game.save.registeredItem=nil
  local list=open('BICYCLE')
  T.eq(list.items[row(list,'BICYCLE')].right,'セレクトで とうろく','unregistered field tool explains SELECT')
  selectKey(source);list:update(1/60)
  T.eq(Game.save.registeredItem,'BICYCLE',source..' SELECT registers bicycle')
  T.eq(list.swapIndex,nil,source..' registration does not start reorder')
  T.check(Game.stack:top().text:find('とうろくした',1,true)~=nil,'Japanese registration confirmation')
  T.eq(list.items[row(list,'BICYCLE')].right,'とうろく','registered tool has visible marker')
  Game.stack:pop();selectKey(source);list:update(1/60)
  T.eq(Game.save.registeredItem,nil,source..' second SELECT unregisters')
  T.check(Game.stack:top().text:find('はずした',1,true)~=nil,'Japanese unregister confirmation')
end
local list=open('BICYCLE');selectKey('touch');list:update(1/60)
T.check(Save.save(Game.save),'favorite saves through ordinary game save')
local loaded=assert(Save.load('red_jp'))
T.eq(loaded.registeredItem,'BICYCLE','favorite survives actual save/load roundtrip')
Game.save.registeredItem=loaded.registeredItem
Game.stack.states={Game.overworld};selectKey('pad')
T.check(Game.overworld:handleRegisteredItem(),'overworld accepts SELECT')
T.eq(Game.save.onBike,true,'registered bicycle mounts through standard item use')
T.eq(Game.stack.states[1],Game.overworld,'shortcut never pops the overworld')
Game.stack.states={Game.overworld};selectKey('touch');Game.overworld:handleRegisteredItem()
T.eq(Game.save.onBike,false,'registered bicycle dismounts')
Game.overworld.player.surfing=true;selectKey('keyboard');Game.overworld:handleRegisteredItem()
T.eq(Game.save.onBike,false,'shortcut respects surfing prohibition')
Game.overworld.player.surfing=false;Game.save.onBike=true;Game.save.forcedBike=true
selectKey('touch');Game.overworld:handleRegisteredItem()
T.eq(Game.save.onBike,true,'shortcut cannot dismount on forced cycling road')
Game.save.forcedBike=nil;Game.save.onBike=false
Game.overworld.map.def.tileset='HOUSE'
selectKey('touch');Game.overworld:handleRegisteredItem()
T.eq(Game.save.onBike,false,'shortcut cannot mount indoors')
Game.overworld.map.def.tileset='OVERWORLD'
Game.overworld.player.moving=true;selectKey('keyboard')
T.eq(Game.overworld:handleRegisteredItem(),false,'mid-step SELECT waits for landing')
Input:step();Game.overworld.player.moving=false
T.check(Game.overworld:handleRegisteredItem(),'held SELECT acts after landing')
T.eq(Game.save.onBike,true,'landing shortcut mounts once')
T.eq(Game.overworld:handleRegisteredItem(),false,'held shortcut does not repeat')
Game.overworld.player.moving=true;selectKey('keyboard');Game.overworld:handleRegisteredItem()
Input:keyreleased('tab');Input:step();Game.overworld.player.moving=false
T.eq(Game.overworld:handleRegisteredItem(),false,'released mid-step SELECT does not activate later')
selectKey('touch');Input:keypressed('escape');Input:step()
T.eq(Game.overworld:handleRegisteredItem(),false,'START retains priority')
selectKey('touch');Game.overworld.player.inputLocked=true
T.eq(Game.overworld:handleRegisteredItem(),false,'locked player cannot activate field tools')
Game.overworld.player.inputLocked=false
Bag.remove(Game.save,'BICYCLE',1)
T.eq(Registered.get(Game),nil,'removed/deposited favorite is cleared')
selectKey('touch');Game.overworld:handleRegisteredItem()
T.check(Game.stack:top().text:find('セレクト',1,true)~=nil,'empty shortcut explains Japanese registration')
list=open('FIX_POTION');selectKey('touch');list:update(1/60)
T.eq(list.swapIndex,list.index,'ordinary item SELECT still reorders')
Bag.add(Game.save,'BICYCLE',1)
list=open('BICYCLE',{battle={}})
T.eq(list.items[row(list,'BICYCLE')].right,nil,'battle bag never advertises field registration')
selectKey('touch');list:update(1/60)
T.eq(list.swapIndex,list.index,'battle bag SELECT still reorders')
T.eq(Game.save.registeredItem,nil,'battle cannot change field registration')
Version.set('red');list=open('BICYCLE');selectKey('touch');list:update(1/60)
T.eq(list.swapIndex,list.index,'other versions keep original bicycle reorder')
T.eq(Game.overworld:handleRegisteredItem(),false,'other versions have no new field shortcut')
-- A renderer may replace handleInput completely. The real update loop must
-- dispatch SELECT first, while retaining the script/menu/transition gates.
Version.set('red_jp');Game.save.registeredItem='BICYCLE';Game.save.onBike=false
local ow=Game.overworld
local cameraCalls,running=0,false
ow.runner={update=function()end,isRunning=function()return running end}
ow.npcs,ow.ghosts,ow.scriptMoves,ow.entities={},{},{},{}
ow.player.px,ow.player.py=0,0
ow.player.update=function()return false end
ow.camera={follow=function()end}
for _,name in ipairs({'drainPendingScripts','updateParallel','tickPoisonFlash',
  'updateScriptMoves','checkTrainerSight','applyPendingSpawnResets'})do ow[name]=function()end end
ow.onSlopeMap=function()return false end
ow.handleInput=function()cameraCalls=cameraCalls+1 end
Game.renderer={worldViewSize=function()return 160,144 end}
package.loaded['src.world.PikachuFollower']={update=function()end}
Game.stack.states={ow};selectKey('touch');ow:update(1/60)
T.eq(Game.save.onBike,true,'real update dispatches shortcut before free-camera replacement')
T.eq(cameraCalls,0,'shortcut activation does not also move the free camera')
for _,gate in ipairs({'script','transition','menu'})do
  Game.stack.states=gate=='menu' and {ow,{}} or {ow}
  running=gate=='script';ow.transitioning=gate=='transition'
  selectKey('touch');ow:update(1/60)
  T.eq(Game.save.onBike,true,gate..' prevents registered item use')
  T.eq(cameraCalls,0,gate..' also retains camera input gate')
end
T.finish()
