-- Actual installed renderer, cloud removal, outdoor FX, blur and connected edges.
return function(Game,Renderer,V,state,check,write)
 local g,fs=love.graphics,love.filesystem
 local W,Sky,Tilt=V.require('FieldAtmosphere'),V.require('Sky'),V.require('TiltShift')
 local P=require('src.render.Pipelines');local C=V.require('Voxel3D');local opts=Game.save.options
 local function image(canvas)return canvas:newImageData():getString()end
 local function shot(canvas,name)g.setCanvas();write(name..'.png',canvas:newImageData():encode('png'):getString())end
 local outdoor={id='ROUTE_1',def={outdoor=true,tileset='OVERWORLD'}}
 local indoor={id='ROOM',def={outdoor=false,tileset='REDS_HOUSE_1'}}
 local canvas=g.newCanvas(640,360);local function base()g.setCanvas(canvas);g.clear(.22,.48,.36,1);g.setCanvas()end
 base();local clean=image(canvas);Game.overworld={map=outdoor};opts.reduceMotion=false;opts.jpFxWind=true
 check(W.cloudSetting==nil and W.prewarm==nil and W.paintClouds==nil,'cloud setting, upload and draw entry points removed')
 check(not fs.getInfo('mods/DRAMALESS_SHAPE/assets/sky/clouds.png'),'installed MOD contains no cloud image')
 for _,mode in ipairs({'clear','rain','snow','fog','storm'})do
  W.setting:sync(mode);W.setClock(12.3);base();W.apply(canvas,outdoor)
  check((image(canvas)==clean)==(mode=='clear'),'outdoor weather '..mode..' visible or exact OFF')
  check(not W.lastError,'weather '..mode..' no renderer error')
  shot(canvas,'weather-'..mode)
  base();W.apply(canvas,indoor);check(image(canvas)==clean,'weather '..mode..' never enters a room')
 end
 W.setting:sync('auto');local modes={}
 for i=0,31 do modes[W.modeAt(outdoor,'auto',i*W.AUTO_SECONDS)]=true end
 check(modes.clear and modes.rain and modes.fog and modes.storm,'automatic weather covers calm and wet conditions without game RNG')
 opts.reduceMotion=true;base();W.apply(canvas,outdoor);check(image(canvas)==clean,'reduce motion disables precipitation')
 local clock=W.clock;W.update(.1);check(W.clock==clock,'reduced motion pauses weather clock');opts.reduceMotion=false
 W.update(4);check(W.clock==clock,'resume does not jump weather after pause')
 W.setting:sync('clear');C.camera=nil
 local function sky()
  g.setCanvas(canvas);g.clear(0,0,0,1);Sky.paint(640,360,Sky.dress({1,1,1,1}),230,2);g.setCanvas()
 end
 sky();local clearSky=image(canvas);W.setClock(30);sky()
 check(image(canvas)==clearSky,'weather animation cannot add moving cloud sprites to sky');shot(canvas,'sky-without-clouds')
 local before=P.level('tiltshift');P.setLevel('tiltshift',3)
 local grid=g.newCanvas(640,360);g.setCanvas(grid)
 for y=0,359,4 do for x=0,639,4 do
  local c=(x/4+y/4)%2;g.setColor(c,c,c,1);g.rectangle('fill',x,y,4,4)
 end end;g.setColor(1,1,1,1);g.setCanvas()
 local original=grid:newImageData();local blurred=Tilt.apply(grid):newImageData()
 local function changedRow(y)
  local d=0;for x=1,638 do local a=original:getPixel(x,y);local b=blurred:getPixel(x,y);d=d+math.abs(a-b)end;return d/638
 end
 check(changedRow(180)<1e-5,'field player focus band remains pixel-sharp')
 check(changedRow(105)>.02,'blur now reaches nearer scenery previously inside the clear band')
 check(changedRow(40)>changedRow(105),'blur grows smoothly toward background')
 shot(Tilt.apply(grid),'blur-expanded');P.setLevel('tiltshift',0)
 check(Tilt.apply(grid)==grid,'blur OFF returns exact original canvas');P.setLevel('tiltshift',before)
 -- Reuse the handwritten tree/ground atlas from the performance fixture.
 local img=love.image.newImageData(128,128);img:mapPixel(function()return 1,1,1,1 end)
 for y=0,7 do for x=0,7 do local c=(x+y)%4==0 and .66 or 1;img:setPixel(96+x,16+y,c,c,c,1)end end
 for y=0,15 do for x=0,15 do
  local radius=((x-7.5)/7)^2+((y-6.5)/6)^2;local c=1
  if radius<=1 then c=radius>.74 and 0 or ((x*3+y)%5==0 and .33 or .66)
  elseif y>=11 and x>=6 and x<=9 then c=.33 end
  img:setPixel((x<8 and 0 or 8)+x%8,(y<8 and 32 or 40)+y%8,c,c,c,1)
 end end
 fs.write('field38-trees.png',img:encode('png'))
 local ground,trees={},{};for y=0,3 do for x=0,3 do ground[#ground+1]=44;trees[#trees+1]=(y%2==0 and 64 or 80)+x%2 end end
 local ts={id='OVERWORLD',image='field38-trees.png',imageWidth=128,imageHeight=128,tilesPerRow=16,
  blocks={},walkable={44},counterTiles={},doorTiles={},warpTiles={},waterTiles={},shoreTiles={}}
 for i=1,16 do ts.blocks[i]=ground end;ts.blocks[16]=trees;Game.data.tilesets.OVERWORLD=ts
 local def={id='FIELD38',index=2800,tileset='OVERWORLD',width=6,height=6,outdoor=true,blocks={},borderBlock=15,
  connections={},warps={},objects={},signs={}}
 for i=1,36 do def.blocks[i]=0 end;Game.data.maps.FIELD38=def
 local map=require('src.world.MapLoader').load(Game.data,'FIELD38')
 require('src.render.TileRenderer').setVoidFill('trees')
 local M,Shapes,D=V.require('ChunkMesher'),V.require('Structures'),V.require('SceneryDistance')
 local extents={}
 for _,setting in ipairs({4,12,20})do
  D.setting:sync(setting);M.invalidate()
  M.request(map,false,{{0,-500,192,0}},true)
  while M.pending()>0 do M.pump(false)end
  local mesh=assert(M.peek(map,false));local minx=0;local connectedClear=true
  for i=1,mesh:getVertexCount()do
   local x,y,z=mesh:getVertex(i);minx=math.min(minx,x)
   if y>1 and x>0 and x<192 and z<0 then connectedClear=false end
  end
  check(connectedClear,'connection stays clear of added border trees '..setting)
  extents[#extents+1]=minx
  check(not M.jobPending(map.id,false),'expanded scenery completes its bounded build')
  local structures=Shapes.forMap(map)
  check(structures.ringTiles==setting,'outer depth follows persisted choice '..setting)
  M.invalidate();M.request(map,false,{},true);while M.pending()>0 do M.pump(false)end
  local field={map=map,neighbors={},entities={},ghosts={},player={cellX=6,cellY=6,px=96,py=96},
    camera=require('src.render.Camera').new(),paletteNameFor=function()return 'PALLET'end}
  field.camera.x,field.camera.y=16,48;Game.overworld=field
  V.require('VoxelState').angle=math.rad(65);V.require('VoxelState').level=5
  local scene=V.require('VoxelScene').render(field,640,360,160,90,function()return nil end)
  check(scene~=nil,'extended field renders '..setting)
  shot(scene,'forest-depth-'..setting)
  if setting==12 and os.getenv('JP_QA_WEATHER43')=='1' then require('tests.jp43_weather')(Game,V,field,check,write)end
 end
 check(extents[2]<extents[1]-50 and extents[3]<extents[2]-50,'forest grows from 2 to 6 to 10 tree rows')
 check(D.stats.distantQuads<D.stats.sourceQuads*.5,'distant trees cost fewer than half the detailed template quads')
 if os.getenv('JP_QA_FIELD39')=='1' then
  require('tests.jp39_mesh_reuse')(Game,V,map,check,write)
 end
 local instances=V.require('TreeInstances');local available=instances.available
 instances.available=function()return false end
 -- A route large enough to cross multiple real terrain allocation pages.
 local bigdef={id='FIELD38_BIG',index=2801,tileset='OVERWORLD',width=24,height=24,outdoor=true,
  blocks={},borderBlock=15,connections={},warps={},objects={},signs={}}
 for i=1,24*24 do bigdef.blocks[i]=15 end;Game.data.maps.FIELD38_BIG=bigdef
 local big=require('src.world.MapLoader').load(Game.data,'FIELD38_BIG')
 D.setting:sync(4);M.invalidate();M.request(big,true,nil,true)
 while M.pending()>0 do M.pump(false)end
 local paged=assert(M.peek(big,true))
 check(type(paged)=='table' and #paged.voxelMeshParts>1,'large terrain really uses multiple GPU allocations')
 for _,part in ipairs(paged.voxelMeshParts)do check(part:getVertexCount()<=262144,'each terrain allocation is at most 6 MiB')end
 -- Independently render the same emitted geometry through the preceding
 -- monolithic Packed sink, then compare the actual depth-tested pixels.
 local source=assert(fs.read(V.path..'/lib/ChunkMesher.lua'))
 source=source:gsub('if partition==nil and hasPacked and Packed.available%(%) then return pagedTerrain%(%)end',
  'if false then return pagedTerrain()end',1)
 local other=assert(loadstring(source,'unpaged-reference'))(V)
 other.request(big,true,nil,true);while other.pending()>0 do other.pump(false)end
 local single=assert(other.peek(big,true));check(single:getVertexCount()==paged:getVertexCount(),'paging preserves all terrain vertices')
 local tex=big.renderer.image;C.camera=nil;V.require('VoxelState').angle=math.rad(50)
 local function rendered(mesh)
  check(C.beginScene(640,360,380,340,180,110,nil,'paging38'),'paging comparison target available')
  C.draw(mesh,tex);return image(C.endScene())
 end
 check(rendered(single)==rendered(paged),'paged and monolithic terrain pixels match exactly')
 other.invalidate();M.invalidate()
 -- Cancel after a real part uploads; no unpublished Mesh may survive it.
 local allocations,releases={},{}
 local create=g.newMesh
 g.newMesh=function(...)
  local mesh=create(...);allocations[#allocations+1]=mesh;return mesh
 end
 M.request(big,true,nil,true)
 for _=1,2000 do M.pump(false,.0001);if #allocations>0 then break end end
 g.newMesh=create
 check(#allocations>0 and M.jobPending(big.id,true),'cancellation happens during a real paged upload')
 M.cancelPending(big.id,true)
 local released=true
 for _,mesh in ipairs(allocations)do
  local usable=pcall(mesh.getVertexCount,mesh);if usable then released=false end
 end
 check(released and not M.peek(big,true),'cancelling upload releases every unpublished part')
 instances.available=available
 D.setting:sync(12);M.invalidate();Game.overworld=state
 write('field38-results.json',require('src.link.Json').encode({extents=extents,distant=D.stats,cloudImageRemoved=true,
  renderer={g.getRendererInfo()},romUsed=false,androidDeviceUsed=false}))
 canvas:release();grid:release()
end
