-- Actual seven-MOD escort regression: B begins during Oak lockstep.
-- Authored maps; optional private text is never included in this fixture.
package.path='./?.lua;./?/init.lua;'..package.path
return function(Game,Renderer,check,write)
local Pipelines=require('src.render.Pipelines')
local V=Game.mods.exports.DRAMALESS_SHAPE.lib
require('src.mods.Runtime').hooks:wrap('render.viewport',function(next,ctx)local r=next(ctx);r.capture=true;return r end,0,'starter-qa')
local terrainFrames=0
local oldOptions=Game.save.options
local baseDef=Game.data.maps.FIX_TOWN
Game.mods.modOptions.running_shoes=Game.mods.modOptions.running_shoes or {}
Game.mods.modOptions.running_shoes.speed=os.getenv('JP_QA_RUNNING_SPEED') or '2'
local Game=require('src.core.Game');local Data=require('src.core.Data')
local Input=require('src.core.Input');Input:init();Game.input=Input
local OW=require('src.world.OverworldController');local NPC=require('src.world.NPC');local Player=require('src.world.Player')
local Runner=require('src.script.ScriptRunner');local Stack=require('src.core.StateStack');local Version=require('src.core.GameVersion');Version.set('red_jp')
local Scripts=require('data.scripts.init');local Story=require('data.scripts.story2')
local Font=require('src.render.Font');local Strings=require('src.core.Strings')
setmetatable(Game.data,{__index=Data});Game.data.constants.language='ja'
Game.data.field.playerSprites={walk="SPRITE_FIX_PLAYER"}
Game.save=require('src.core.SaveData').newGame(Game.data);Game.save.options=oldOptions;Game.save.options.textSpeed=1
Game.save.options.pipelines={voxel=tonumber(os.getenv('JP_QA_INTRO_VOXEL')) or 2};Pipelines.applyOptions(Game.save.options)
Game.stack=setmetatable({states={}},{__index=Stack});Game.renderer=Renderer
Game.data.text={}
for _,key in ipairs({'_PalletTownOakHeyWaitDontGoOutText','_PalletTownOakItsUnsafeText','_OaksLabRivalFedUpWithWaitingText','_OaksLabOakChooseMonText','_OaksLabRivalWhatAboutMeText','_OaksLabOakBePatientText'})do Game.data.text[key]='テスト\nかいわ{DONE}' end
local primary=os.getenv('JP_QA_INTRO_PRIMARY_FILE')
if primary then for k,v in pairs(dofile(primary))do Game.data.text[k]=v end end
Font.load(Game.data);Strings.load(Game.data)
local function obj(index,name,x,y,text)
 return {index=index,name=name,x=x,y=y,text=text,sprite='SPRITE_FIX_NPC',movement='STAY',range='DOWN'}
end
local defs={PALLET_TOWN={label='PalletTown',tileset='OVERWORLD',objects={obj(1,'PALLETTOWN_OAK',8,5)}},OAKS_LAB={label='OaksLab',tileset='LAB',objects={obj(1,'OAKSLAB_RIVAL',4,3,'TEXT_OAKSLAB_RIVAL'),obj(5,'OAKSLAB_OAK1',5,2,'TEXT_OAKSLAB_OAK1'),obj(8,'OAKSLAB_OAK2',5,10,'TEXT_OAKSLAB_OAK2')}}}
for id,def in pairs(defs)do for k,v in pairs(baseDef)do if def[k]==nil then def[k]=v end end;def.id=id;def.tileset='FIX_OUT';def.outdoor=id=='PALLET_TOWN' end
Game.data.maps=defs
local ow=setmetatable({scriptMoves={},ghosts={},npcs={},entities={},camera={x=0,y=0,follow=function()end}},{__index=OW});Game.overworld=ow
for _,fn in pairs(OW)do if type(fn)=='function'then for i=1,30 do local n=debug.getupvalue(fn,i);if not n then break end;if n=='Game'then debug.setupvalue(fn,i,Game)elseif n=='mapScripts'then debug.setupvalue(fn,i,Scripts)end end end end
function ow:setMap(id,x,y,facing)
 self.map={id=id,def=defs[id],widthCells=20,heightCells=20,
  inBounds=function(_,x,y)return x>=0 and y>=0 and x<20 and y<20 end,
  isWalkableCell=function()return true end, tileAt=function()return 0 end,
  isDoorTileCell=function()return false end,isWaterCell=function()return false end,
  warpAtCell=function()return nil end,isGrassCell=function()return false end,cellTile=function()return 0 end,
  warpPadOrHoleAt=function()return nil end}
 local physical=require('src.world.Map').new(defs[id],Game.data.tilesets.FIX_OUT)
 for k,v in pairs(self.map)do if type(v)=='function' then physical[k]=v end end
 self.map=physical;self.neighbors={}
 self.player=Player.new(Game.data,x,y,facing);self.npcs={};self.entities={self.player};self.npcPool={}
 for _,d in ipairs(self.map.def.objects)do if d.name~='OAKSLAB_OAK1'then local n=NPC.new(Game.data,id,d);table.insert(self.npcs,n);table.insert(self.entities,n);self.npcPool[n.id]=n end end
