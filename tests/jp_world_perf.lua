-- Actual DRAMALESS Structures/ChunkMesher/VoxelScene on authored fixture art.
-- No cartridge pixels or map data: the forest tiles and both maps are generated
-- below. This stresses the same round-tree stamp path as outdoor gameplay.
local M={}
function M.run(Game,Renderer,V,data,output,sourceHashes,ffi)
  local g=love.graphics
  local Json=require("src.link.Json")
  local operations={}
  local function watched(name,fn)
    return function(...)
      local start=love.timer.getTime();local value=fn(...)
      local dt=1000*(love.timer.getTime()-start)
      local s=operations[name] or {calls=0,total_ms=0,max_ms=0}
      operations[name]=s;s.calls=s.calls+1;s.total_ms=s.total_ms+dt;s.max_ms=math.max(s.max_ms,dt)
      return value
    end
  end
  if os.getenv("JP_WORLD_TRACE") then
    local ffi=assert(package.loaded.ffi)
    ffi.new=watched("ffi.new",ffi.new);ffi.copy=watched("ffi.copy",ffi.copy)
    g.newMesh=watched("newMesh",g.newMesh)
    love.data.newByteData=watched("newByteData",love.data.newByteData)
    local probe=g.newMesh({{"VertexPosition","float",2}},3,"triangles","static")
    local methods=getmetatable(probe).__index
    methods.setVertices=watched("setVertices",methods.setVertices)
    methods.setVertexMap=watched("setVertexMap",methods.setVertexMap)
    probe:release()
  end
  local function write(name,bytes)local f=assert(io.open(output.."/"..name,"wb"));f:write(bytes);f:close()end
  local img=love.image.newImageData(128,128)
  img:mapPixel(function()return 1,1,1,1 end)
  for y=0,7 do for x=0,7 do
    local q=(x+y)%4==0 and 0.66 or 1
    img:setPixel(96+x,16+y,q,q,q,1) -- tile 44, authored ground pattern
  end end
  for y=0,15 do for x=0,15 do
    local radius=((x-7.5)/7)^2+((y-6.5)/6)^2
    local shade=1
    if radius<=1 then shade=radius>0.74 and 0 or ((x*3+y)%5==0 and 0.33 or 0.66)
    elseif y>=11 and x>=6 and x<=9 then shade=(x==6 or x==9) and 0 or 0.33 end
    local tx,ty=(x<8 and 0 or 1),(y<8 and 4 or 5)
    img:setPixel(tx*8+x%8,ty*8+y%8,shade,shade,shade,1)
  end end
  assert(love.filesystem.write("forest-fixture.png",img:encode("png")))
  local ground,tree={},{}
  for y=0,3 do for x=0,3 do
    ground[#ground+1]=44
    tree[#tree+1]=(y%2==0 and 64 or 80)+x%2
  end end
  local ts={id="OVERWORLD",image="forest-fixture.png",imageWidth=128,imageHeight=128,
    tilesPerRow=16,blocks={},walkable={44},counterTiles={},doorTiles={},warpTiles={},waterTiles={},shoreTiles={}}
  for i=1,16 do ts.blocks[i]=ground end
  ts.blocks[2],ts.blocks[16]=tree,tree
  data.tilesets.OVERWORLD=ts
  local function mapDef(id,w,h,seed)
    local blocks={}
    for y=0,h-1 do for x=0,w-1 do
      local trees=(x<3 or x>w-4 or y<2 or y>h-3 or (x*7+y*11+seed)%7<3)
      if x>=math.floor(w/2)-1 and x<=math.floor(w/2)+1 then trees=false end
      blocks[#blocks+1]=trees and 1 or 0
    end end
    local m={id=id,index=2000+seed,tileset="OVERWORLD",width=w,height=h,
      outdoor=true,blocks=blocks,borderBlock=15,connections={},warps={},objects={},signs={}}
    data.maps[id]=m;return m
  end
  local routeDef=mapDef("PERF_ROUTE",10,24,1)
  local townDef=mapDef("PERF_TOWN",20,18,2)
  routeDef.connections.north={map=townDef.id,offset=0}
  townDef.connections.south={map=routeDef.id,offset=0}
  local Loader=require("src.world.MapLoader")
  local route,town=Loader.load(data,routeDef.id),Loader.load(data,townDef.id)
  local Cam=require("src.render.Camera")
  local state={map=route,neighbors={{map=town,ox=0,oy=-18*32}},entities={},ghosts={},
    player={cellX=10,cellY=4,px=160,py=64},camera=Cam.new(),paletteNameFor=function()return "PALLET"end}
  Game.overworld=state
  Game.stack={states={state},top=function()return state end,visibleBase=function()return 1 end}
  local Scene,Mesher,Structures=V.require("VoxelScene"),V.require("ChunkMesher"),V.require("Structures")
  local Pipeline=require("src.render.Pipelines")
  local Palette=require("src.render.PaletteFX")
  Pipeline.setLevel("voxel",2);Palette.setMode("gbc")
  V.require("VoxelState").angle=math.rad(25)
  local function paletteFor()return Palette.pal(data,"PALLET")end
  local report={source_hashes=sourceHashes,fixture="procedural 16x16 tree art, real profile IDs64/65/80/81; route10x24 + town20x18 blocks; no ROM",renderer={g.getRendererInfo()},builds={},samples={}}
  local function processPeak()
    local f=io.open("/proc/self/status","r")
    if not f then return nil end
    local status=f:read("*a");f:close()
    return tonumber(status:match("VmHWM:%s+(%d+)%s+kB"))
  end
  local function build(label)
    local times={};local t=love.timer.getTime();local mem=collectgarbage("count");local peakHeap=mem
    Scene.prefetch(state)
    while Mesher.pending()>0 do
      local start=love.timer.getTime();Mesher.pump(false)
      times[#times+1]=1000*(love.timer.getTime()-start)
      peakHeap=math.max(peakHeap,collectgarbage("count"))
      assert(#times<10000,"mesher must finish")
    end
    local total=1000*(love.timer.getTime()-t)
    table.sort(times)
    local terrain=assert(Scene.prefetch(state))
    local S=Structures.forMap(state.map)
    local stat={label=label,total_ms=total,slices=#times,max_slice_ms=times[#times] or 0,
      median_slice_ms=times[math.max(1,math.floor(#times/2))] or 0,
      heap_delta_kb=collectgarbage("count")-mem,sampled_gc_heap_peak_kb=peakHeap,process_peak_rss_kb=processPeak(),vertices=terrain:getVertexCount(),stamps=#S.roundStamps}
    report.builds[#report.builds+1]=stat;print(Json.encode(stat))
  end
  collectgarbage("collect");build("cold-route-and-neighbor")
  state.map=town;state.neighbors={{map=route,ox=0,oy=18*32}}
  build("town-seam-promotion")
  local function draw(i,shot)
    local Viewport=require("src.render.GameViewport");Viewport.begin(1)
    Renderer:beginFrame(true);Renderer:beginWorldPass()
    local vw,vh=Renderer:worldViewSize()
    state.camera.x=160-vw/2+math.sin(i/35)*24
    state.camera.y=400-vh/2+math.cos(i/35)*24
    local c=assert(Pipeline.drawWorld("voxel",{state=state,cam=state.camera,vw=vw,vh=vh,
      paletteFor=paletteFor,drawFx=function()end,scale=Renderer:fitScale(),level=2,width=960,height=720}))
    Renderer:setWorldOverride(c,vw,vh);Renderer:endWorldPass();Viewport.setTarget()
    Renderer:endFrame();Viewport.finish(Game)
    if shot then g.captureScreenshot(function(p)write(shot..".png",p:encode("png"):getString())end)end
    local stats=g.getStats();g.present();return stats
  end
  for i=1,35 do draw(i)end
  for sample=1,(os.getenv("JP_WORLD_TRACE") and 0 or 4) do
    collectgarbage("collect")
    local before=collectgarbage("count");local start=love.timer.getTime();local cpu=os.clock();local stats
    for i=1,90 do stats=draw(i)end
    local dt=love.timer.getTime()-start
    local rec={sample=sample,frames=90,wall_ms=dt/90*1000,process_cpu_ms=(os.clock()-cpu)/90*1000,
      net_heap_kb_per_frame=(collectgarbage("count")-before)/90,stats=stats}
    report.samples[#report.samples+1]=rec;print(Json.encode(rec))
  end
  -- Count actual submitted Mesh indices for one additional frame, outside
  -- timing. This includes independent sunlight culling and leaves quality as set.
  local rawDraw,rawInstanced=g.draw,g.drawInstanced
  local submission={calls=0,indices=0,instancedCalls=0}
  g.drawInstanced=function(mesh,count,...)
    submission.calls=submission.calls+1;submission.instancedCalls=submission.instancedCalls+1
    submission.indices=submission.indices+#mesh:getVertexMap()*count
    return rawInstanced(mesh,count,...)
  end
  g.draw=function(mesh,...)
    if type(mesh)=="userdata" and mesh.typeOf and mesh:typeOf("Mesh") then
      local first,count=mesh:getDrawRange()
      if not count then local map=mesh:getVertexMap();count=map and #map or mesh:getVertexCount() end
      submission.calls=submission.calls+1;submission.indices=submission.indices+count
    end
    return rawDraw(mesh,...)
  end
  draw(1,"world")
  g.draw=rawDraw;g.drawInstanced=rawInstanced
  report.submitted_mesh_indices=submission
  report.process_peak_rss_kb_before_readback=processPeak()
  -- Fingerprint actual GPU vertex values in original triangle order. Indexed
  -- optimization may store fewer vertices but must produce identical triangles.
  local terrain=Mesher.peek(town,false)
  local vertices=terrain:getVertexCount()
  local index=terrain:getVertexMap()
  report.terrain_vertices=vertices;report.terrain_indices=index and #index or nil
  -- Read real GPU Mesh attributes after timing. Original vertex order is
  -- retained, while spatial index partitioning can change triangle order.
  -- Hash all six float32 attributes and prove each indexed quad appears once.
  local bytes=love.data.newByteData(vertices*24)
  local ptr=ffi.cast("float*",bytes:getFFIPointer())
  for i=1,vertices do
    local x,y,z,u,v,shade=terrain:getVertex(i);local at=(i-1)*6
    ptr[at],ptr[at+1],ptr[at+2],ptr[at+3],ptr[at+4],ptr[at+5]=x,y,z,u,v,shade
  end
  report.vertex_sha256=love.data.encode("string","hex",love.data.hash("sha256",bytes))
  bytes:release()
  assert(index and #index==vertices/4*6,"same indexed quad topology")
  local seen=ffi.new("uint8_t[?]",vertices/4)
  for i=1,#index,6 do
    local v=index[i];local q=(v-1)/4
    assert(q%1==0 and q>=0 and q<vertices/4 and seen[q]==0,"every quad exactly once")
    assert(index[i+1]==v+1 and index[i+2]==v+2 and index[i+3]==v
      and index[i+4]==v+2 and index[i+5]==v+3,"original triangle winding")
    seen[q]=1
  end
  report.quad_topology="each original quad once, 0/1/2,0/2/3 winding"
  report.result="complete"
  report.operations=operations
  write("performance.json",Json.encode(report))
end
return M
