-- Predictive scheduler contract, independent of a ROM or graphics driver.
local root=os.getenv('JP_QA_ROOT') or '.'
package.path=root..'/?.lua;'..package.path
local n=0
local function check(ok,label)assert(ok,label);n=n+1;print('PASS '..label)end
local requests,atlases,cancelled,retained,loads={},{},{},{},{}
local callbacks={}
package.loaded['src.render.Assets']={register=function(fn)callbacks[#callbacks+1]=fn end}
package.loaded['src.world.Warp']={destination=function(_,warp,last)return warp.destMap=='LAST_MAP' and last.id or warp.destMap end}
package.loaded['src.world.OverworldController']={computeNeighbors=function()return {}end}
local data={maps={}}
for _,id in ipairs({'ROOT','NORTH','SOUTH','EAST','OTHER'})do data.maps[id]={id=id,width=30,height=30}end
data.maps.ROOT.warps={{x=1,y=1,destMap='NORTH'},{x=58,y=58,destMap='SOUTH'},{x=58,y=1,destMap='EAST'},
  {x=50,y=50,destMap='NORTH'}}
local maps={}
package.loaded['src.world.MapLoader']={load=function(d,id)
  loads[id]=(loads[id] or 0)+1
  maps[id]=maps[id] or {id=id,def=d.maps[id]};return maps[id]
end}
local ready={ROOT=true};local stale={}
local mesh={
  setPredictive=function(live)retained=live end,
  peek=function(map)return ready[map.id] end,
  pending=function()return 999 end,
  slotKnown=function(map)return ready[map.id] and not stale[map.id] end,
  request=function(map,body,masks,urgent,priority,predictive)
    requests[#requests+1]={id=map.id,priority=priority,predictive=predictive,body=body}
  end,
}
local scene={warmAtlas=function(map,seconds)
  atlases[#atlases+1]={id=map.id,seconds=seconds}
  return #atlases>=4
end,cancelWarmAtlas=function(map)cancelled[#cancelled+1]=map.id end}
local modules={ChunkMesher=mesh,VoxelScene=scene,TerrainAtlas={setPredictive=function()end}}
local P=assert(loadfile(root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/VoxelPrecache.lua'))({require=function(id)return assert(modules[id],id)end})
local loader=package.loaded['src.world.MapLoader']
local current=loader.load(data,'ROOT')
local game={data=data,overworld={map=current,player={targetX=1,targetY=1},lastOutdoor={id='OTHER',x=2,y=2}}}
P.update(game)
check(#requests==1 and requests[1].id=='NORTH','near prediction starts despite distant pending queue')
check(requests[1].predictive==true and requests[1].priority==0,'prediction uses comparable pixel-distance priority')
check(loads.NORTH==1 and not loads.EAST,'at most one map loads per update')
P.update(game)
check(loads.EAST==1 and retained.NORTH and retained.EAST and not retained.SOUTH,'only two closest distinct exits retained')
ready.NORTH=true
P.update(game)
check(#atlases==1 and atlases[1].seconds==.001,'warm atlas uses one millisecond preparation interface')
P.update(game)
check(#atlases==2,'partial atlas resumes once per update')
-- Cross while atlas remains unfinished. It must transfer, never cancel and
-- rebuild synchronously in the first live render.
local north=maps.NORTH;game.overworld.map=north
P.update(game)
local cancelledNorth=false;for _,id in ipairs(cancelled)do if id=='NORTH' then cancelledNorth=true end end
check(not cancelledNorth and #atlases==3,'crossing transfers unfinished destination atlas without cancellation')
P.update(game)
check(#atlases==4,'transferred arrival atlas finishes in later update')
-- Return and reverse direction; the nearest pair changes without a root change.
game.overworld.map=current;P.update(game);P.update(game)
game.overworld.player.targetX=58;game.overworld.player.targetY=58
P.update(game)
check(retained.SOUTH and retained.NORTH and not retained.EAST,'player target reranks exits before map changes')
local last=requests[#requests]
check(last.id=='NORTH' or last.id=='SOUTH','reranked request belongs to new near pair')
local rows=P.candidates(data,game.overworld)
check(rows[2].id=='NORTH' and rows[2].distance==128,'duplicate warp uses nearest door rather than first declaration')
-- LAST_MAP resolves through authoritative Warp helper.
data.maps.ROOT.warps={{x=58,y=58,destMap='LAST_MAP'}}
local resolved=P.candidates(data,game.overworld)
check(#resolved==1 and resolved[1].id=='OTHER','LAST_MAP prediction uses actual last outdoor destination')
-- Same map id with new object/data must reset (restore/asset reload).
local replacement={id='ROOT',def=data.maps.ROOT};game.overworld.map=replacement
P.update(game)
check(retained.OTHER and not retained.SOUTH,'new current-map instance replans after restore')
check(#callbacks==1,'asset invalidation owns prediction reset')
callbacks[1]()
local done,total,active,id=P.progress()
check(total==0 and id==nil and next(retained)==nil,'asset reset clears speculative ownership')
print('PASS '..n..' predictive precache checks')
