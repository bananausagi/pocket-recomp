-- Identical before/after workload, running the actual delivered renderer.
-- Authored trees and eight-frame water; no ROM, fake mesher, or fake clock.
local M={}
function M.run(Game,Renderer,V,data,out,hashes)
  local g,fs=love.graphics,love.filesystem
  local Json=require('src.link.Json')
  local Mesh,Scene,Pre=V.require('ChunkMesher'),V.require('VoxelScene'),V.require('VoxelPrecache')
  local Atlas=V.require('TerrainAtlas')
  local Loader=require('src.world.MapLoader')
  local OW=require('src.world.OverworldController')
  local Palette=require('src.render.PaletteFX')
  local image=love.image.newImageData(128,128)
  image:mapPixel(function(x,y)local c=({1,.66,.33,0})[(x+y)%4+1];return c,c,c,1 end)
  for y=0,15 do for x=0,15 do
    local r=((x-7.5)/7)^2+((y-6.5)/6)^2
    local c=r<=1 and (r>.74 and 0 or ((x*3+y)%5==0 and .33 or .66)) or 1
    if r>1 and y>=11 and x>=6 and x<=9 then c=.33 end
    local tx,ty=(x<8 and 0 or 1),(y<8 and 4 or 5)
    image:setPixel(tx*8+x%8,ty*8+y%8,c,c,c,1)
  end end
  fs.write('adjacent-fixture.png',image:encode('png'));image:release()
  local ground,trees,water={},{},{}
  for y=0,3 do for x=0,3 do
    ground[#ground+1]=44;trees[#trees+1]=(y%2==0 and 64 or 80)+x%2;water[#water+1]=20
  end end
  local ts={id='OVERWORLD',image='adjacent-fixture.png',imageWidth=128,imageHeight=128,
    tilesPerRow=16,blocks={},walkable={44},counterTiles={},doorTiles={},warpTiles={},
    waterTiles={20},shoreTiles={},animatedTiles={{kind='hshift',tile=20,offsets={0,1,2,3,4,5,6,7},period=20}}}
  for i=1,16 do ts.blocks[i]=ground end
  ts.blocks[2],ts.blocks[3],ts.blocks[16]=trees,water,trees
  data.tilesets.OVERWORLD=ts
  local function def(id,w,h,seed)
    local blocks={}
    for y=0,h-1 do for x=0,w-1 do
      local tree=x<2 or x>w-3 or y<2 or y>h-3 or (x*7+y*11+seed)%9<3
      if x>=4 and x<=7 then tree=false end
      blocks[#blocks+1]=(x>=w-5 and x<=w-3 and y>4 and y<9) and 2 or (tree and 1 or 0)
    end end
    local m={id=id,index=2100+seed,tileset='OVERWORLD',width=w,height=h,outdoor=true,
      blocks=blocks,borderBlock=15,connections={},warps={},objects={},signs={}}
    data.maps[id]=m;return m
  end
  local root=def('ADJ_ROOT',20,18,1)
  local north=def('ADJ_NORTH',10,24,2)
  local south=def('ADJ_SOUTH',16,12,3)
  local east=def('ADJ_EAST',12,20,4)
  local nextMap=def('ADJ_NEXT',10,12,5)
  local beyond=def('ADJ_BEYOND',10,12,6)
  local houseA=def('ADJ_HOUSE_A',5,4,7);houseA.outdoor=false
  local houseB=def('ADJ_HOUSE_B',5,4,8);houseB.outdoor=false
  local function join(a,dir,b,back,offset)
    a.connections[dir]={map=b.id,offset=offset};b.connections[back]={map=a.id,offset=-offset}
  end
  join(root,'north',north,'south',2);join(root,'south',south,'north',0)
  join(root,'east',east,'west',1);join(north,'north',nextMap,'south',0)
  join(nextMap,'north',beyond,'south',0)
  root.warps={{x=12,y=13,destMap=houseA.id,destWarp=1},{x=12,y=15,destMap=houseB.id,destWarp=1}}
  houseA.warps={{x=1,y=1,destMap=root.id,destWarp=1}}
  houseB.warps={{x=1,y=1,destMap=root.id,destWarp=2}}
  local state={entities={},ghosts={},player={},camera=require('src.render.Camera').new()}
  local vw,vh=Renderer:worldViewSize()
  state.neighborViewW,state.neighborViewH=vw,vh
  local function position(x,y)
    local p=state.player;p.cellX,p.cellY,p.targetX,p.targetY,p.px,p.py=x,y,x,y,x*16,y*16
  end
  local function enter(id,x,y)
    state.map=Loader.load(data,id);state.neighbors={};position(x,y)
    for _,nb in ipairs(OW.computeNeighbors(data.maps,id,2,math.floor(vw/2)+64,math.floor(vh/2)+64))do
      state.neighbors[#state.neighbors+1]={map=Loader.load(data,nb.id),ox=nb.ox,oy=nb.oy}
    end
    Game.overworld=state
  end
  Game.stack={states={state},top=function()return state end,visibleBase=function()return 1 end}
  require('src.render.Pipelines').setLevel('voxel',2);Palette.setMode('gbc')
  local colors={root={{245,250,235},{170,205,130},{50,130,70},{10,25,20}},
    other={{245,245,255},{180,195,235},{80,110,170},{10,25,50}}}
  local function paletteFor(map)return map.id==root.id and colors.root or colors.other end
  local stages={scene=0,prediction=0,mesher=0}
  local function step()
    local t=love.timer.getTime()
    Scene.prefetch(state);local s=love.timer.getTime();Pre.update(Game);local p=love.timer.getTime();Mesh.pump(false)
    local m=love.timer.getTime()
    stages.scene=math.max(stages.scene,(s-t)*1000);stages.prediction=math.max(stages.prediction,(p-s)*1000)
    stages.mesher=math.max(stages.mesher,(m-p)*1000)
    return (love.timer.getTime()-t)*1000
  end
  local function sig(mesh)
    if not mesh then return {vertices=0,hash='empty'} end
    local pieces,count={},0
    for _,part in ipairs(type(mesh)=='table' and mesh.voxelMeshParts or {mesh})do
      count=count+part:getVertexCount()
      for i=1,part:getVertexCount(),4 do
        local q={}
        for j=0,3 do q[#q+1]=love.data.pack('string','<ffffff',part:getVertex(i+j)) end
        pieces[#pieces+1]=table.concat(q)
      end
    end
    table.sort(pieces) -- canonical quad order; original winding/UV/shade retained
    local bytes=table.concat(pieces)
    if os.getenv('JP_WORLD_TRACE') and count>10000 then
      local f=assert(io.open(out..'/diagnostic-vertices.bin','wb'));f:write(bytes);f:close()
    end
    return {vertices=count,hash=love.data.encode('string','hex',love.data.hash('sha256',bytes))}
  end
  local report={source_hashes=hashes,renderer={g.getRendererInfo()},romUsed=false,trials={}}
  for trial=1,3 do
    Mesh.invalidate();Atlas.invalidate();Pre.reset();Loader.invalidateAll();enter(root.id,12,14)
    -- Only the current map is ready at t=0: a real cold neighbour queue.
    Mesh.request(state.map,false,Pre.masksFor(data,root.id,state),true)
    for i=1,10000 do Mesh.pump(false);if Mesh.slotKnown(state.map,false) then break end end
    assert(Mesh.slotKnown(state.map,false),'initial map completes')
    state.camera.x,state.camera.y=12*16-vw/2,14*16-vh/2
    -- The real renderer owns the live palette resolver used by prewarming.
    assert(Scene.render(state,960,720,vw,vh,paletteFor,{}))
    local target=Loader.load(data,north.id)
    local times,readyFrame={},nil
    stages={scene=0,prediction=0,mesher=0}
    local start=love.timer.getTime()
    -- Three seconds beside the competing doors, then one second to the seam.
    for frame=1,240 do
      if frame>180 then position(12,math.max(0,14-math.floor((frame-180)*14/60))) end
      times[#times+1]=step()
      if not readyFrame and Mesh.slotKnown(target,false) and Scene.atlasReady(target) then readyFrame=frame end
    end
    local before={body=Mesh.slotKnown(target,true),full=Mesh.slotKnown(target,false),atlas=Scene.atlasReady(target),
      outerBody=Mesh.slotKnown(Loader.load(data,beyond.id),true),pending=Mesh.pending()}
    local leadCpu=(love.timer.getTime()-start)*1000
    enter(north.id,8,north.height*2-1)
    Scene.prefetch(state)
    local seamStart=love.timer.getTime();local remaining=0
    while not (Mesh.slotKnown(target,false) and Scene.atlasReady(target)) do
      step();remaining=remaining+1;assert(remaining<10000,'seam preparation settles')
    end
    local seamMs=(love.timer.getTime()-seamStart)*1000
    local uploads,original=0,g.newImage
    g.newImage=function(...)uploads=uploads+1;return original(...)end
    Scene.warmAtlas(target);g.newImage=original
    table.sort(times)
    local rec={trial=trial,lead_frames=240,lead_cpu_ms=leadCpu,ready_frame=readyFrame or false,
      update_p50_ms=times[120],update_p95_ms=times[228],update_max_ms=times[240],
      before_seam=before,seam_remaining_frames=remaining,seam_cpu_ms=seamMs,arrival_uploads=uploads,
      texture_memory_bytes=g.getStats().texturememory,heap_kb=collectgarbage('count')}
    rec.max_stage_ms=stages
    local terrain,waterMesh=Mesh.pair(target,false)
    if trial==3 then rec.geometry={terrain=sig(terrain),water=sig(waterMesh),grass=sig(Mesh.grass(target)),flowers=sig(Mesh.flowers(target))} end
    report.trials[#report.trials+1]=rec;print(Json.encode(rec))
    collectgarbage('collect')
  end
  report.result='complete'
  local f=assert(io.open(out..'/performance.json','wb'));f:write(Json.encode(report));f:close()
end
return M
