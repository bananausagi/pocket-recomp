package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('jp35 independent additions and duplicate suppression')
local Prefs=require('src.core.JapaneseEffects')
local Save=require('src.core.SaveData')
local Transfer=require('src.import.SettingsTransfer')
local opt=Save.mergeOptions({jpFxGrass=false,jpFxIdle=false,jpFxDensity='high'})
local now,moon=0,false;love.timer={getTime=function()return now end}
local game={save={options=opt}};package.loaded['src.core.Game']=game
local modules={EffectParticles={LIMIT=128},VoxelScene={groundAt=function()return 3 end},
  DayNight={body=function()return {dx=.2,dy=.7,dz=.3,moon=moon}end}}
local E=assert(loadfile('vendor/jp-mods/DRAMALESS_SHAPE/lib/SceneEffects.lua'))({require=function(n)return assert(modules[n],n)end})
local function off()for _,r in ipairs(Prefs.rows)do opt[r.id]=false end end
local function count(s,key,kind)
  local n=0;for _,p in ipairs(s.particles)do if p.key==key and (not kind or p.kind==kind)then n=n+1 end end;return n
end
local map={def={tileset='OVERWORLD'},inBounds=function()return true end,
  isWalkableCell=function()return true end,isGrassCell=function()return false end,
  isWaterCell=function(s)return s.wet end,cellTile=function()return 4 end}
local ow={map=map,player={px=32,py=32}}
local function world(n)now=now+(n or .1);return E.world(ow)end
off();opt.jpFxTracks=true;world();ow.player.px=40
local s=world();T.eq(count(s,'jpFxTracks',7),1,'one dry print per footfall')
T.check(s.particles[1].y>3 and s.particles[1].y<3.5,'print lies on actual ground height')
local z=s.particles[1].z;ow.player.px=48;s=world()
T.check(s.particles[2].z~=z,'left and right feet alternate')
opt.jpFxTracks=false;s=world();T.eq(#s.particles,0,'tracks OFF clears existing footprints')
off();opt.jpFxTracks=true;opt.jpFxWater=true;map.wet=true;ow.player.surfing=true;world()
map.wet=false;ow.player.surfing=false;ow.player.px=56;s=world()
T.eq(count(s,'jpFxWater',7),1,'surf exit leaves one wet mark')
T.eq(count(s,'jpFxTracks'),0,'wet print replaces dry print without overlap')
opt.jpFxWater=false;ow.player.px=64;s=world()
T.eq(count(s,'jpFxTracks',7),1,'water OFF does not disable independent dry tracks')
T.eq(count(s,'jpFxWater'),0,'water OFF removes all wet marks and droplets')
opt.jpFxWater=true;map.wet=true;ow.player.surfing=true;world()
map.wet=false;ow.player.surfing=false;ow.player.px=256;s=world()
T.eq(s.wetUntil,nil,'teleport clears wet trail instead of inventing a shore exit')
ow.player.px=264;s=world();T.eq(count(s,'jpFxWater'),0,'no distant post-warp droplets')
off();opt.jpFxFootsteps=true;ow.dustAnim={};ow.player.px=272;s=world()
T.eq(count(s,'jpFxFootsteps'),0,'native running dust suppresses duplicate dust emitter')
ow.dustAnim=nil;ow.player.px=280;s=world();T.check(count(s,'jpFxFootsteps')>0,'normal walking still emits its dust')
off();opt.jpFxLightShafts=true;map.def.tileset='FOREST'
for _=1,50 do s=world()end
T.check(count(s,'jpFxLightShafts',9)>0,'daytime forest has sunbeams')
T.check(count(s,'jpFxLightShafts',9)<=3,'high density bounds forest beams to three')
T.eq(count(s,'jpFxAmbient'),0,'sunbeams do not invent another ambience emitter')
moon=true;s=world();T.eq(count(s,'jpFxLightShafts'),0,'night clears sunbeams immediately')
moon=false;opt.jpFxLightShafts=false;for _=1,20 do s=world()end
T.eq(count(s,'jpFxLightShafts'),0,'sunbeam OFF stays off')
local b={game=game,phase='messages',data={moves={EMBER={type='FIRE'},TACKLE={type='NORMAL'},EARTHQUAKE={type='GROUND'}}},
  player={mon={species='PIKACHU'}},enemy={mon={species='GASTLY'}}}
local arena={encounter=true,map=map,groundY=3,player={20,40},enemy={40,20}}
local function hit(name,crit)
  b.jpFxHitSerial=(b.jpFxHitSerial or 0)+1;b.jpFxHitTarget=b.enemy;b.jpFxHitMoveName=name;b.jpFxHitCritical=crit
  now=now+.02;return E.battle(arena,b)
end
off();opt.jpFxCritical=true;opt.jpFxAfterglow=true;opt.jpFxDensity='normal'
s=hit('EMBER',true);T.eq(count(s,'jpFxCritical',8),1,'actual critical hit emits one short accent')
T.eq(count(s,'jpFxAfterglow'),7,'fire hit leaves seven residual particles')
local old=E.stats.emitted;now=now+.02;E.battle(arena,b)
T.eq(E.stats.emitted,old,'unchanged hit serial never retriggers an effect')
E.finish(arena);s=hit('TACKLE',false)
T.eq(count(s,'jpFxCritical'),0,'normal hit has no critical accent')
T.eq(count(s,'jpFxAfterglow'),0,'normal hit does not duplicate contact dust')
off();opt.jpFxBattleEnvironment=true;E.finish(arena);s=hit('EARTHQUAKE',false)
T.eq(count(s,'jpFxBattleEnvironment',1),1,'heavy hit adds one ring to existing environment effect')
opt.jpFxBattleEnvironment=false;now=now+.02;s=E.battle(arena,b)
T.eq(#s.particles,0,'environment OFF clears stones and shock ring together')
off();opt.jpFxAfterglow=true;opt.jpFxCritical=true
for _,density in ipairs({'low','normal','high'})do
  opt.jpFxDensity=density;E.finish(arena);s=hit('EMBER',true)
  local n=count(s,'jpFxAfterglow');T.eq(n,({low=4,normal=7,high=11})[density],density..' scales residual count')
  for _=1,200 do s=hit('EMBER',true)end
  T.check(#s.particles<=({low=48,normal=96,high=128})[density],density..' respects particle budget')
end
opt.reduceMotion=true;s=hit('EMBER',true);T.eq(#s.particles,0,'reduce motion suppresses all new battle effects')
opt.reduceMotion=false;opt.animations=false;s=hit('EMBER',true)
T.eq(#s.particles,0,'native animation OFF suppresses new battle accents')
opt.animations=true
opt.jpFxAfterglow=false;opt.jpFxCritical=false;opt.jpFxTracks=false;opt.jpFxLightShafts=false
local restored=assert(Transfer.import(assert(Transfer.export(opt)),{}))
for _,key in ipairs({'jpFxAfterglow','jpFxCritical','jpFxTracks','jpFxLightShafts'})do T.eq(restored[key],false,key..' explicit OFF survives export/import')end
T.eq(restored.jpFxDensity,'high','density survives export/import')
T.eq(Save.mergeOptions({jpFxDensity='broken'}).jpFxDensity,'normal','invalid density becomes normal')
T.finish()
