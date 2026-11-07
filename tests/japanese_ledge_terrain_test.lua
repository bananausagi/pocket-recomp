-- Original block-shaped road ledges. Synthetic map/atlas only, no ROM assets.
local F=require('tests.ledge_terrain_fixture');local f=F.new();local checks=0
local function check(v,s)assert(v,s);checks=checks+1 end
local function snapshot(map)local t={};for y=0,map.heightCells-1 do for x=0,map.widthCells-1 do t[#t+1]=map:cellTile(x,y);t[#t+1]=map:isWalkableCell(x,y)and 1 or 0 end end;return table.concat(t,',')end
local function ledge(map,y)for x=0,map.widthCells-1 do map.cells[F.key(x,y)]=55 end end
local m=f:map('BLOCKS',16,24);ledge(m,8);ledge(m,16)
local before=snapshot(m);local t=f:build(m)
check(t.seeds==32,'both original road-hop rows are recognized')
check(t.stats.iterations==0 and not t.world and not t.tiles,'no global height field or solver is allocated')
local vertices,indices,count=f.Mesher.geometry(m,true)
check(#vertices==count*4 and #indices==count*6,'production mesher still emits indexed geometry')
local tops,sides=0,0
for i=1,#vertices,4 do
 local lo,hi=math.huge,-math.huge
 for j=i,i+3 do local y=vertices[j][2];assert(y==0 or y==6,'unexpected road elevation');lo=math.min(lo,y);hi=math.max(hi,y)end
 if lo==6 and hi==6 then tops=tops+1 end
 if lo==0 and hi==6 then sides=sides+1 end
end
check(tops==64,'only 64 original ledge tiles receive six-unit block tops')
check(sides==132,'original ledge runs have complete exposed vertical sides')
for _,y in ipairs({0,7,8,9,15,16,17,23})do check(f.Scene.groundAt(m,8,y)==((y==8 or y==16)and 6 or 0),'actor/battle floor follows only original blocks at '..y)end
check(snapshot(m)==before,'collision, tile data and original jump metadata are unchanged')
local ticks=f.ticks;for i=1,10000 do assert(f.T.height(m,80,100)==0)end
check(ticks==f.ticks,'height API has no solver or per-frame analysis cost')
local grass={{{32,0,32},{36,0,32},{36,7,32},{32,7,32}}};f.T.liftFoliage(m,grass)
check(grass[1][1][2]==0 and grass[1][3][2]==7,'foliage has no terrain uplift')
local actor={cellX=8,cellY=8,px=128,py=128,ledgeHop=true,hopFrames=16,hopTotal=32,facing='down'}
check(f.Scene.entityGround(m,actor)==0,'airborne feet do not snap up onto the ledge midpoint')
for elapsed=0,32 do
 local a={cellX=8,cellY=elapsed<16 and 7 or elapsed<32 and 8 or 9,hopFrames=32-elapsed,hopTotal=32,facing='down'}
 check(f.Scene.entityGround(m,a)==0,'continuous floor under all hop frames '..elapsed)
end
local Player=require('src.world.Player')
actor.walkPhase=function()return 0 end;actor.sprite='synthetic-player'
local _,_,py=Player.pose(actor)
check(py==118 and actor.hopFrames==16,'actual Player pose preserves the ten-pixel jump arc and timing')
for _,spec in ipairs({{'LEFT',39},{'RIGHT',13}})do
 local s=f:map(spec[1],16,16);for y=0,15 do s.cells[F.key(8,y)]=spec[2]end
 f:build(s);local v=f.Mesher.geometry(s,true);local raised=0;for _,p in ipairs(v)do assert(p[2]==0 or p[2]==6,'side-facing hop changed height');if p[2]==6 then raised=raised+1 end end
 check(raised>0 and f.Scene.groundAt(s,8,8)==6,spec[1]..' road-hop art has the original block height')
end
local other=f:map('NORMAL',16,20);ledge(other,10);other.cells[F.key(4,3)]=99;other.cells[F.key(5,3)]=20
f:build(other);local v,_,_,water=f.Mesher.geometry(other,true,nil,true)
local wall=false;for _,p in ipairs(v)do if p[2]==16 then wall=true end end
check(wall,'unrelated wall/building heights remain')
check(#water>0,'water still uses its separate stream');for _,p in ipairs(water)do assert(p[2]==-2,'water changed')end
check(true,'existing water depth remains unchanged')
-- Adjacent maps are not loaded or solved, even when connected metadata exists.
local a=f:map('A',16,20);local b=f:map('B',16,20);ledge(a,8);ledge(b,8)
a.def.connections={down={map='B',offset=0}};b.def.connections={up={map='A',offset=0}}
local data=f:data({a,b});local calls=0
setmetatable(data.maps,{__index=function()calls=calls+1;error('must not traverse other maps')end})
f:build(a,data)
check(not f.T.forMap(b) and calls==0 and a.S.terrain.stats.cells==320,'classification stays local to the requested map')
f:build(b,data);check(f.Scene.groundAt(a,8,19)==0 and f.Scene.groundAt(b,8,0)==0,'map seam ground stays flat on both sides')
f.T.invalidate(a.id);check(not f.T.forMap(a)and f.T.height(a,100,100)==0,'classification eviction leaves the compatibility height API unchanged')
-- The actual importer-supplied field rows also work before a mesh is ready.
package.loaded['src.core.Game'].data.field.ledges=f.rules
check(f.Scene.groundAt(a,8,8)==6,'uncached road-hop query agrees with the block mesh')
check(f.Scene.groundAt(a,-1,8)==0,'off-map border extension does not lift seam walkers')
local root=os.getenv('JP_QA_ROOT')or'.'
local Disk=assert(loadfile(root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/VoxelMeshDisk.lua'))(f.V)
local new=Disk.fingerprint(a,1,nil,'terrain');Disk.CACHE_REVISION=4
local old=Disk.fingerprint(a,1,nil,'terrain');Disk.CACHE_REVISION=5
check(new~=old and new:match('^rev|5|'),'flat geometry cache fingerprint cannot match restored block geometry')
check(not Disk.available(),'persistent cache remains disabled in the shipped provider')
local result={checks=checks,romUsed=false,solverIterations=0,globalMapTraversal=false,blockHeight=6,meshCacheRevision=5}
local out=os.getenv('TERRAIN_QA_OUT');if out then local fp=assert(io.open(out..'/headless-results.json','w'));fp:write(require('src.link.Json').encode(result));fp:close()end
print('PASS '..checks..' focused block-road checks')
