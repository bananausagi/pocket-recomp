-- Actual NPC interaction -> script runner -> trade, using authored text/art data.
-- No ROM is required. UI adapters only resolve the player's choices.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Japanese NPC trades')
local Version=require('src.core.GameVersion');Version.set('red_jp')
local Data=require('src.core.Data')
local before=os.getenv('JP_TRADE_BEFORE')
local seed=before and assert(loadfile(before..'/src/core/Data.lua'))().applyVersionedFieldData or Data.applyVersionedFieldData
local Game=require('src.core.Game')
local Input=require('src.core.Input');Input:init();Game.input=Input
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local TextBox=require('src.render.TextBox')
local Screens=require('src.ui.Screens')
local Runner=require('src.script.ScriptRunner')
local Flags=require('src.script.Flags')
local OW=require('src.world.OverworldController')
local Player=require('src.world.Player')
local Scripts=require('data.scripts.init')
local Json=require('src.link.Json')
local f=assert(io.open('tools/rom_manifest_red_jp.json'));local manifest=assert(Json.decode(f:read('*a')));f:close()
local expected=manifest.field.trades
local function clone(t)
 if type(t)~='table' then return t end
 local out={};for k,v in pairs(t)do out[k]=clone(v)end;return out
end
local function fresh()
 local d=setmetatable(require('tests.fixture_data').load(),{__index=Data})
 d.constants.language='ja';d.field.trades={}
 for _,r in ipairs(expected)do for _,id in ipairs({r.give,r.get})do
  d.pokemon[id]=clone(d.pokemon.FIXMON_A);d.pokemon[id].name=id=='RAICHU' and 'ライチュウ' or id=='ELECTRODE' and 'マルマイン' or 'ポケモン'
 end end
 for n=1,3 do
  d.text['_WannaTrade'..n..'Text']='{RAM:wInGameTradeGiveMonName}と\n{RAM:wInGameTradeReceiveMonName}を こうかん？'
  d.text['_NoTrade'..n..'Text']='こうかんを やめました。'
  d.text['_WrongMon'..n..'Text']='その ポケモンでは ありません。'
  d.text['_Thanks'..n..'Text']='こうかん ありがとう！'
  d.text['_AfterTrade'..n..'Text']='まえに こうかんしたね。'
 end
 d.text._ConnectCableText='こうかんを はじめます。'
 d.text._TradedForText='ポケモンを こうかんしました。'
 return d
