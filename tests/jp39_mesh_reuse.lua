-- Real Mesh/GL checks for shared ownership, exact scenery, water and fallback.
return function(Game,V,map,check,write)
 local M=V.require('ChunkMesher');local C=V.require('Voxel3D');local I=V.require('TreeInstances')
 local g=love.graphics;local masks={{0,-500,192,0}}
 local function pump()local n=0;while M.pending()>0 do M.pump(false);n=n+1;assert(n<3000)end end
 local function valid(mesh)return pcall(mesh.getVertexCount,mesh)end
 V.require('SceneryDistance').setting:sync(12)
 map:setBlock(2,2,15);M.invalidate()
 M.request(map,true,nil,true);pump();local body=assert(M.peek(map,true))
 local first=body.voxelMeshParts[1]
 M.request(map,false,masks,true);pump();local full=assert(M.peek(map,false))
 check(full.voxelMeshParts[1]==first,'full scenery reuses exact body GPU pages')
 local reference,referenceWater=M.build(map,false,masks,true)
 check(full:getVertexCount()==reference:getVertexCount(),'shared/instanced geometry preserves every terrain vertex')
 local function pixels(mesh)
  C.camera=nil;V.require('VoxelState').angle=math.rad(50)
  assert(C.beginScene(640,360,80,75,180,110,nil,'reuse39'))
  C.draw(mesh,map.renderer.image);local canvas=C.endScene()
  return canvas:newImageData(),canvas
 end
 local a=pixels(reference);local b,canvas=pixels(full)
 local diff,max=0,0
 for y=0,359 do for x=0,639 do
  local ar,ag,ab,aa=a:getPixel(x,y);local br,bg,bb,ba=b:getPixel(x,y)
  local d=math.max(math.abs(ar-br),math.abs(ag-bg),math.abs(ab-bb),math.abs(aa-ba))
  if d>1/255+.00001 then diff=diff+1 end;max=math.max(max,d)
 end end
 check(diff==0,'instanced/reused terrain matches exact expanded reference pixels')
 local sun=V.require('ShadowMap')
 local function shadow(mesh)
  assert(sun.begin(80,75,180,110));sun.draw(mesh,map.renderer.image);sun.finish('qa39')
  return sun.texture():newImageData():getString()
 end
 check(shadow(reference)==shadow(full),'shared trees cast exactly the same shadow-map pixels')
 write('reused-forest.png',canvas:newImageData():encode('png'):getString())
 a:release();b:release();reference:release();if referenceWater then referenceWater:release()end
 if I.available()then check(I.stats.placements>10,'real hardware instancing submitted repeated tree placements')end
 -- A dirty body may publish before the matching border; old full pages must
 -- remain drawable until both slots are replaced, then be released exactly once.
 M.refresh(map.id);M.request(map,true,nil,true);pump()
 check(valid(first),'old full scene keeps old body alive during refresh')
 M.request(map,false,masks,true);pump()
 check(not valid(first),'old body is freed after final full reference is replaced')
 local held=M.peek(map,false).voxelMeshParts[1];M.invalidate(map.id)
 check(not valid(held),'eviction releases shared pages after both cache slots')
 -- Driver advertises instancing but rejects per-instance attributes: retry
 -- the ordinary paged path once, not a missing forest or a blank map.
 local available=I.available
 if available()then
  local probe=g.newMesh({{'VertexPosition','float',3}},3,'triangles','static')
  local methods=getmetatable(probe).__index;local attach=methods.attachAttribute
  local called=0
  methods.attachAttribute=function()called=called+1;error('fixture unsupported instance attributes')end
  M.request(map,false,masks,true);pump();methods.attachAttribute=attach;probe:release()
  check(called==1 and M.peek(map,false)~=nil,'rejected per-instance attributes fall back once with complete scenery')
  M.invalidate()
 end
 -- Distinct water pages also share lifetime and use the reflective draw path.
 local ts=map.tileset;local wet={}
 for k,v in pairs(ts)do wet[k]=v end
 wet.id='JP39_WATER';wet.waterTiles={44};wet.walkable={};wet.blocks={}
 local block={};for i=1,16 do block[i]=44 end;wet.blocks[1]=block
 Game.data.tilesets.JP39_WATER=wet
 Game.data.maps.JP39_WATER={id='JP39_WATER',index=2939,tileset=wet.id,width=2,height=2,
  blocks={0,0,0,0},borderBlock=0,outdoor=true,connections={},warps={},objects={},signs={}}
 local waterMap=require('src.world.MapLoader').load(Game.data,'JP39_WATER')
 M.request(waterMap,false,{},true);pump()
 local _,bw=M.pair(waterMap,true);local _,fw=M.pair(waterMap,false)
 check(bw and fw and fw.voxelMeshParts[1]==bw.voxelMeshParts[1],'water body page is shared with full reflected surface')
 local _,rw=M.build(waterMap,false,{},true)
 check(rw and rw:getVertexCount()==fw:getVertexCount(),'water reuse adds no duplicate surfaces')
 rw:release();M.invalidate()
 local Buildings=V.require('Buildings')
 local q={{{0,1,0},{2,1,0},{2,3,0},{0,3,0},uv={{0,0},{1,0},{1,1},{0,1}},shade=.8}}
 Buildings.applyHeightScale(q,1.4)
 check(math.abs(q[1][3][2]-4.2)<1e-9 and q[1][3][1]==2 and q[1].shade==.8,'house scaling changes Y only, preserving footprint, material and shade')
 check(V.require('DayNight').K_MAX==.7 and V.require('DayNight').ALPHA_SUN==.3,'compact soft shadow parameters match adopted field style')
 local forest=V.require('VoxelScene')._skyFor({id='VIRIDIAN_FOREST',def={tileset='FOREST',outdoor=false}})
 check(forest and forest.canopy and not forest.bands,'forest backdrop is tinted canopy with no open sky')
 write('mesh-reuse39.json',require('src.link.Json').encode({pixelDifferences=diff,maxChannelDifference=max,
  treeInstances=I.stats,driverFallbackChecked=not I.available(),romUsed=false}))
end
