-- Connected-map visibility and cooperative request ordering, synthetic data.
local root=os.getenv('JP_QA_ROOT') or '.'
package.path=root..'/?.lua;'..package.path
local path=root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/'
local checks=0
local function check(ok,why)assert(ok,why);checks=checks+1;print('PASS '..why)end
local Visibility=assert(loadfile(path..'NeighborVisibility.lua'))()
local function neighbor(id,ox,oy,w,h)
  return {map={id=id,def={width=w,height=h},tileset={tilesPerRow=16}},ox=ox,oy=oy}
end
local radius=64*2*8 -- production FAR=128 tiles, each tile8px
local north=neighbor('NORTH',-320,-2048,40,64)
local west=neighbor('WEST',-2048,-320,64,40)
local south=neighbor('SOUTH',-320,320,40,64)
local east=neighbor('EAST',320,-320,64,40)
local defs={north,west,south,east}
local player={px=160,py=160}
for _,nb in ipairs(defs)do
  check(Visibility.contains(nb,player,radius),nb.map.id..' nearby edge visible at FAR despite remote origin')
end
check((north.ox-player.px)^2+(north.oy-player.py)^2>radius^2,'north route reproduces previous origin-culling failure')
check((west.ox-player.px)^2+(west.oy-player.py)^2>radius^2,'west route reproduces previous origin-culling failure')
for _,dir in ipairs({'north','west','south','east'})do
  local nb=({north=north,west=west,south=south,east=east})[dir]
  local outside=dir=='north' and {px=160,py=1100}
    or dir=='west' and {px=1100,py=160}
    or dir=='south' and {px=160,py=-800} or {px=-800,py=160}
  check(not Visibility.contains(nb,outside,radius),dir..' remains culled beyond FAR range')
  check(Visibility.contains(nb,{cellX=10,cellY=10},radius),dir..' cell-position fallback uses world-pixel units')
end
check(Visibility.contains(north,{px=160,py=1024},radius),'closest edge at exact FAR boundary remains visible')
check(not Visibility.contains(north,{px=160,py=1025},radius),'one pixel beyond FAR remains culled')
check(Visibility.distanceSquared(north,{px=160,py=-1000})==0,'standing inside a neighbor bound has zero distance')
check(Visibility.contains(south,{px=160,py=300},radius),'approach outgoing south seam visible')
local departed=neighbor('DEPARTED',0,-320,10,10)
check(Visibility.contains(departed,{px=160,py=16},radius),'after seam crossing departed map remains visible looking backward')
local copy={};for i,n in ipairs(defs)do copy[i]=n.ox..','..n.oy..','..n.map.def.width..','..n.map.def.height end
for i,n in ipairs(defs)do check(copy[i]==n.ox..','..n.oy..','..n.map.def.width..','..n.map.def.height,'visibility does not modify map connections/dimensions '..n.map.id)end

