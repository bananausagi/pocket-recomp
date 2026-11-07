local root=os.getenv('JP_QA_ROOT') or '.'
package.path=root..'/?.lua;'..package.path
local path=root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/'
local n=0
local function check(ok,why)assert(ok,why);n=n+1;print('PASS '..why)end
love={timer={getTime=function()return 100 end}}
package.loaded['src.render.Assets']={register=function()end}
package.loaded['src.render.PackedVoxelMesh']={available=function()return false end}
local begun,visited,slices={},{},{}
local shape={grassQuads={},flowerQuads={},figures={},shapeAt={},tileAt={},runs={},objectQuads={},roundStamps={}}
local modules={
 Structures={forMap=function(map)
  if not visited[map.id] then visited[map.id]=true;begun[#begun+1]=map.id;coroutine.yield('fixture')end
  return shape
 end,invalidate=function()end},TileShape={},
 Voxel3D={newMesh=function()return {release=function()end,getVertexCount=function()return 0 end}end},
 BuildBudget={begin=function(_,seconds)slices[#slices+1]=seconds end,finish=function()end,tick=function()end,check=function()end},
 VoxelMeshDisk={available=function()return false end,invalidate=function()end},
 MeshParts=assert(loadfile(path..'MeshParts.lua'))(),TreeInstances={available=function()return false end}}
local M=assert(loadfile(path..'ChunkMesher.lua'))({require=function(id)return assert(modules[id],id)end})
local function map(id)return {id=id,def={width=0,height=0,borderBlock=false},tileset={tilesPerRow=16},tileAt=function()return nil end}end
local current,near,far,destination=map('CURRENT'),map('NEAR'),map('FAR'),map('DESTINATION')
M.request(current,true,nil,true);M.request(near,true,nil,false,256);M.setApproaching({NEAR=256})
M.pump(false);check(begun[1]=='CURRENT','cold current map precedes nearby prediction')
M.cancelPending(near.id,true)
M.pump(false);check(M.slotKnown(current,true),'current body publishes and remains drawable')
M.request(current,false,{},true);M.request(far,true,nil,false,1);M.request(near,true,nil,false,256);M.pump(false)
check(begun[2]=='NEAR','nearby body receives time before decorative current ring')
check(math.abs(slices[#slices]-.002)<1e-8,'nearby body retains ordinary 2 ms slice')
M.request(destination,true,nil,true,0,true);M.pump(false)
check(begun[#begun]=='DESTINATION','confirmed cold destination preempts already running neighbor')
M.setApproaching({});M.pump(false)
check(M.slotKnown(destination,true),'cold destination finishes without rebuilding visible current body')
local before=#begun
for _=1,10 do if M.pending()==0 then break end;M.pump(false)end
check(M.pending()==0 and #begun==before,'reversing priority resumes partial jobs instead of restarting them')
check(M.slotKnown(near,true) and M.slotKnown(far,true),'both adjacent and background geometry finish')
print('PASS '..n..' jp41 actual queue priority checks')
