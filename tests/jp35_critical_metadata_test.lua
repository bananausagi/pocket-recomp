-- Exercise the real move queue: critical metadata must not change hit sounds,
-- number of hits, or leak the first strike's accent into later strikes.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Data=T.fixtures.fresh()
require('src.render.Font').load(Data);require('src.battle.TypeChart').load(Data)
local Battle=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local Sound=require('src.core.Sound')
local played={};Sound.playMove=function(_,s)played[#played+1]=s end
Data.moves.FIX_DOUBLE={id='FIX_DOUBLE',index=99,name='DOUBLE',type='NORMAL',power=10,
  accuracy=100,pp=20,effect='ATTACK_TWICE_EFFECT'}
for _,crit in ipairs({false,true})do for _,mult in ipairs({5,10,20})do
  local save=Save.newGame();save.party={Pokemon.new(Data,'FIXMON_A',20)}
  local game={data=Data,save=save,stack={push=function()end,top=function()end}}
  local b=Battle.newWild(game,'FIXMON_C',20);b.queue={};b.nextInsert=0
  b.rng=function(a)return a end;b.computeDamage=function()return 1,{crit=crit,typeMult=mult}end
  b:performMove(b.player,b.enemy,{id='FIX_DOUBLE',pp=10},false)
  local hits={};for _,row in ipairs(b.queue)do if row.hit then hits[#hits+1]=row.hit end end
  T.eq(#hits,2,'multi-hit still queues exactly two applying attacks')
  T.eq(hits[1].crit,crit,'first strike reflects actual critical result')
  T.eq(hits[2].crit,false,'second strike has no duplicate critical accent')
  T.check(hits[1]~=hits[2],'each strike owns its presentation metadata')
  played={}
  for _,hit in ipairs(hits)do
    b:applyHitFx(hit)
    T.eq(b.jpFxHitMoveName,'FIX_DOUBLE','landed event identifies actual move')
    T.eq(b.jpFxHitCritical,hit.crit,'landed event carries correct critical flag')
    T.eq(hit.sfx.sound,({[5]='Not_Very_Effective',[10]='Damage',[20]='Super_Effective'})[mult],'audio depends only on type effectiveness')
  end
  T.eq(#played,2,'critical adds no extra sound')
end end
T.finish('jp35 critical metadata and native audio')
