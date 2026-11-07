-- ROM-free integration: actual fixed-step input, state stack, world update,
-- transition, emote callbacks, player/NPC movement and lab step scripts.
-- The room below is authored collision geometry (not a ROM map/tileset).
-- In particular this never pops dialogue or invokes onDone manually.
package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local T = require('tests.harness').suite('Japanese lab intro progression')
local Game = require('src.core.Game')
local Data = require('src.core.Data')
local Input = require('src.core.Input')
local OW = require('src.world.OverworldController')
local NPC = require('src.world.NPC')
local Player = require('src.world.Player')
local Map = require('src.world.Map')
local Collision = require('src.world.Collision')
local Runner = require('src.script.ScriptRunner')
local Stack = require('src.core.StateStack')
local Scripts = require('data.scripts.init')
local Story = require('data.scripts.story2')
local Font = require('src.render.Font')
local Strings = require('src.core.Strings')
local Version = require('src.core.GameVersion')
local Json = require('src.link.Json')
local f = assert(io.open('tools/rom_manifest_red_jp.json', 'rb'))
local manifest = assert(Json.decode(f:read('*a'))); f:close()
local speechKeys = {
  '_OaksLabRivalFedUpWithWaitingText', '_OaksLabOakChooseMonText',
  '_OaksLabRivalWhatAboutMeText', '_OaksLabOakBePatientText',
}
local function object(index, name, x, y)
  return {index=index, name=name, x=x, y=y, text='TEXT_'..name,
    sprite='SPRITE_FIX_NPC', movement='STAY', range='NONE'}
