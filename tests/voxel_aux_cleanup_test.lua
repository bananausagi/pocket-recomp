-- Focused fault/cancellation ownership test; no graphics driver or ROM.
local root=os.getenv('JP_QA_ROOT') or '.'
package.path=root..'/?.lua;'..package.path
local checks=0
local function check(ok,label)assert(ok,label);checks=checks+1;print('PASS '..label)end
local function scenario(mode)
  local images,uploads={},0
  love={timer={getTime=os.clock}}
  package.loaded['src.render.Assets']={register=function()end}
  package.loaded['src.render.PackedVoxelMesh']={available=function()return false end}
  local q={{0,0,0},{1,0,0},{1,1,0},{0,1,0},u=0,v=0,shade=1}
  local many={};for i=1,5000 do many[i]=q end
  local S={grassQuads=mode=='figures' and {} or many,flowerQuads={},figures={},shapeAt={},tileAt={},runs={},objectQuads={}}
  if mode=='figures' then
    S.figures={{quads={q},wx=0,wz=0},{quads=many,wx=1,wz=0}}
  end
  local function finish(vertices)
    if #vertices==0 then return nil end
    uploads=uploads+1
    if (mode=='failure' or mode=='nil') and uploads==2 then
      if mode=='nil' then return nil end
      error('injected upload failure')
    elseif mode=='figures' and uploads==3 then error('later figure failed')end
    local mesh={released=false}
    function mesh:release()self.released=true end
    images[#images+1]=mesh
    return mesh
  end
  local mods={
    Structures={forMap=function()return S end,invalidate=function()end},
    TileShape={forMap=function()return {}end},
    Voxel3D={newMesh=finish,pushQuad=function(indices,n)
      for _,i in ipairs({1,2,3,1,3,4})do indices[#indices+1]=n*4+i end
    end},
    BuildBudget={tick=function()end,begin=function()end,finish=function()end,check=function()
      if mode=='cancel' and uploads==1 then coroutine.yield('cancel-fixture')end
    end},
    VoxelMeshDisk={available=function()return false end,invalidate=function()end},
  }
  local V={require=function(name)return assert(mods[name],name)end}
  local Mesh=assert(loadfile(root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/ChunkMesher.lua'))(V)
  local map={id='QA',def={width=0,height=0},tileset={tilesPerRow=16}}
  Mesh.request(map,true)
  Mesh.pump(false,.002)
  if mode=='cancel' then
    check(Mesh.pending()==1 and #images==1 and not images[1].released,'first uploaded part is unpublished while build is suspended')
    Mesh.cancelPending('QA',true)
    check(Mesh.pending()==0 and images[1].released,'cancellation releases unpublished uploaded part immediately')
  else
    while Mesh.pending()>0 do Mesh.pump(false,.002)end
    local released=true;for _,mesh in ipairs(images)do if not mesh.released then released=false end end
    check(released,mode..' releases all discarded partial products')
    if mode=='figures' then check(Mesh.figures(map)==nil,'failed figure collection never publishes its successful prefix')
    else check(not Mesh.grass(map),mode..' never publishes incomplete grass')end
  end
end
for _,mode in ipairs({'cancel','failure','nil','figures'})do scenario(mode)end
print('PASS '..checks..' auxiliary mesh cleanup checks')
