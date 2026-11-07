package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local now=0;love.timer={getTime=function()return now end}
local T=require('tests.harness').suite('jp32 effect triggers, isolation and persistence')
local Prefs=require('src.core.JapaneseEffects')
local Save=require('src.core.SaveData')
local Transfer=require('src.import.SettingsTransfer')
local Json=require('src.link.Json')
local Home=require('src.import.LauncherSettings')
local Menu=require('src.ui.OptionsMenu')
local Catalog=require('src.ui.JapaneseSettingsCatalog')
require('src.core.GameVersion').set('red_jp')
local data={constants={language='ja'}};require('src.core.Strings').load(data)
local opt=Save.mergeOptions({})
local game={save={options=opt},data=data};package.loaded['src.core.Game']=game
local home=Home.open({options=opt,save=function()return true end},'red_jp')
local menu=Menu.new(game)
local function find(sections,id)
  for _,s in ipairs(sections)do for _,row in ipairs(s.rows or {}) do if row.id==id then return row end end end
end
for _,row in ipairs(Prefs.rows) do
  T.eq(opt[row.id],true,row.id..' migration default')
  T.eq(Save.mergeOptions({[row.id]=false})[row.id],false,row.id..' explicit OFF retained')
  T.eq(Save.mergeOptions({[row.id]='false'})[row.id],true,row.id..' invalid saved value normalized')
  T.eq(Catalog.group(row.id),row.group,row.id..' separate settings category')
  local h=find(home.sections,row.id);local m
  for _,r in ipairs(menu.rows)do if r.id==row.id then m=r end end
  T.check(h and m,row.id..' in both menus')
  h.step(1);T.eq(m.value(game),'オフ',row.id..' live toggle shared')
  T.eq(opt[row.id],false,row.id..' actually toggled')
end
Save.saveOptions(opt);local loaded=Save.loadOptions()
local copied=assert(Transfer.import(assert(Transfer.export(loaded)),{}))
for _,row in ipairs(Prefs.rows)do
  T.eq(loaded[row.id],false,row.id..' survives restart')
  T.eq(copied[row.id],false,row.id..' JSON roundtrip')
  local imported=assert(Transfer.import(Json.encode({format=Transfer.FORMAT,version=1,options={musicVol=3}}),copied))
  T.eq(imported[row.id],false,row.id..' old import retains preference')
  opt[row.id]=true
