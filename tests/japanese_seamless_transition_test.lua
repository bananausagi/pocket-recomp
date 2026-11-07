-- Presentation lifetime and failure boundary: real Host/Transition/Blend with
-- deliberately failing providers. GL success/pixel continuity is tested separately.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Seamless encounter ownership')
local modId=os.getenv('JP_QA_RENDERER') or 'DRAMALESS_SHAPE'
local pipeline='voxel'
package.loaded['src.render.Pipelines']={worldPipeline=function()return pipeline end}
local hookStyle
package.loaded['src.mods.Runtime']={call=function(_,default,ctx)return hookStyle or default(ctx)end}
local Cast,draws=0,0
local V={log={event=function()end,error=function()end},require=function(id)
 if id=='VoxelState' then return {active=function()return true end}end
 if id=='VoxelScene' then return {captureEncounterCast=function()Cast=Cast+1;return function()draws=draws+1 end end}end
 if id=='WildEncounterMotion' then return assert(loadfile('vendor/jp-mods/'..modId..'/lib/WildEncounterMotion.lua'))()end
 error(id)
end}
local Host=assert(loadfile('vendor/jp-mods/'..modId..'/lib/VoxelBattleStandalone.lua'))(V)
local Transition=require('src.render.BattleTransition')
local calls={}
local fail
local arenaProvider={
 arena=function()calls.search=(calls.search or 0)+1;return {encounter=true,entryPose={eye={0,1,2}},presentationTime=0}end,
 begin=function(_,ctx)ctx.battle.jpSeamlessCamera=true;return true end,
 update=function(_,ctx,dt)if fail=='update' then error('injected update')end;ctx.arena.presentationTime=ctx.arena.presentationTime+dt end,
 render=function(_,ctx,arena,actors)calls.render=(calls.render or 0)+1;if fail=='render' then error('injected render')end;actors({width=160,height=144});if fail=='surface' then return 'FALLBACK' end;return {getWidth=function()return 160 end,getHeight=function()return 144 end}end,
 finish=function(_,ctx,reason)calls.reason=reason end,
}
local cards={begin=function()calls.cards=(calls.cards or 0)+1;return fail~='cards'end,
 update=function()calls.cardUpdates=(calls.cardUpdates or 0)+1 end,
 drawWorld=function()calls.cardDraws=(calls.cardDraws or 0)+1 end,
 finish=function()end}
local game={renderer={setWorldOverride=function()end},data={constants={language='ja'}},overworld={}}
local battle={game=game,kind='wild'}
game.mods={exports={[modId]={prepareBattleTransition=function(b)return Host.prepare(b,arenaProvider,cards)end}}}
local transition,entered
local function make()
 calls={};fail=nil;entered=0
 transition=Transition.new(game,function()entered=entered+1;Host.begin(battle,arenaProvider,cards)end,{battle=battle})
 game.stack={pop=function()transition:exit()end}
 return transition
