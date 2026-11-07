-- Map graph, scheduling ownership and bounded prefetch contracts. Real
-- VoxelPrecache, explicit doubles only for GPU/engine side effects.
local root=os.getenv('JP_QA_ROOT') or '.'
package.path=root..'/?.lua;'..package.path
local n=0
local function check(ok,why)assert(ok,why);n=n+1;print('PASS '..why)end
local definitions={}
for _,id in ipairs({'ROOT','N','S','W','E','A','B','C'})do
  definitions[id]={id=id,width=20,height=20,connections={},warps={}}
end
for i=1,12 do definitions['NEXT'..i]={id='NEXT'..i,width=6,height=6} end
definitions.ROOT.connections={north={map='N',offset=10},south={map='S',offset=0},west={map='W',offset=0},east={map='E',offset=0}}
definitions.N.width=8
definitions.ROOT.warps={{x=5,y=1,destMap='A'},{x=6,y=1,destMap='B'},{x=7,y=1,destMap='C'}}
local data={maps=definitions,constants={world={neighborHops=3}}}
local cached,loads,requests,atlasCalls,retained,nearby,cancels={},{},{},{},{},{},{}
local atlasReady={ROOT=true}
local loader={}
function loader.load(_,id)
  loads[#loads+1]=id;cached[id]=cached[id] or {id=id,def=definitions[id]};return cached[id]
end
function loader.cached(id)return cached[id]end
function loader.trim(keep)check(keep.ROOT,'native cache trimming protects current world')end
local mesh={peek=function(map)return map.id=='ROOT' end,slotKnown=function()return false end,
  request=function(map,body,masks,urgent,priority,predictive)
    requests[#requests+1]={id=map.id,body=body,masks=masks,urgent=urgent,priority=priority,predictive=predictive}
  end,setPredictive=function(live)retained=live end,setApproaching=function(v)nearby=v end,
  cancelPending=function(id,body)cancels[#cancels+1]={id=id,body=body}end}
local scene={atlasReady=function(map)return atlasReady[map.id] end,
  warmAtlas=function(map,seconds)atlasCalls[#atlasCalls+1]={id=map.id,seconds=seconds};return false end,
  cancelWarmAtlas=function(map)cancels[#cancels+1]={id=map.id,atlas=true}end}
local graphReads={}
package.loaded['src.render.Assets']={register=function()end}
package.loaded['src.world.MapLoader']=loader
package.loaded['src.world.Warp']={destination=function(_,w)return w.destMap end}
package.loaded['src.world.OverworldController']={computeNeighbors=function(_,id,hops,w,h)
  graphReads[#graphReads+1]={hops=hops,w=w,h=h}
  if id~='N' then return {}end
  local result={};for i=1,12 do result[i]={id='NEXT'..i,ox=i*32,oy=-200}end;return result
end}
local modules={ChunkMesher=mesh,VoxelScene=scene,TerrainAtlas={setPredictive=function()end}}
local P=assert(loadfile(root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/VoxelPrecache.lua'))({require=function(id)return assert(modules[id],id)end})
local current=loader.load(data,'ROOT')
local ow={map=current,player={targetX=5,targetY=1},neighbors={},neighborViewW=480,neighborViewH=320}
for _,id in ipairs({'N','S','W','E'}) do ow.neighbors[#ow.neighbors+1]={map=loader.load(data,id),ox=0,oy=0}end
local game={overworld=ow,data=data};loads={}
local rows=P.candidates(data,ow);local north
for _,row in ipairs(rows)do if row.id=='N' then north=row end end
check(north.distance==226,'north priority includes lateral distance to offset boundary segment')
P.update(game)
check(retained.N and retained.S and retained.E and retained.W,'four connections retain their own allocation beside nearby doors')
check(retained.A and retained.B and not retained.C,'only two nearest doors retain speculative ownership')
local bodies,full=0,0
for _,r in ipairs(requests)do if r.id=='N' or r.id=='S' or r.id=='W' or r.id=='E' then
  if r.body then bodies=bodies+1 else full=full+1 end
end end
check(bodies==2 and full==2,'all four adjacent maps queued but only nearest two build decorative rings')
check(#loads==1,'already loaded connected maps do not consume new-map allowance')
check(#atlasCalls==1 and atlasCalls[1].seconds==.001,'all predictions share one atlas slice per update')
check(atlasCalls[1].id=='W','nearest adjacent atlas starts before any geometry settles')
check(nearby.W==25*256 and nearby.N==226*256 and not nearby.S,'only actually approached edges receive queue hints')
for _,r in ipairs(graphReads)do check(r.hops==3 and r.w==304 and r.h==224,'prediction uses native hop and zoom reach values')end
-- Approach the shifted north opening: doors keep their slots; future view is
-- capped even when a third-party graph offers many more maps.
ow.player.targetX,ow.player.targetY=22,1
atlasReady.W=true;requests={};P.update(game)
local count=0;for id in pairs(retained)do if id:match('NEXT') then count=count+1 end end
check(count==6,'at most six additional bodies from one upcoming neighbourhood retained')
check(nearby.N==256,'inside north strip has only perpendicular distance')
for _=1,8 do
  local a,b=#loads,#atlasCalls;P.update(game)
  check(#loads-a<=1 and #atlasCalls-b<=1,'future neighbourhood never multiplies per-frame map or atlas work')
end
local aheadBody=true
for _,r in ipairs(requests)do if r.id:match('NEXT') and not r.body then aheadBody=false end end
check(aheadBody,'extra neighbourhood builds bodies without additional outer rings')
local countBefore=#loads;ow.player.targetY=2;P.update(game)
check(#loads==countBefore,'approach updates reuse cached maps and partial work')
-- A different SGB/display palette invalidates atlas readiness without needing
-- a geometry rebuild or another step to trigger the change.
atlasReady.N=true;P.update(game)
atlasReady.N=false;local before=#atlasCalls;P.update(game)
check(#atlasCalls==before+1 and atlasCalls[#atlasCalls].id=='N','same-cell palette change resumes correct adjacent atlas')
ow.player.targetX,ow.player.targetY=1,38;P.update(game)
check(not retained.NEXT1 and not nearby.N and nearby.S,'reversal releases future-only maps and switches approach hints')
P.reset()
check(next(retained)==nil and next(nearby)==nil,'reset clears retained speculative maps and all approach hints')
print('PASS '..n..' jp41 adjacent scheduler checks')