end
local mods={EffectParticles={LIMIT=128,draw=function(p)return #p end},
  VoxelScene={groundAt=function()return 0 end},Voxel3D={effects=function()end}}
local V={require=function(name)return assert(mods[name],name)end}
local E=assert(loadfile('vendor/jp-mods/DRAMALESS_SHAPE/lib/SceneEffects.lua'))(V)
local map={def={tileset='OVERWORLD'},inBounds=function()return true end,
  isWaterCell=function(self)return self.surface=='water'end,
  isGrassCell=function(self)return self.surface=='grass'end,
  isWalkableCell=function()return true end,cellTile=function()return 4 end}
local ow={map=map,player={px=32,py=32,facing='down'}}
local function step(n)now=now+(n or .1);return E.world(ow)end
local function count(s,key)local n=0;for _,p in ipairs(s.particles)do if p.key==key then n=n+1 end end;return n end
local s=step();T.eq(#s.particles,0,'standing still does not emit footsteps')
ow.player.px=40;s=step();T.check(count(s,'jpFxFootsteps')>0,'soil step emits dust')
opt.jpFxFootsteps=false;s=step();T.eq(count(s,'jpFxFootsteps'),0,'OFF removes existing footsteps immediately')
map.surface='grass';ow.player.px=48;s=step();T.check(s.step[4]>0,'grass step bends nearby tips')
opt.jpFxGrass=false;s=step();T.eq(s.step[4],0,'grass OFF restores geometry')
opt.jpFxGrass=true;ow.player.px=56;step();now=now+1;s=step()
for _=1,8 do s=step()end
T.eq(s.step[4],0,'grass returns to original geometry')
map.surface='water';opt.jpFxFootsteps=true;ow.player.px=64;s=step()
T.check(count(s,'jpFxFootsteps')>0,'shallow water step emits splash')
ow.player.surfing=true;ow.player.px=72;s=step();T.check(count(s,'jpFxWater')>0,'surf travel emits wake')
opt.jpFxWater=false;s=step();T.eq(count(s,'jpFxWater'),0,'water OFF clears wake separately')
T.check(count(s,'jpFxFootsteps')>0,'water OFF leaves independent footstep effect')
opt.jpFxWater=true;ow.fishing={};s=step();T.check(count(s,'jpFxWater')>=7,'casting triggers splash and ripple')
T.check(s.wind[2]>0 and s.wind[3]>0,'outdoors receives breeze and cloud shadow')
opt.jpFxWind=false;s=step();T.eq(s.wind[2]+s.wind[3],0,'wind OFF removes wind and clouds')
map.def.tileset='FOREST'
for _=1,7 do s=step()end
T.check(count(s,'jpFxAmbient')>0,'forest emits drifting leaves')
opt.jpFxAmbient=false;s=step();T.eq(count(s,'jpFxAmbient'),0,'ambience OFF clears particles')
opt.jpFxAmbient=true;map.def.tileset='CAVERN'
for _=1,7 do s=step()end
local found=false;for _,p in ipairs(s.particles)do if p.kind==4 and p.key=='jpFxAmbient' then found=true end end
T.check(found,'cave emits droplets')
map.def.tileset='HOUSE'
for _=1,7 do s=step()end
found=false;for _,p in ipairs(s.particles)do if p.kind==0 and p.key=='jpFxAmbient' then found=true end end
T.check(found,'room emits lit dust')
map.surface=nil
local b={game=game,data={moves={EMBER={type='FIRE'},EARTHQUAKE={type='GROUND'}}},phase='menu',
  player={mon={species='PIKACHU'}},enemy={mon={species='GASTLY'},shownStatus='PSN'}}
local arena={encounter=true,map=map,player={20,40},enemy={40,20},groundY=0}
local function battle(dt)now=now+(dt or .1);return E.battle(arena,b)end
s=battle();battle()
local _,lift=E.pose(arena,b,'enemy',false);T.check(lift>0,'floating species idles in world space')
opt.jpFxIdle=false;local dx,dy,dz,sx,sy=E.pose(arena,b,'enemy',false)
T.check(dx==0 and dy==0 and dz==0 and sx==1 and sy==1,'idle OFF gives native placement')
b.phase='messages';b.jpFxMoveSerial=1;b.jpFxMoveName='EMBER';b.jpFxMoveTarget=b.enemy
s=battle();s=battle();T.check(s.light[4]>0 and s.lightColor[1]>s.lightColor[3],'fire reflects warm light')
T.check(s.gust[4]>0,'move reacts on environment')
opt.jpFxMoveLight=false;s=battle();T.eq(s.light[4],0,'lighting OFF removes reflection')
T.check(s.gust[4]>0,'lighting OFF does not disable environment')
opt.jpFxBattleEnvironment=false;s=battle();T.eq(s.gust[4],0,'environment OFF removes gust')
b.jpFxHitSerial=1;b.jpFxHitTarget=b.enemy;s=battle();s=battle()
dx,dy,dz=E.pose(arena,b,'enemy',false);T.check(dx>0 and dz<0,'recipient recoils away from attacker')
T.check(count(s,'jpFxHitReaction')>0,'impact emits contact dust')
opt.jpFxHitReaction=false;s=battle();dx,dy,dz=E.pose(arena,b,'enemy',false)
T.check(dx==0 and dy==0 and dz==0 and count(s,'jpFxHitReaction')==0,'reaction OFF restores native placement')
opt.jpFxBattleEnvironment=true;b.jpFxMoveSerial=2;b.jpFxMoveName='EARTHQUAKE'
b.jpFxHitSerial=2;s=battle();T.check(count(s,'jpFxBattleEnvironment')>0,'heavy impact emits stones independently')
for _=1,8 do s=battle()end
T.check(count(s,'jpFxStatus')>0,'visible poison produces bubbles')
for _,status in ipairs({'PAR','SLP','BRN','FRZ'})do
  b.enemy.shownStatus=status
  for _=1,8 do s=battle()end
  T.check(count(s,'jpFxStatus')>0,status..' emits visible status')
end
opt.jpFxStatus=false;s=battle();T.eq(count(s,'jpFxStatus'),0,'status OFF removes particles')
opt.reduceMotion=true;opt.jpFxMoveLight=true;opt.jpFxIdle=true
b.phase='menu';s=battle();T.eq(#s.particles,0,'reduce motion clears all battle particles')
dx,dy,dz,sx,sy=E.pose(arena,b,'enemy',false)
T.check(dx==0 and dy==0 and dz==0 and sy==1,'reduce motion suppresses idle')
s=step();T.eq(#s.particles,0,'reduce motion clears field particles')
opt.reduceMotion=false;opt.animations=false;b.jpFxMoveSerial=3;b.phase='messages';s=battle();s=battle()
T.eq(s.light[4]+s.gust[4],0,'native animations OFF suppresses battle effects')
opt.animations=true
for _=1,600 do b.jpFxHitSerial=b.jpFxHitSerial+1;s=battle(.01)end
T.check(#s.particles<=E.LIMIT and E.stats.peak<=E.LIMIT,'rapid multi-hit effects have bounded live particles')
E.finish(arena);map.surface='water';b.jpFxHitSerial=b.jpFxHitSerial+1
opt.jpFxHitReaction=true;s=battle()
T.eq(count(s,'jpFxBattleEnvironment'),0,'water impacts do not throw dry stones')
found=false;for _,p in ipairs(s.particles)do if p.key=='jpFxHitReaction' and p.kind==4 then found=true end end
T.check(found,'water impact splashes instead of dust')
E.finish(arena);T.eq(arena.jpSceneEffects,nil,'battle exit releases effect state')
T.finish()