end
make()
T.check(transition.seamless~=nil,'render-tested provider owns transition')
T.check(transition.isOpaque and transition.isBattleState,'one visible scene owns presentation layout')
T.eq(calls.cards,nil,'preparation never begins battle cards')
T.eq(calls.render,1,'initial trial renders exactly once')
T.eq(transition.seamless.time(),0,'trial render never advances clock')
local initial=Host.session.context.arena
for i=1,233 do Host.update(1/60);transition:update(1/60)end
T.eq(entered,0,'no early battle enter during camera orbit')
T.eq(calls.cardUpdates,nil,'no battle-card update during preparation')
T.eq(calls.search,1,'same arena search shared by preview')
Host.update(1/60);transition:update(1/60)
T.eq(entered,1,'handoff enters the battle once near the end of the orbit')
T.eq(calls.cards,1,'cards initialize only at actual enter')
T.check(Host.session.context.arena==initial,'handoff retains exact encounter and clock')
T.eq(calls.search,1,'handoff does not re-search or move the arena')
T.eq(battle.jpEncounterIntroCredit,72,'music cue credits the complete visual intro')
T.check(battle.jpEncounterAwaitDraw,'fast logic must wait for the first physical reveal frame')
Host.draw(battle)
T.eq(battle.jpEncounterAwaitDraw,nil,'the first battle draw releases the original cry queue')
for i=1,100 do transition:update(1/60)end
T.eq(entered,1,'repeated fast updates cannot replay handoff or battle events')
T.check(not Host.session.prepared,'normal card ownership starts after handoff')
battle.jpEncounterCleanup(true)
T.eq(calls.reason,'battle.ended','normal completion releases with return-camera reason')
T.check(battle.jpSeamlessCamera,'normal finish retains fade suppression until return is built')
T.eq(Host.session,nil,'normal finish releases host')
make();transition:exit()
for i=1,600 do transition:update(1/60)end
T.eq(entered,0,'interrupted transition cannot later replay battle entry')
T.eq(calls.reason,'preview-aborted','stack clear cancels preview rather than starting return camera')
T.eq(Host.session,nil,'aborted preview releases host')
T.eq(battle.jpSeamlessCamera,nil,'aborted preview clears fade flags')
make();fail='update';Host.update(1/60);transition:update(1/60)
T.eq(transition.seamless,nil,'update failure restores legacy transition')
T.check(not transition.isOpaque,'failure restores overworld draw ownership')
T.eq(entered,0,'failure never starts battle early')
make();fail='render';transition:draw();transition:update(1/60)
T.eq(transition.seamless,nil,'late render failure restores legacy transition')
T.eq(Host.session,nil,'late render failure releases preview')
fail='render'
local declined=Host.prepare(battle,arenaProvider,cards)
T.eq(declined,nil,'first render failure never enables seamless')
T.eq(Host.session,nil,'failed trial does not leak a host session')
T.eq(battle.jpSeamlessCamera,nil,'failed trial clears arena begin flags')
fail='surface'
T.eq(Host.prepare(battle,arenaProvider,cards),nil,'provider sentinel cannot count as a rendered canvas')
T.eq(Host.session,nil,'invalid surface clears preview ownership')
fail=nil;pipeline=nil
T.eq(Host.prepare(battle,arenaProvider,cards),nil,'2D world never silently enables voxel transition')
pipeline='voxel';game.data.constants.language='en'
T.eq(Host.prepare(battle,arenaProvider,cards),nil,'non-JP path retains its existing transition')
game.data.constants.language='ja'
battle.kind='trainer'
T.eq(Host.prepare(battle,arenaProvider,cards),nil,'trainer provider refuses seamless even if called directly')
transition=Transition.new(game,function()end,{battle=battle,trainer=true})
T.eq(transition.seamless,nil,'trainer keeps original wipe and black hold')
T.eq(transition.style,'spiralin','ordinary trainer keeps authentic inward spiral')
battle.kind='wild'
hookStyle='split';transition=Transition.new(game,function()end,{battle=battle})
T.eq(transition.seamless,nil,'custom transition selection keeps ownership')
hookStyle=nil
transition=Transition.new(game,function()end,{})
T.eq(transition.seamless,nil,'callers without a battle retain legacy wipe')
make();fail='cards';for i=1,235 do Host.update(1/60);transition:update(1/60)end
T.eq(Host.session,nil,'late card initialization failure releases prepared session')
T.eq(battle.jpSeamlessCamera,nil,'late card failure cannot suppress native return fade')
local Blend=assert(loadfile('vendor/jp-mods/'..modId..'/lib/BattleCameraBlend.lua'))()
local a={eye={0,80,90},focus={2,4,5},up={0,1,0},fov=.8,filmX=.2,filmY=-.1,curve=.001,curveX=100,curveZ=200}
local b={eye={40,16,67},focus={-2,3,0},up={0,1,0},fov=.349,filmX=-.1,filmY=.3,curve=.002,curveX=120,curveZ=250}
for _,t in ipairs({0,1})do
 local p=Blend.encounter(a,b,t);local want=t==0 and a or b
 for _,key in ipairs({'fov','filmX','filmY','curve','curveX','curveZ'})do T.eq(p[key],want[key],'endpoint preserves '..key)end
 for i=1,3 do T.eq(p.eye[i],want.eye[i],'endpoint preserves eye');T.eq(p.focus[i],want.focus[i],'endpoint preserves focus')end
end
local pulse=Blend.encounter(a,b,.07)
T.check(pulse.fov<a.fov and pulse.eye[1]==a.eye[1],'brief zoom cue precedes orbit')
for i=1,59 do
 local p=Blend.encounter(a,b,i/60)
 T.check(p.fov>0 and p.eye[1]==p.eye[1] and p.focus[2]==p.focus[2],'orbit stays finite at frame '..i)
end
T.eq(a.eye[1],0,'source pose remains untouched')
T.eq(b.eye[1],40,'target pose remains untouched')
T.finish()
