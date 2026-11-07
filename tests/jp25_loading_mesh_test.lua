-- Cold terrain publication, cancellation/resume and scheduling ownership.
local root=os.getenv('JP_QA_ROOT') or '.'
package.path=root..'/?.lua;'..package.path
local checks=0
local function check(ok,label)assert(ok,label);checks=checks+1;print('PASS '..label)end
local function scenario(mode)
  love={timer={getTime=os.clock}}
  package.loaded['src.render.Assets']={register=function()end}
  package.loaded['src.render.PackedVoxelMesh']={available=function()return false end}
  local q={{0,0,0},{1,0,0},{1,1,0},{0,1,0},u=0,v=0,shade=1,own=true}
  local many={};for i=1,5000 do many[i]=q end
  local k=64*4096+64
  local S={grassQuads=many,flowerQuads={},figures={},skip={},ground={},
    shapeAt={[k]={class='water',h=-2,art='flat'}},tileAt={[k]=0},runs={},objectQuads={q}}
  local images,yieldCount={},0
  local mods={
    Structures={forMap=function()return S end,invalidate=function()end},
    TileShape={forMap=function()return {}end},
    Voxel3D={newMesh=function(vertices)
      if #vertices==0 then return nil end
      local mesh={released=false,vertices=#vertices}
      function mesh:release()self.released=true end
      images[#images+1]=mesh;return mesh
    end,pushQuad=function(indices,n)
      for _,i in ipairs({1,2,3,1,3,4})do indices[#indices+1]=n*4+i end
    end},
    BuildBudget={tick=function()end,begin=function()end,finish=function()end,check=function()
      if (#images==3 and yieldCount==0) or (mode=='priority' and #images==6 and yieldCount==1) then
        yieldCount=yieldCount+1;coroutine.yield()
      end
    end},
    VoxelMeshDisk={available=function()return mode=='aux_failure' end,invalidate=function()end,
      loadTerrain=function()return nil end,loadAux=function()error('injected cold auxiliary failure')end},
  }
  local Mesh=assert(loadfile(root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/ChunkMesher.lua'))({require=function(id)return assert(mods[id],id)end})
  local map={id='CURRENT',def={width=1,height=1},tileset={tilesPerRow=16}}
  Mesh.request(map,true,nil,true);Mesh.pump(true)
  local terrain,water=Mesh.pair(map,true)
  if mode=='aux_failure' then
    check(terrain==images[1] and not terrain.released,'auxiliary exception preserves published terrain')
    check(water==images[2] and not water.released and Mesh.pending()==0,'auxiliary exception preserves water pair and settles job')
    check(Mesh.slotKnown(map,true),'auxiliary exception settles missing products without endless retry')
    return
  end
  check(terrain==images[1] and water==images[2],'terrain/water pair published before unfinished grass')
  check(Mesh.jobPending(map.id,true) and not Mesh.slotKnown(map,true),'visible terrain retains pending auxiliary work')
  check(not Mesh.grass(map) and not images[3].released,'unfinished grass stays private')
  if mode=='cancel' then
    Mesh.cancelPending(map.id,true)
    check(images[3].released and not terrain.released and not water.released,'cancel releases private grass, preserving visible terrain')
    Mesh.request(map,true,nil,true)
    while Mesh.pending()>0 do Mesh.pump(true)end
    check(Mesh.peek(map,true)==terrain and #images==5,'resume builds only two grass parts without duplicating terrain')
    check(Mesh.slotKnown(map,true) and Mesh.grass(map)~=nil,'resumed material collection reaches fully known state')
  elseif mode=='invalidate' then
    Mesh.invalidate(map.id)
    check(terrain.released and water.released and images[3].released and Mesh.pending()==0,'invalidation releases both published and unpublished resources')
    check(not Mesh.peek(map,true) and not Mesh.slotKnown(map,true),'invalidation clears both ready and building states')
  else
    local destination={id='DESTINATION',def=map.def,tileset=map.tileset}
    Mesh.request(destination,true,nil,true,0,true);Mesh.pump(true)
    check(Mesh.peek(destination,true)==images[4],'confirmed cold destination outranks older visible-map foliage')
    check(Mesh.jobPending(map.id,true) and Mesh.jobPending(destination.id,true),'priority change preserves both continuations')
    while Mesh.pending()>0 do Mesh.pump(true)end
    check(Mesh.slotKnown(map,true) and Mesh.slotKnown(destination,true),'both maps finish without duplicate requests')
  end
end
for _,mode in ipairs({'cancel','invalidate','priority','aux_failure'})do scenario(mode)end
print('PASS '..checks..' jp25 staged mesh checks')