end
local function room(def, width, height)
  def.width, def.height, def.borderBlock = width, height, 0
  def.blocks = {}
  local tileset = {walkable={1},blocks={}}
  for by=0,height-1 do
    for bx=0,width-1 do
      local block={}
      for ty=0,3 do for tx=0,3 do block[ty*4+tx+1]=1 end end
      -- A desk blocks the three balls' cells. Other furniture is outside
      -- this test's route and deliberately not reproduced.
      if def.id=='OAKS_LAB' then
        for cy=0,1 do for cx=0,1 do
          local x,y=bx*2+cx,by*2+cy
          if y==3 and x>=6 and x<=8 then
            block[(cy*2+1)*4+cx*2+1]=0
          end
        end end
      end
      def.blocks[#def.blocks+1]=#tileset.blocks
      tileset.blocks[#tileset.blocks+1]=block
    end
  end
  return Map.new(def,tileset)
end
local function setup(held)
  Version.set('red_jp'); Input:init(); Game.input=Input; Game.sessionMenu=nil
  Game.data=setmetatable(require('tests.fixture_data').load(),{__index=Data})
  Game.data.constants.language='ja'
  Game.data.field.playerSprites={walk='SPRITE_FIX_PLAYER'}
  Game.data.font.charmap=manifest.fontCharmap
  Game.data.font.composites=manifest.fontComposites
  Game.data.text={}
  for _,key in ipairs(speechKeys)do Game.data.text[key]='テスト\nかいわ\vつづき\fおわり{DONE}'end
  Game.data.text._PalletTownOakHeyWaitDontGoOutText='まって{DONE}'
  Game.data.text._PalletTownOakItsUnsafeText='いこう{DONE}'
  Game.data.text._OaksLabOakDontGoAwayYetText='まだだよ{DONE}'
  Game.save=require('src.core.SaveData').newGame(Game.data)
  Game.save.options.textSpeed=1
  Game.stack=setmetatable({states={}},{__index=Stack})
  Game.renderer={worldViewSize=function()return 160,144 end}
  Font.load(Game.data); Strings.load(Game.data); Collision.load(Game.data)
  local defs={
    PALLET_TOWN={id='PALLET_TOWN',label='PalletTown',tileset='OVERWORLD',index=0,
      objects={object(1,'PALLETTOWN_OAK',8,5)}},
    OAKS_LAB={id='OAKS_LAB',label='OaksLab',tileset='DOJO',index=40,objects={
      object(1,'OAKSLAB_RIVAL',4,3),object(2,'OAKSLAB_CHARMANDER_POKE_BALL',6,3),
      object(3,'OAKSLAB_SQUIRTLE_POKE_BALL',7,3),object(4,'OAKSLAB_BULBASAUR_POKE_BALL',8,3),
      object(5,'OAKSLAB_OAK1',5,2),object(6,'OAKSLAB_POKEDEX1',2,1),
      object(7,'OAKSLAB_POKEDEX2',3,1),object(8,'OAKSLAB_OAK2',5,10),
      object(9,'OAKSLAB_GIRL',1,9),object(10,'OAKSLAB_SCIENTIST1',2,10),
      object(11,'OAKSLAB_SCIENTIST2',8,10),
    }},
  }
  Game.data.maps=defs
  local ow=setmetatable({scriptMoves={},ghosts={},npcs={},entities={},
    camera={x=0,y=0,follow=function()end}},{__index=OW})
  Game.overworld=ow
  -- The real enter() loads an imported map from disk. Bind its Game and
  -- registry, then supply authored maps at that IO boundary only.
  for _,fn in pairs(OW)do if type(fn)=='function'then
    for i=1,30 do
      local name=debug.getupvalue(fn,i); if not name then break end
      if name=='Game'then debug.setupvalue(fn,i,Game)
      elseif name=='mapScripts'then debug.setupvalue(fn,i,Scripts)end
    end
  end end
  function ow:setMap(id,x,y,facing)
    self.map=room(defs[id],id=='OAKS_LAB' and 5 or 10,id=='OAKS_LAB' and 6 or 10)
    self.player=Player.new(Game.data,x,y,facing)
    self.npcs={};self.entities={self.player};self.npcPool={}
    for _,d in ipairs(self.map.def.objects)do
      if d.name~='OAKSLAB_OAK1'then
        local npc=NPC.new(Game.data,id,d)
        self.npcs[#self.npcs+1]=npc;self.entities[#self.entities+1]=npc;self.npcPool[npc.id]=npc
      end
    end
  end
  ow.runner=Runner.new(Game,ow)
  ow:setMap('PALLET_TOWN',10,1,'up');ow.enter=false;Game.stack:push(ow)
  if held then Input:sourcePress(held,'held-cutscene')end
  T.check(Story.PALLET_TOWN.onStep(Game,ow,10,1),'Pallet step starts actual escort')
  return ow
end
local function tick(n)
  for _=1,n or 1 do Game:step(1/60)end
end
local function driveUntil(test,limit)
  for frame=1,limit do
    if frame%8==0 then Input:sourcePress('a','dialogue')
    elseif frame%8==1 then Input:sourceRelease('a','dialogue')end
    tick()
    if test()then Input:sourceRelease('a','dialogue');return frame end
  end
  error('progress deadline reached without forcing a callback')
end
local function walk(ow,dir,x,y)
  Input:sourcePress(dir,'walk')
  local arrived=false
  for _=1,120 do
    tick()
    if ow.player.cellX==x and ow.player.cellY==y and not ow.player.moving then arrived=true;break end
  end
  Input:sourceRelease(dir,'walk');tick()
  T.check(arrived,('input walks %s to %d,%d'):format(dir,x,y))
end
for _,held in ipairs({'none','up','down','right'})do
  local ow=setup(held~='none' and held or nil)
  local frames=driveUntil(function()return Game.save.flags.EVENT_OAK_ASKED_TO_CHOOSE_MON end,4000)
  Input:sourceRelease(held,'held-cutscene')
  T.check(frames<4000,held..': all four multi-page speeches complete')
  T.eq(ow.map.id,'OAKS_LAB','escort enters lab')
  T.eq(ow.player.cellX,5,'escort x exactly 5')
  T.eq(ow.player.cellY,3,'escort y exactly 3; held direction cannot leak')
  T.eq(Game.stack:top(),ow,'last dialogue really popped')
  T.eq(ow.emote,nil,'all three-frame callbacks drained')
  T.eq(#ow.scriptMoves,0,'script movement queue empty')
  T.check(not ow.runner:isRunning(),'no suspended script coroutine')
  T.check(not ow.transitioning and not ow.engaging and not ow.player.inputLocked,'world input gates clear')
  T.check(Game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB and Game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB_2,'both escort flags set')
  T.check(not Game.save.flags.EVENT_GOT_STARTER,'intro does not give a starter')
  for _,dir in ipairs({'up','left','right'})do
    T.check(not Collision.canMove(ow.map,ow.entities,ow.player,dir),dir..' blocked by desk/people, not a stuck script')
  end
  T.check(Collision.canMove(ow.map,ow.entities,ow.player,'down'),'south exit remains open')
  tick()
  walk(ow,'down',5,4)
  for x=6,8 do walk(ow,'right',x,4)end
  walk(ow,'left',5,4)
  walk(ow,'down',5,6)
  T.check(Game.stack:top()~=ow,'real onStep blocks leaving without starter with text')
  driveUntil(function()return Game.stack:top()==ow and not ow.runner:isRunning() and #ow.scriptMoves==0 end,500)
  T.eq(ow.player.cellY,5,'Oak pushes player one cell north')
  walk(ow,'up',5,4)
  T.check(not ow.player.inputLocked and not ow.runner:isRunning(),'movement still available after leaving warning')
end
T.finish()
