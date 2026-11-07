package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('JP25 path follower')
local Runtime=require('src.mods.Runtime')
Runtime.install(require('src.mods.Events').new(),require('src.mods.Hooks').new())
local made,released=0,0
package.loaded['src.render.JapaneseFollowerSprite']={new=function(data,mon)
  made=made+1
  return {def={image=mon.species},draw=function()end,release=function()released=released+1 end}
end}
local F=require('src.world.JapaneseFollower')
local Collision=require('src.world.Collision')
local Save=require('src.core.SaveSerializer')
local Json=require('src.link.Json')
local function clone(value)
  if type(value)~='table' then return value end
  local out={}for k,v in pairs(value)do out[k]=clone(v)end return out
end
local function fixture()
  local data=require('tests.fixture_data').load();data.constants.language='ja'
  local p={px=48,py=48,cellX=3,cellY=3,facing='right',inputLocked=false}
  local ow={isOverworld=true,map={id='FIX_MAP'},player=p,npcs={},entities={p},scriptMoves={},runner={isRunning=function()return false end}}
  local mon={species='FIXMON_A',hp=20,level=10,dvs={attack=2},moves={{id='FIX_TACKLE',pp=5}},nickname='テスト'}
  local game={data=data,save={party={mon},boxes={{}},options={},flags={EVENT_GOT_STARTER=true,EVENT_BATTLED_RIVAL_IN_OAKS_LAB=true}},overworld=ow,stack={states={ow}}}
  return game,ow,mon
end
local function step(game,ow,dx,dy)
  local p=ow.player;p.px,p.py=p.px+dx,p.py+dy
  p.cellX,p.cellY=math.floor(p.px/16),math.floor(p.py/16)
  F.update(game,ow)
end
local function emerge(game,ow)
  F.update(game,ow)
  for _=1,40 do step(game,ow,1,0) end
  return ow.jpFollowerState.actor
end