end
-- The fixture has no encounter/warp tiles or map connections. Keep all
-- simulation, script movement, camera follow and ordinary input gates real.
function ow:checkEdgeExit()return false end
function ow:checkLedgeHop()return false end
function ow:checkBoulderPush()return false end
function ow:stopSurfingOntoLand()end
function ow:onStepComplete()end
function ow:paletteNameFor()return 'PALLET' end
function ow:draw()
 Renderer:beginWorldPass();local vw,vh=Renderer:worldViewSize()
 local surface=Pipelines.drawWorld('voxel',{state=self,vw=vw,vh=vh,width=320,height=480,scale=1,
 paletteFor=function()return require('src.render.PaletteFX').pal(Game.data,'PALLET')end,
 drawFx=function()end})
 Renderer:endWorldPass();if surface then Renderer:setWorldOverride(surface);terrainFrames=terrainFrames+1 end
end
love.window.setMode(320,480,{vsync=0})
local rendered=0
local function advance()
 Game:step(1/60);Pipelines.update(1/60)
 if rendered%4==0 then Game:draw();love.graphics.setCanvas() end
 rendered=rendered+1
end

ow.runner=Runner.new(Game,ow);ow:setMap('PALLET_TOWN',10,1,'up');ow.enter=false;Game.stack:push(ow)
assert(Story.PALLET_TOWN.onStep(Game,ow,10,1))
local prev
local bStarted=false
local steps={}
local sawSpeedMismatch=false
for frame=1,4000 do
 local paired=false
 for _,mv in ipairs(ow.scriptMoves)do if mv.entity==ow.player then paired=true end end
 if not bStarted and paired and ow.map.id=='PALLET_TOWN' then
   bStarted=true;Input:sourcePress('b','escort-run');Input:sourcePress('down','escort-direction')
   print('B START',frame,ow.player.cellX,ow.player.cellY)
 end
 if bStarted and not Game.save.flags.EVENT_OAK_ASKED_TO_CHOOSE_MON then
   local p=ow.player
   for _,mv in ipairs(ow.scriptMoves)do
     if mv.entity~=p and mv.entity.def and mv.entity.def.name=='PALLETTOWN_OAK' and p.moving and mv.entity.moving then
       local a,b=p.stepFramesCur,mv.entity.stepFrames or 16
       if a~=b then sawSpeedMismatch=true end
       if not steps[tostring(a)..':'..tostring(b)]then print('ESCORT FRAMES player/Oak',a,b);steps[tostring(a)..':'..tostring(b)]=true end
     end
   end
 end
 local top=Game.stack:top()
 if top~=prev then print(frame,top==ow and 'world' or top.pages and 'TextBox' or 'other',ow.map.id,ow.player.cellX,ow.player.cellY,#ow.scriptMoves,ow.emote and ow.emote.frames);prev=top end
 if frame%8==0 then Input:sourcePress('a','test')elseif frame%8==1 then Input:sourceRelease('a','test')end
 advance()
 if Game.save.flags.EVENT_OAK_ASKED_TO_CHOOSE_MON then
   print('INTRO DONE',frame,ow.player.cellX,ow.player.cellY,ow.transitioning,ow.player.inputLocked,#ow.scriptMoves,ow.emote,ow.engaging,ow.runner:isRunning())
   Input:sourceRelease('a','test');Input:sourceRelease('b','escort-run');Input:sourceRelease('down','escort-direction')
   print('SPEED MISMATCH',sawSpeedMismatch)
   check(bStarted,'B plus direction held during the real escort')
   check(not sawSpeedMismatch,'Oak and player remain at the same event speed')
   for _,mv in ipairs(ow.scriptMoves)do print('LEFTOVER',mv.entity.def and mv.entity.def.name,mv.entity.moving,mv.remaining,mv.entity.cellX,mv.entity.cellY)end
   Input:sourcePress('down','test')
   for _=1,40 do advance()end
   print('AFTER DOWN',ow.player.cellX,ow.player.cellY,ow.player.moving,ow.player.inputLocked)
   check(not ow.transitioning and not ow.player.inputLocked and #ow.scriptMoves==0 and not ow.emote and not ow.engaging and not ow.runner:isRunning(),'real seven-MOD intro clears all interaction locks')
   if ow.player.cellX==5 and ow.player.cellY==3 then
     Input:sourceRelease('down','test');Input:sourcePress('right','test')
     for _=1,40 do advance()end
   end
   if ow.player.cellX==5 and ow.player.cellY==3 then
     Input:sourceRelease('right','test');Input:sourcePress('up','test')
     for _=1,40 do advance()end
   end
   check(ow.player.cellX~=5 or ow.player.cellY~=3,'direction input moves after choose-mon speech before ball interaction')
   check(terrainFrames>100,'more than 100 live 3D pipeline frames during real intro')
   check(#Game.mods.errors==0,'no MOD errors during escort/3D frames')
   Game:draw();love.graphics.setCanvas()
   write('after-intro.png',require('src.render.GameViewport').target():newImageData():encode('png'):getString())
   return
 end
end
print('STUCK STATE',ow.map.id,ow.player.cellX,ow.player.cellY,#ow.scriptMoves,ow.player.inputLocked,ow.transitioning);for _,mv in ipairs(ow.scriptMoves)do print('LEFTOVER',mv.entity.def and mv.entity.def.name,mv.entity.moving,mv.remaining,mv.entity.cellX,mv.entity.cellY)end;error('STUCK')

end