end
local d=fresh();seed(d,'red_jp')
T.eq(#d.field.trades,10,'empty JP cache is restored without ROM reimport')
for i,row in ipairs(expected)do T.same(d.field.trades[i],row,'runtime repair matches primary manifest row '..i)end
local initial=d.field.trades;seed(d,'red_jp');T.eq(d.field.trades,initial,'second seed preserves existing table identity')
local other=fresh();other.field.trades=nil;seed(other,'red_jp');T.eq(#(other.field.trades or {}),10,'missing old table is restored')
if d.field.trades[1] and other.field.trades and other.field.trades[1] then
 d.field.trades[1].nickname='MOD';T.eq(other.field.trades[1].nickname,expected[1].nickname,'repairs do not share mutable rows')
end
for _,version in ipairs({'red','blue','yellow'})do
 local nonjp=fresh();nonjp.constants.language='en';seed(nonjp,version)
 T.eq(#nonjp.field.trades,version=='yellow' and 10 or 0,'non-JP '..version..' version behavior preserved')
end
local custom=fresh();custom.field.trades={{give='CUSTOM',get='CUSTOM',nickname='MY MOD'}}
local customTable=custom.field.trades;seed(custom,'red_jp');T.eq(custom.field.trades,customTable,'custom trade table remains authoritative')
T.eq(custom.field.trades[1].nickname,'MY MOD','custom nickname remains unchanged')

-- Keep actual show_text substitution and ask/trade commands; these adapters
-- stand in for pressing YES/NO, choosing a party slot and finishing animation.
TextBox.new=function(game,text,done,opts)return{kind='text',text=text,done=done,opts=opts or {}}end
Screens.push=function(game,name,opts)game.stack:push({kind=name,opts=opts});return game.stack:top()end
local texts,anims
local stack={states={}}
function stack:push(state)self.states[#self.states+1]=state end
function stack:top()return self.states[#self.states] end
function stack:pop()return table.remove(self.states)end
Game.stack=stack
-- enter() binds these two shared upvalues, but loading a real map would require
-- ROM data. Bind its exact dependencies and retain every interaction method.
for _,fn in pairs(OW)do if type(fn)=='function' then
 for n=1,30 do local name=debug.getupvalue(fn,n);if not name then break end
  if name=='Game' then debug.setupvalue(fn,n,Game)
  elseif name=='mapScripts' then debug.setupvalue(fn,n,Scripts) end
 end
end end
local sites={
 {'ROUTE_11_GATE_2F','TEXT_ROUTE11GATE2F_YOUNGSTER',1},
 {'ROUTE_2_TRADE_HOUSE','TEXT_ROUTE2TRADEHOUSE_GAMEBOY_KID',2},
 {'CINNABAR_LAB_FOSSIL_ROOM','TEXT_CINNABARLABFOSSILROOM_SCIENTIST2',4},
 {'VERMILION_TRADE_HOUSE','TEXT_VERMILIONTRADEHOUSE_LITTLE_GIRL',5},
 {'ROUTE_18_GATE_2F','TEXT_ROUTE18GATE2F_YOUNGSTER',6},
 {'CERULEAN_TRADE_HOUSE','TEXT_CERULEANTRADEHOUSE_GAMBLER',7},
 {'CINNABAR_LAB_TRADE_ROOM','TEXT_CINNABARLABTRADEROOM_GRAMPS',8},
 {'CINNABAR_LAB_TRADE_ROOM','TEXT_CINNABARLABTRADEROOM_BEAUTY',9},
 {'UNDERGROUND_PATH_ROUTE_5','TEXT_UNDERGROUNDPATHROUTE5_LITTLE_GIRL',10},
}
local vec={up={0,-1},down={0,1},left={-1,0},right={1,0}}
local function setup(site,dir,missing)
 Game.data=fresh();if not missing then seed(Game.data,'red_jp')end
 Game.save=Save.newGame();Game.save.party={Pokemon.new(Game.data,expected[site[3]].give,17)}
 stack.states={};texts={};anims={}
 local v=vec[dir or 'up'];local player={cellX=3,cellY=3,px=48,py=48,facing=dir or 'up',moving=false,facingCell=Player.facingCell}
 local npc={cellX=3+v[1],cellY=3+v[2],def={text=site[2]},facePlayer=function()end}
 local ow=setmetatable({player=player,npcs={npc},entities={npc},map={id=site[1],def={label=site[1]},isCounterCell=function()return false end}},{__index=OW})
 ow.runner=Runner.new(Game,ow);Game.overworld=ow
 return ow,npc
end
local function drain(ow,action)
 for _=1,25 do
  local s=stack:pop();if not s then break end
  if s.kind=='text' then
   texts[#texts+1]=s.text
   if s.opts.choice then s.opts.choice(action~='decline')else s.done()end
  elseif s.kind=='PartyMenu' then
   if action=='cancel' then s.opts.onCancel()else s.opts.onSwitch(Game.save.party[1])end
  elseif s.kind=='TradeAnim' then anims[#anims+1]=s.opts;s.opts.onDone()
  else error('unexpected screen '..tostring(s.kind)) end
 end
 T.check(not ow.runner:isRunning(),'interaction coroutine finishes')
 T.check(not ow.npcs[1].frozen,'NPC unfreezes after conversation')
end
-- The exact old failure: adjacency resolves, NPC script runs, but no dialogue.
local ow=setup(sites[7],'up',true);ow:interact()
T.eq(#stack.states,0,'unrepaired empty table reproduces the silent NPC')
T.check(not ow.runner:isRunning(),'old silent failure exits before an offer')
for _,site in ipairs(sites)do
 local ow,npc=setup(site);ow:interact()
 T.check(stack:top() and stack:top().opts.choice,'A reaches Japanese offer at '..site[1]..'/'..site[2])
 drain(ow,'decline')
 T.eq(#texts,2,'decline shows offer and reply for trade '..site[3])
 T.eq(Game.save.party[1].species,expected[site[3]].give,'decline keeps party for trade '..site[3])
end
local gramps=sites[7]
ow=setup(gramps);ow:interact();drain(ow,'yes')
T.eq(texts[1],'ライチュウと\nマルマインを こうかん？','actual prompt substitutes Japanese ROM names')
T.eq(#texts,4,'successful exchange displays offer/cable/result/thanks')
T.eq(Game.save.party[1].species,'ELECTRODE','Gramps gives Electrode')
T.eq(Game.save.party[1].nickname,'おマル','Gramps uses Japanese nickname')
T.eq(Game.save.party[1].level,17,'received Pokemon retains sent level')
T.eq(Game.save.party[1].ot,'トレーナー','original trainer label is Japanese')
T.eq(anims[1] and anims[1].enemyName,'トレーナー','trade animation names the Japanese trainer')
T.check(Flags.get(Game.save,'EVENT_TRADED_RAICHU_FOR_ELECTRODE'),'completion flag retains existing index')
T.check(Game.save.pokedex.owned.ELECTRODE,'received Pokemon is registered')
ow:interact();drain(ow,'yes')
T.eq(texts[#texts],'まえに こうかんしたね。','completed trade shows after-trade text')
T.eq(#anims,1,'completed trade cannot repeat')
for _,action in ipairs({'cancel','wrong'})do
 ow=setup(gramps)
 if action=='wrong' then Game.save.party={Pokemon.new(Game.data,'ABRA',9)} end
 local sent=Game.save.party[1];ow:interact();drain(ow,action)
 T.eq(Game.save.party[1],sent,action..' preserves original party object')
 T.check(not Flags.get(Game.save,'EVENT_TRADED_RAICHU_FOR_ELECTRODE'),action..' leaves trade available')
 T.eq(#anims,0,action..' never starts transfer animation')
end

-- Use real free-camera bearing and FreeMove.tick, with rendering-only services
-- stubbed. Both camera rungs must still reach the same native trade script.
local base='vendor/jp-mods/DRAMALESS_SHAPE/lib/'
local mode='first'
local mods={Mat4=dofile(base..'Mat4.lua'),
 VoxelState={level=6,isFreeCam=function()return mode~='orbit'end},
 Voxel3D={available=function()return true end},WorldCurve={},
 ThirdPerson={extended=function()return mode=='third' end},ModSetting={new=function()return{get=function()return false end}end}}
local V={require=function(name)return assert(mods[name],name)end}
mods.FirstPerson=assert(loadfile(base..'FirstPerson.lua'))(V)
local Free=assert(loadfile(base..'FreeMove.lua'))(V)
local yaw={down=0,right=math.pi/2,up=math.pi,left=-math.pi/2}
for _,camera in ipairs({'orbit','first','third'})do for dir in pairs(vec)do
 mode=camera;ow=setup(gramps,dir)
 Input.pressed={a=true}
 if camera=='orbit' then ow:interact()else
  mods.FirstPerson.yaw=yaw[dir];Free.drop();Free.tick(ow)
 end
 Input.pressed={}
 T.check(stack:top() and stack:top().opts.choice,camera..' '..dir..' reaches trade offer')
 drain(ow,'decline')
end end
Version.set('red')
ow=setup(gramps)
Game.data.constants.language='en'
Game.data.field.trades=clone(expected)
Game.data.field.trades[8].nickname='CUSTOM TRADE'
ow:interact();drain(ow,'yes')
T.eq(Game.save.party[1].ot,'TRAINER','non-Japanese original trainer label remains unchanged')
T.eq(anims[1] and anims[1].enemyName,'TRAINER','non-Japanese animation label remains unchanged')
T.eq(Game.save.party[1].nickname,'CUSTOM TRADE','trade uses an authoritative custom nickname')
Version.set('red_jp')
T.finish()