do
  local game,ow,mon=fixture()
  T.eq(F.enabled(game),true,'absent option defaults on in Japanese game')
  T.eq(F.selected(game),mon,'healthy lead follows by default')
  local before=Save.encode(game.save)
  local actor=emerge(game,ow)
  T.eq(ow.player.px-actor.px,18,'trail stands eighteen pixels behind actual route')
  T.eq(actor.py,ow.player.py,'straight path stays aligned')
  T.eq(#ow.entities,2,'only one presentation actor attached')
  T.eq(#ow.npcs,0,'never placed in NPC/script/interaction collection')
  T.eq(Collision.occupied(ow.entities,actor.cellX,actor.cellY,ow.player),nil,'real collision permits player on follower cell')
  T.eq(Save.encode(game.save),before,'following updates do not mutate saved gameplay state')
  T.eq(#ow.scriptMoves,0,'no scripted movement entries are created')
  for _=1,20 do F.update(game,ow);F.prepareDraw(game,ow)end
  T.eq(#ow.entities,2,'repeated update/draw does not duplicate actor')
  T.eq(actor.moving,false,'stationary companion stops animating')
end

do
  local game,ow=fixture();F.update(game,ow)
  for _=1,32 do step(game,ow,1,0)end
  for i=1,32 do
    step(game,ow,0,1)
    local actor=ow.jpFollowerState.actor
    if i<18 then T.eq(actor.py,48,'turn follows prior horizontal corridor '..i)
    else T.eq(actor.px,80,'turn follows exact vertical corridor '..i)end
  end
  local actor=ow.jpFollowerState.actor
  T.eq(actor.py,62,'L corner preserves full path distance')
  T.eq(actor.facing,'down','facing follows companion travel tangent')
end

do
  local game,ow=fixture();F.update(game,ow)
  for _=1,200 do step(game,ow,.2,.2)end
  local a=ow.jpFollowerState.actor
  local distance=math.sqrt((a.px-ow.player.px)^2+(a.py-ow.player.py)^2)
  T.check(math.abs(distance-18)<.001,'free analog diagonal keeps Euclidean trail distance')
  local largest=0
  for i=1,30000 do
    step(game,ow,.01,0)
    largest=math.max(largest,#ow.jpFollowerState.points)
  end
  T.check(largest<=146,'tiny analog samples have a bounded history')
  T.check(#ow.jpFollowerState.points<=146,'long walks retain only local trail')
end

do
  local game,ow=fixture();F.update(game,ow)
  for i=1,64 do
    step(game,ow,4,0)
    local a=ow.jpFollowerState.actor
    T.check(ow.player.px-a.px<=18.001,'B dash cannot leave companion behind '..i)
  end
  local a=ow.jpFollowerState.actor
  local sprite,x,y=a:pose()
  T.check(y==a.py or y==a.py-1,'walking bob is at most one world pixel')
  local before=clone(game.save)
  F.reset(ow);T.eq(#ow.entities,1,'reset removes render actor')
  T.same(game.save,before,'reset never changes progress/items/party')
end

do
  local game,ow=fixture();local a=emerge(game,ow)
  local previousX,total=a.px,ow.jpFollowerState.total
  ow.map={id='NEXT_MAP'};ow.entities={ow.player};ow.npcs={}
  ow.player.px=ow.player.px-96;ow.player.cellX=ow.player.cellX-6
  F.onMapEntered(game,ow,{seamless=true});F.rebase(ow,-6,0)
  T.eq(a.px,previousX-96,'connection preserves actor using same map translation')
  T.eq(ow.jpFollowerState.total,total,'connection preserves path progress')
  T.eq(#ow.entities,2,'connection attaches actor to new entity collection')
  step(game,ow,1,0)
  T.eq(ow.player.px-a.px,18,'first post-seam step retains exact separation')
  ow.map={id='HOUSE'};ow.player.px,ow.player.py=32,32;ow.player.cellX,ow.player.cellY=2,2;ow.entities={ow.player}
  F.onMapEntered(game,ow,{via='door'})
  T.eq(ow.jpFollowerState,nil,'door warp drops old-map trail')
  F.update(game,ow);T.eq(#ow.entities,1,'warp does not spawn through adjacent wall')
  for _=1,8 do step(game,ow,1,0)end
  T.eq(#ow.entities,2,'companion emerges after walking away from door')
  step(game,ow,1000,1000)
  T.eq(#ow.entities,1,'unannounced teleport discards old actor immediately')
end

for _,gate in ipairs({'option','english','link','bike','surf','input','transition','engaging','hidden','pan','emote','teleport','fly','flyArrive','spin','fall','arrive','heal','fish','cut','pikaHop','spinner','script','moves','queue','starter','oak','yellow','battle','nestedBattle','trainerTransition','seamlessTransition'})do
  local game,ow,mon=fixture();emerge(game,ow)
  if gate=='option'then game.save.options.jpFollower=false
  elseif gate=='english'then game.data.constants.language='en'
  elseif gate=='link'then game.linkSession={}
  elseif gate=='bike'then game.save.onBike=true
  elseif gate=='surf'then ow.player.surfing=true
  elseif gate=='input'then ow.player.inputLocked=true
  elseif gate=='transition'then ow.transitioning=true
  elseif gate=='engaging'then ow.engaging=true
  elseif gate=='hidden'then ow.playerHidden=true
  elseif gate=='pan'then ow.cameraPan={}
  elseif gate=='emote'then ow.emote={}
  elseif gate=='teleport'then ow.teleportOut={}
  elseif gate=='fly'then ow.flyAnim={}
  elseif gate=='flyArrive'then ow.flyArrive={}
  elseif gate=='spin'then ow.spinArrive=true
  elseif gate=='fall'then ow.holeFall={}
  elseif gate=='arrive'then ow.holeArrive={}
  elseif gate=='heal'then ow.healAnim={}
  elseif gate=='fish'then ow.fishing={}
  elseif gate=='cut'then ow.cutAnim={}
  elseif gate=='pikaHop'then ow.pikaHop={}
  elseif gate=='spinner'then ow.spinnerSliding=true
  elseif gate=='script'then ow.runner.isRunning=function()return true end
  elseif gate=='moves'then ow.scriptMoves={{entity=ow.player}}
  elseif gate=='queue'then ow.pendingScripts={{}}
  elseif gate=='starter'then game.save.flags.EVENT_GOT_STARTER=nil
  elseif gate=='oak'then ow.map.id='OAKS_LAB';game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB=nil
  elseif gate=='yellow'then ow.npcs={{pikachuFollower=true}}
  elseif gate=='battle'then game.stack.states[#game.stack.states+1]={isBattleState=true}
  elseif gate=='nestedBattle'then game.stack.states[#game.stack.states+1]={battle={}}
  elseif gate=='trainerTransition'then game.stack.states[#game.stack.states+1]={trainerBattle={}}
  elseif gate=='seamlessTransition'then game.stack.states[#game.stack.states+1]={seamlessBattle={}} end
  local before=Save.encode(game.save)
  F.prepareDraw(game,ow)
  T.eq(ow.jpFollowerState,nil,gate..' draw gate removes stale actor before renderer')
  T.eq(#ow.entities,1,gate..' does not leak actor into 3D pipeline')
  T.eq(F.select(game,mon),false,gate..' disallows stale party-menu commit')
  T.eq(Save.encode(game.save),before,gate..' preserves gameplay and settings')
end

do
  local game,ow,mon=fixture();local second=clone(mon);second.species='FIXMON_B'
  game.save.party[2]=second
  T.eq(F.select(game,second),true,'choose second party individual')
  local identity=second.jpFollowerIdentity
  T.check(type(identity)=='number' and identity>0,'selection saves a scalar identifier')
  T.eq(F.selected(game),second,'explicit party selection wins')
  game.save.party={second,mon};T.eq(F.selected(game),second,'selection survives party reordering')
  second.species='FIXMON_A';second.nickname='へんこう';second.level=42
  T.eq(F.selected(game),second,'same individual survives evolution/name/level changes')
  second.hp=0;T.eq(F.selected(game),mon,'fainted selected individual uses healthy fallback')
  T.eq(game.save.jpFollowerIdentity,identity,'temporary fallback preserves preferred individual')
  second.hp=20;game.save.party={mon};game.save.boxes[1]={second}
  T.eq(F.selected(game),mon,'boxed selected individual uses healthy fallback')
  game.save.party={mon,second};game.save.boxes[1]={}
  T.eq(F.selected(game),second,'withdrawal restores preferred individual')
  local encoded=Save.encode(game.save)
  local decoded=assert(Save.decode(encoded))
  game.save=decoded
  T.eq(F.selected(game),decoded.party[2],'stable selection survives actual save roundtrip')
  T.eq(F.clearSelection(game),true,'return to automatic selection')
  T.eq(F.selected(game),decoded.party[1],'automatic selection uses current healthy lead')
  T.eq(decoded.options.jpFollower,nil,'party selection never changes global enable preference')
  local duplicate=clone(decoded.party[2]);decoded.party[3]=duplicate
  decoded.jpFollowerIdentity=duplicate.jpFollowerIdentity
  T.eq(F.selected(game),decoded.party[1],'ambiguous copied identities safely fall back to healthy lead')
  T.eq(F.isSelected(game,duplicate),false,'ambiguous local-trade duplicate is not presented as selected')
  T.eq(F.select(game,duplicate),true,'duplicate imported ID can be selected safely')
  T.neq(duplicate.jpFollowerIdentity,decoded.party[2].jpFollowerIdentity,'duplicate ID is reassigned')
  T.eq(F.selected(game),duplicate,'duplicate identity cannot select wrong mon')
end

do
  local game,ow,mon=fixture();local menu={game=game,submenu=true};local items={{action='stats'},{action='cancel'}}
  F.addEntry(menu,items,mon);F.addEntry(menu,items,mon)
  T.eq(#items,3,'party action inserted once')
  T.eq(items[2].label,'つれてあるく','party action uses Japanese label before cancel')
  items[2].onSelect(mon,game)
  T.eq(F.isSelected(game,mon),true,'party action selects the actual individual')
  T.eq(menu.submenu,nil,'party action closes old submenu')
  items={{action='cancel'}};F.addEntry(menu,items,mon)
  T.eq(items[1].label,'せんとうに おまかせ','chosen individual can return to automatic lead')
  items[1].onSelect(mon,game);T.eq(game.save.jpFollowerIdentity,nil,'automatic action clears only preference')
  game.save.options.jpFollower=false;items={{action='cancel'}};F.addEntry(menu,items,mon)
  T.eq(#items,1,'disabled setting has no enabled-looking party action')
end

do
  local game,ow,mon=fixture();local a=emerge(game,ow)
  game.stack.states[#game.stack.states+1]={isTextBox=true}
  F.prepareDraw(game,ow);T.eq(ow.jpFollowerState.actor,a,'ordinary menu/dialog retains companion')
  mon.hp=0;F.prepareDraw(game,ow)
  T.eq(ow.jpFollowerState,nil,'all fainted party disappears even while menu pauses OW')
end

-- Drive the actual Player, bundled running-speed hook, and Dramaless analog
-- movement implementation too. The companion consumes the resulting pose;
-- it does not implement a parallel movement simulation.
do
  local Game=require('src.core.Game')
  local Player=require('src.world.Player')
  local OW=require('src.world.OverworldController')
  local mx,my=1,0
  local FP={driving=function()return false end,releaseBody=function()end,
    pointTravel=function(x,z)return math.abs(x)>=math.abs(z) and (x>=0 and 'right' or 'left') or (z>=0 and 'down' or 'up')end,
    moveVector=function()return mx,my end}
  local FM=assert(loadfile('vendor/jp-mods/DRAMALESS_SHAPE/lib/FreeMove.lua'))({require=function(name)assert(name=='FirstPerson');return FP end})
  local opts,defaults={},{}
  local mod={options={define=function(_,rows)for _,row in ipairs(rows)do defaults[row.key]=row.default end end,
    get=function(_,key)if opts[key]~=nil then return opts[key]end;return defaults[key]end},
    hooks={wrap=function(_,name,fn)return Runtime.hooks:wrap(name,fn,0,'running_shoes')end},
    events={on=function()end},log={info=function()end},
    find=function(id)if id=='DRAMALESS_SHAPE'then return{id=id,version='test',exports={lib={require=function(name)assert(name=='FreeMove');return FM end}}}end end}
  assert(loadfile('vendor/jp-mods/running_shoes/main.lua'))()(mod);opts.fx='off'
  for _,mode in ipairs({'grid','analog'})do
    for _,speed in ipairs({'1.5','2','3','4'})do
      FM.drop();opts.speed=speed;mx,my=1,0
      local game,ow=fixture();game.data.field.playerSprites={walk='SPRITE_FIX_PLAYER'}
      game.input={isDown=function(_,key)return key=='b' end,wasPressed=function()return false end}
      for k,v in pairs(game)do Game[k]=v end
      local p=Player.new(game.data,4,4,'right');p.turnArmed=false
      ow.player=p;ow.entities={p};setmetatable(ow,{__index=OW})
      ow.map={id='FIX_MAP',def={tileset='FIX_OUT'},inBounds=function()return true end,
        isWalkableCell=function()return true end,cellTile=function()return 0 end}
      ow.onStepComplete=function()end;ow.onSlopeMap=function()return false end
      ow.checkEdgeExit=function()return false end;ow.checkLedgeHop=function()return false end
      ow.checkBoulderPush=function()return false end;ow.canCollisionWarp=function()return false end
      game.stack.top=function()return ow end
      Game.save.onBike=false;F.update(game,ow)
      local before=Save.encode(game.save)
      for frame=1,96 do
        Runtime.call('input.step',function()end,Game,1/60)
        if mode=='analog'then FM.tick(ow)
        elseif not p.moving then p:tryMove('right',ow.map,ow.entities)end
        p:update();F.update(game,ow)
        local a=ow.jpFollowerState and ow.jpFollowerState.actor
        T.check(a and p.px-a.px<=18.001,mode..' actual run '..speed..' frame '..frame..' keeps up')
      end
      T.eq(Save.encode(game.save),before,mode..' actual movement has no companion save mutations')
      T.eq(#ow.entities,2,mode..' actual collision path preserves single actor')
      T.eq(#ow.npcs,0,mode..' actual movement never enrolls companion as NPC')
      if mode=='analog'then
        mx,my=math.sqrt(.5),math.sqrt(.5)
        for _=1,32 do FM.tick(ow);p:update();F.update(game,ow)end
        local a=ow.jpFollowerState.actor
        T.check(math.abs(a.py-p.py)>1 and math.abs(a.px-p.px)>1,'actual analog path trails diagonally at speed '..speed)
      end
      F.reset(ow)
    end
  end
  FM.drop()
end

do
  local f=assert(io.open('tools/rom_manifest_red_jp.json'));local manifest=Json.decode(f:read('*a'));f:close()
  for _,species in ipairs(manifest.dexOrder)do
    local game,ow=fixture();game.data.pokemon[species]={name=species}
    game.save.party={{species=species,hp=1}}
    local a=emerge(game,ow)
    T.check(a and a.sprite.def.image==species,'all-151 selection is species-generic: '..species)
  end
end
T.check(released>0 and released<=made,'retired actors release renderer resources')
T.finish()
