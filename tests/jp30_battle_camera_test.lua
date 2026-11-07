package.path='./?.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('jp30 battle camera timing and mode boundaries')
local now=100;love.timer={getTime=function()return now end}
local V,modules={},{}
function V.require(n)if not modules[n]then modules[n]=assert(loadfile('vendor/jp-mods/DRAMALESS_SHAPE/lib/'..n..'.lua'))(V)end;return modules[n]end
local A=V.require('BattleActionCamera')
local function fresh()
 local b={phase='menu',kind='wild',player={},enemy={},data={moves={TACKLE={}}},game={save={options={animations=true}}}}
 return {encounter=true},b
end
local reference
for _,fps in ipairs({20,30,60,120})do for _,speed in ipairs({1,4})do
 local a,b=fresh();A.update(a,b)
 for _=1,fps*2 do now=now+1/fps;for _=1,speed do A.update(a,b)end end
 T.check(a.actionCamera and math.abs(a.actionCamera.time-2)<1e-8,'resting orbit follows physical time at '..fps..'fps '..speed..'x')
 T.eq(a.actionCamera.weight,1,'normal command choice enables camera')
 local time=a.actionCamera.time;now=now+60;A.update(a,b)
 T.eq(a.actionCamera.time,time,'app pause never jumps orbit ahead')
 b.phase='messages';b.animPlaying=true;b.animName='TACKLE';b.animAttackerIsPlayer=true
 for _=1,fps do now=now+1/fps;for _=1,speed do A.update(a,b)end end
 T.check(a.actionCamera.aim<-.9 and a.actionCamera.kind=='attack','attention selects the actual recipient')
 if reference then T.check(math.abs(a.actionCamera.aim-reference)<.002,'attention smoothing is frame-rate independent')else reference=a.actionCamera.aim end
 b.animPlaying=false;b.fx={blink={target=b.enemy,frames=30}}
 for _=1,fps*2 do now=now+1/fps;for _=1,speed do A.update(a,b)end end
 T.check(a.actionCamera.aim<-.98 and a.actionCamera.kind=='hit','damage attention changes to actual target')
 local same=a.actionCamera;b.fx=nil;b.phase='moveSelect';now=now+.01;A.update(a,b)
 T.eq(a.actionCamera,same,'move list does not reset orbit')
end end
do
 local a,b=fresh();b.phase='messages';b.animPlaying=true;b.animName='TACKLE';b.animAttackerIsPlayer=false
 A.update(a,b)
 for _=1,120 do now=now+1/60;A.update(a,b)end
 T.check(a.actionCamera.aim>.98,'enemy turn follows the player recipient')
 b.animPlaying=false;b.fx={blink={target=b.player,frames=30}}
 for _=1,120 do now=now+1/60;A.update(a,b)end
 T.check(a.actionCamera.aim>.98,'enemy hit shifts focus back to the player target')
end
-- Use the real native effect registry, including non-damaging opponent moves.
-- A blanket reversal of the attacker would get self-status moves wrong.
do
 local Battle=require('src.battle.BattleState')
 local _,b=fresh();setmetatable(b,Battle)
 b.data.moves={
  RECOVER={power=0,effect='HEAL_EFFECT'},
  REFLECT={power=0,effect='REFLECT_EFFECT'},
  HYPNOSIS={power=0,effect='SLEEP_EFFECT'},
  TACKLE={power=35,effect='NO_ADDITIONAL_EFFECT'},
 }
 for _,isPlayer in ipairs({true,false})do
  local actor=isPlayer and b.player or b.enemy
  local recipient=isPlayer and b.enemy or b.player
  T.eq(b:cameraMoveTarget('RECOVER',isPlayer),actor,'recovery follows its own side')
  T.eq(b:cameraMoveTarget('REFLECT',isPlayer),actor,'self protection follows its own side')
  T.eq(b:cameraMoveTarget('HYPNOSIS',isPlayer),recipient,'non-damaging status follows the opponent')
  T.eq(b:cameraMoveTarget('TACKLE',isPlayer),recipient,'damage follows the opponent')
 end
 T.eq(b:cameraMoveTarget('UNKNOWN',true),nil,'unknown animation does not invent a move target')
end
for _,field in ipairs({'showPlayerBack','showEnemyTrainer','introBalls','sendingOut','enemySendingOut','fieldCleared','demo','safari','waitingUI','growIn','shrinkOut','enemyHidden'})do
 local a,b=fresh();b[field]=true;A.update(a,b);T.eq(a.actionCamera,nil,field..' leaves native shot still')
end
for _,option in ipairs({'jpBattleCameraMotion','reduceMotion','jpReduceMotion','animations'})do
 local a,b=fresh();b.game.save.options[option]=option=='reduceMotion' or option=='jpReduceMotion';A.update(a,b)
 T.eq(a.actionCamera,nil,option..' suppresses motion')
end
for _,intro in ipairs({'original','focus'})do
 local a,b=fresh();b.game.save.options.jpBattleIntro=intro;A.update(a,b)
 T.check(a.actionCamera~=nil,'mid-battle toggle is independent from '..intro..' opening setting')
end
for _,side in ipairs({'player','enemy'})do
 local a,b=fresh();b[side].fainted=true;A.update(a,b);T.eq(a.actionCamera,nil,side..' faint stays still')
 local a,b=fresh();b.picFx={[b[side]]={kind='bounce'}};A.update(a,b);T.eq(a.actionCamera,nil,side..' high jump does not add orbit crop')
end
do
 local a,b=fresh();b.phase='messages';b.animPlaying=true;b.animName='TOSS_ANIM';A.update(a,b)
 T.eq(a.actionCamera,nil,'capture animation has canonical camera')
 b.animPlaying=false;A.update(a,b);T.eq(a.actionCamera,nil,'capture queue gap stays fixed')
 b.phase='menu';A.update(a,b);T.check(a.actionCamera~=nil,'command resumes camera after capture chain')
 b.phase='messages';A.update(a,b);T.check(a.actionCamera~=nil,'stale capture name cannot reset next attack announcement')
end
do
 local a,b=fresh();a.backgroundOnly=true;A.update(a,b);T.eq(a.actionCamera,nil,'fallback native backgrounds remain fixed')
 a.jpMetrics={sceneLens={zoom=1}};A.finish(a);T.eq(a.jpMetrics.sceneLens,nil,'finish clears effect anchors')
 package.loaded['src.render.Renderer']={jpBattleSceneLens={}}
 local c={eye={0,1,2},focus={0,0,0},fov=.8}
 T.eq(A.pose({},c,{}),c,'no active motion returns exact canonical object')
 T.eq(package.loaded['src.render.Renderer'].jpBattleSceneLens,nil,'inactive draw clears previous frame anchors')
end
T.finish()