-- Actual exported terrain draw dispatch: all neighbours use their own atlas.
local mods={}
local V={require=function(name)mods[name]=mods[name] or {};return mods[name]end}
mods.Mat4={identity=function()return {}end,translate=function(x,y,z)return {x,y,z}end}
package.loaded['src.render.Assets']={register=function()end}
local V3=assert(loadfile(path..'Voxel3D.lua'))(V)
local calls,atlasReads={},{}
V3.draw=function(mesh,atlas,model)calls[#calls+1]={mesh=mesh,atlas=atlas,model=model}end
local function cull(point,nb)
  check(point.px==nb.ox and point.py==nb.oy,'legacy callback point remains compatible '..nb.map.id)
  return Visibility.contains(nb,player,radius)
end
local meshes={'north-mesh','west-mesh','south-mesh','east-mesh'}
V3.draw3DTerrain('root-mesh','root-atlas',defs,meshes,cull,function(map)
  atlasReads[#atlasReads+1]=map.id;return map.id..'-atlas'
end)
check(#calls==5 and #atlasReads==4,'current mesh and all four edge-neighbors dispatch')
for i,nb in ipairs(defs)do
  check(calls[i+1].atlas==nb.map.id..'-atlas','terrain samples its own connected map palette '..nb.map.id)
  check(calls[i+1].model[1]==nb.ox and calls[i+1].model[3]==nb.oy,'terrain connection translation unchanged '..nb.map.id)
end
calls={};atlasReads={}
V3.draw3DTerrain('root-mesh','root-atlas',{north},{},cull,function()error('uncached mesh must not build texture')end)
check(#calls==1,'uncached neighbor does not synchronously create atlas while mesh is pending')

-- Real queue with deliberately yielding builds: approach reprioritizes an
-- already-running far job without restarting it or raising neighbour budget.
local started,finished,slices,built={},{},{},{}
local lastMap
local function analysis(map)
  if not built[map.id] then
    built[map.id]=true;started[#started+1]=map.id;coroutine.yield('cooperative-slice')
    finished[#finished+1]=map.id
  end
  lastMap=map.id
  return {grassQuads={},flowerQuads={},figures={},shapeAt={},tileAt={},runs={},objectQuads={},roundStamps={}}
end
love={timer={getTime=function()return 100 end}}
local meshmods={
  Structures={forMap=analysis,invalidate=function()end},
  TileShape={},Voxel3D={newMesh=function()return {id=lastMap}end},
  BuildBudget={begin=function(_,seconds)slices[#slices+1]=seconds end,finish=function()end,tick=function()end,check=function()end},
  VoxelMeshDisk={available=function()return false end,invalidate=function()end},
}
package.loaded['src.render.PackedVoxelMesh']={available=function()return false end}
local Mesh=assert(loadfile(path..'ChunkMesher.lua'))({require=function(name)return assert(meshmods[name],name)end})
north.map.def.width,north.map.def.height=0,0
west.map.def.width,west.map.def.height=0,0
Mesh.request(north.map,true,nil,false,100)
Mesh.request(west.map,true,nil,false,10000)
check(Mesh.pending()==2 and not Mesh.slotKnown(north.map,true),'neighbor geometry begins uncached and queued')
Mesh.pump(false)
check(started[1]=='NORTH' and #finished==0,'nearest uncached body receives first cooperative slice')
Mesh.request(north.map,true,nil,false,10000)
Mesh.request(west.map,true,nil,false,25)
Mesh.pump(false)
check(started[2]=='WEST' and #finished==0,'approaching another edge reprioritizes already-pending neighbor')
Mesh.pump(false)
check(finished[1]=='WEST' and finished[2]=='NORTH' and #started==2,'both builds finish without restarting the paused farther body')
check(Mesh.pending()==0 and Mesh.pair(west.map,true).id=='WEST','completed closest neighbor publishes a drawable body')
local withinBudget=true;for _,s in ipairs(slices)do if s>.0050001 then withinBudget=false end end
check(withinBudget and #slices>=4,'neighbor jobs retain5ms budget; approach never sets urgent')
local a,b=neighbor('A',0,0,0,0),neighbor('B',0,0,0,0)
-- Full current-map mesh is empty in this scheduling fixture too.
a.map.def.borderBlock,b.map.def.borderBlock=false,false
function b.map:tileAt()return nil end
Mesh.request(a.map,true,nil,false,0);Mesh.request(b.map,false,nil,true)
Mesh.pump(false)
check(started[#started]=='B','current-map urgent build still precedes nearest neighbor')
check(math.abs(slices[#slices]-.012)<1e-8,'only existing urgent current-map path retains12ms budget')
local countBefore=#started
Mesh.request(b.map,false,nil,true);Mesh.pump(false,.002)
check(#started==countBefore+1 and started[#started]=='A','finishing current mesh continues queued neighbor without restart')
check(slices[#slices]<=.0020001,'caller2ms cap remains respected')
print('PASS '..checks..' neighbor visibility/streaming checks')
