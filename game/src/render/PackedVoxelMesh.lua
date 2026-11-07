-- SPDX-License-Identifier: GPL-3.0-only
-- Native packing without exposing ffi or pointers to the MOD sandbox.
-- A voxel quad has position XYZ, UV and one shade per corner. Store its four
-- corners once and retain the exact 1,2,3,1,3,4 triangle order in a native map.
local Packed={}
local ok,ffi=pcall(require,"ffi")
if not ok then ffi=nil end
local FORMAT={{"VertexPosition","float",3},{"VertexTexCoord","float",2},{"VertexShade","float",1}}
local STRIDE=24
local MAX_VERTICES=16777216
local meshRanges=setmetatable({},{__mode="k"})
local function number(value)
  assert(type(value)=="number" and value==value
    and value>=-3.4028234e38 and value<=3.4028234e38,
    "voxel components must be finite float32 numbers")
  return value
end

function Packed.available()
  return ffi~=nil and love and love.data and love.data.newByteData
    and love.graphics and love.graphics.newMesh and true or false
end

function Packed.new(checkBudget,partition)
  assert(Packed.available(),"native voxel packing unavailable")
  assert(checkBudget==nil or type(checkBudget)=="function","budget callback must be a function")
  local capacity,count=16384,0
  local closed=false
  local mesh,temporary
  local buffer=ffi.new("float[?]",capacity*6)
  local keys=partition and ffi.new("uint32_t[?]",capacity/4) or nil
  local groups,grid={},{}
  -- Terrain may group indices spatially. Foliage must retain source order:
  -- record contiguous spatial runs without ever sorting translucent quads.
  local ordered=partition=="ordered"
  local previousGroup,previousX,previousZ
  local function check()if checkBudget then checkBudget()end end
  local sink={}
  function sink.push(corners,uv,shade)
    assert(not closed,"voxel builder is already finished")
    assert(type(corners)=="table" and type(uv)=="table","voxel corners and UVs must be tables")
    local grew=false
    if count+4>capacity then
      assert(capacity<MAX_VERTICES,"voxel mesh exceeds vertex limit")
      local nextCapacity=math.min(MAX_VERTICES,capacity*2)
      local grown=ffi.new("float[?]",nextCapacity*6)
      ffi.copy(grown,buffer,count*STRIDE)
      if keys then
        local nextKeys=ffi.new("uint32_t[?]",nextCapacity/4)
        ffi.copy(nextKeys,keys,count)
        keys=nextKeys
      end
      buffer,capacity=grown,nextCapacity
      grew=true
    end
    local flat=type(shade)~="table"
    local base=count*6
    for i=1,4 do
      -- Ignore metatables: a MOD callback cannot re-enter this builder while
      -- native memory is being written. Its budget callback runs only after
      -- the completed quad has advanced count, with no later buffer access.
      local c,t=rawget(corners,i),rawget(uv,i)
      assert(type(c)=="table" and type(t)=="table","voxel quad requires four corners and UV pairs")
      buffer[base],buffer[base+1],buffer[base+2]=number(rawget(c,1)),number(rawget(c,2)),number(rawget(c,3))
      buffer[base+3],buffer[base+4]=number(rawget(t,1)),number(rawget(t,2))
      buffer[base+5]=number(flat and shade or rawget(shade,i))
      base=base+6
    end
    if keys then
      local first=count*6
      local xmin,ymin,zmin=buffer[first],buffer[first+1],buffer[first+2]
      local xmax,ymax,zmax=xmin,ymin,zmin
      for i=1,3 do
        local at=first+i*6
        xmin,xmax=math.min(xmin,buffer[at]),math.max(xmax,buffer[at])
        ymin,ymax=math.min(ymin,buffer[at+1]),math.max(ymax,buffer[at+1])
        zmin,zmax=math.min(zmin,buffer[at+2]),math.max(zmax,buffer[at+2])
      end
      local x,z=math.floor((xmin+xmax)/256),math.floor((zmin+zmax)/256)
      local row,group
      if ordered then
        if x==previousX and z==previousZ then group=previousGroup end
      else
        row=grid[z]
        if not row then row={};grid[z]=row end
        group=row[x]
      end
      if not group then
        group={id=#groups+1,count=0,bounds={xmin,ymin,zmin,xmax,ymax,zmax}}
        groups[group.id]=group
        if row then row[x]=group end
      else
        local b=group.bounds
        b[1],b[2],b[3]=math.min(b[1],xmin),math.min(b[2],ymin),math.min(b[3],zmin)
        b[4],b[5],b[6]=math.max(b[4],xmax),math.max(b[5],ymax),math.max(b[6],zmax)
      end
      group.count=group.count+6
      keys[count/4]=group.id
      previousGroup,previousX,previousZ=group,x,z
    end
    count=count+4
    if grew then check()end
  end
  -- A speculative build can be cancelled while finish() is suspended after
  -- an allocation/upload. Release those private GPU objects immediately;
  -- no raw pointer or FFI object is exposed to the MOD sandbox.
  function sink.cancel()
    if temporary then temporary:release();temporary=nil end
    if mesh then mesh:release();mesh=nil end
    buffer,keys=nil,nil;closed=true
  end
  function sink.finish()
    assert(not closed,"voxel builder is already finished")
    closed=true
    if count==0 then buffer,keys=nil,nil;return nil end
    local success,result=pcall(function()
      mesh=love.graphics.newMesh(FORMAT,count,"triangles","static")
      check()
      local i=0
      while i<count do
        local n=math.min(65536,count-i)
        temporary=love.data.newByteData(n*STRIDE)
        ffi.copy(temporary:getFFIPointer(),buffer+i*6,n*STRIDE)
        mesh:setVertices(temporary,i+1)
        temporary:release();temporary=nil
        i=i+n
        check()
      end
      temporary=love.data.newByteData(count/4*6*4)
      local index=ffi.cast("uint32_t*",temporary:getFFIPointer())
      local offset=0
      for _,group in ipairs(groups)do
        group.first,group.cursor=offset+1,offset
        offset=offset+group.count
      end
      local j=0
      for vertex=0,count-1,4 do
        local group=keys and groups[keys[vertex/4]]
        local at=group and group.cursor or j
        index[at],index[at+1],index[at+2]=vertex,vertex+1,vertex+2
        index[at+3],index[at+4],index[at+5]=vertex,vertex+2,vertex+3
        if group then group.cursor=at+6 end
        j=j+6
        if j%49152==0 then check()end
      end
      mesh:setVertexMap(temporary,"uint32")
      temporary:release();temporary=nil
      check()
      if #groups>0 then
        for _,group in ipairs(groups)do group.cursor=nil end
        groups.ordered=ordered
        -- Ordered grass can have hundreds of row runs. Reject broad strips
        -- first so a long distant meadow does not cost one Lua plane test
        -- per tuft-row bucket on every frame. Bounds enclose every member.
        if #groups>32 then
          local blocks={}
          for first=1,#groups,16 do
            local last=math.min(first+15,#groups)
            local b={unpack(groups[first].bounds)}
            for at=first+1,last do
              local nextBounds=groups[at].bounds
              for axis=1,3 do
                b[axis]=math.min(b[axis],nextBounds[axis])
                b[axis+3]=math.max(b[axis+3],nextBounds[axis+3])
              end
            end
            blocks[#blocks+1]={first=first,last=last,bounds=b}
            check()
          end
          groups.blocks=blocks
        end
        meshRanges[mesh]=groups
      end
      return mesh
    end)
    if not success then
      if temporary then temporary:release()end
      if mesh and mesh.release then mesh:release()end
      mesh,temporary=nil,nil
      buffer,keys=nil,nil
      error(result,0)
    end
    -- No native stream remains live in a completed coroutine/sink.
    buffer,keys=nil,nil
    mesh,temporary=nil,nil
    return result
  end
  return sink
end

-- Mesh identity and vertex attributes stay unchanged. Opaque terrain indices
-- are grouped spatially, allowing the unchanged shader to receive only ranges
-- intersecting its view. Transparent water opts out at builder creation.
local function drawRanges(mesh,ranges,context,Frustum,oldFirst,oldCount)
  local pendingFirst,pendingLast
  -- A small strip of already-proven-invisible foliage is cheaper to submit
  -- than another driver call on GLES. It cannot change pixels and its upper
  -- bound is 128 quads per gap; terrain keeps its exact visible ranges.
  local maxGap=ranges.ordered and 768 or 0
  local function flush()
    if pendingFirst then
      mesh:setDrawRange(pendingFirst,pendingLast-pendingFirst+1)
      love.graphics.draw(mesh)
      pendingFirst,pendingLast=nil,nil
    end
  end
  local function appendRange(range)
    if Frustum.test(range.bounds,context) then
      local first,last=range.first,range.first+range.count-1
      if oldFirst then
        first,last=math.max(first,oldFirst),math.min(last,oldFirst+oldCount-1)
      end
      if last>=first then
        -- A run contains exactly the same indices in exactly the same order.
        -- Adjacent visible buckets need one driver submission, not one each.
        if pendingLast and first<=pendingLast+1+maxGap then pendingLast=last
        else flush();pendingFirst,pendingLast=first,last end
      end
    end
  end
  if ranges.blocks then
    for _,block in ipairs(ranges.blocks)do
      if Frustum.test(block.bounds,context)then
        for at=block.first,block.last do appendRange(ranges[at])end
      end
    end
  else
    for _,range in ipairs(ranges)do appendRange(range)end
  end
  flush()
end
function Packed.draw(mesh,vp,model,cx,cz,k,padding)
  local ranges=meshRanges[mesh]
  if not ranges then return false end
  local Frustum=require("src.render.VoxelFrustum")
  local context=Frustum.prepare(vp,model,cx,cz,k,padding)
  local oldFirst,oldCount=mesh:getDrawRange()
  local ok,err=pcall(drawRanges,mesh,ranges,context,Frustum,oldFirst,oldCount)
  if oldFirst then mesh:setDrawRange(oldFirst,oldCount)else mesh:setDrawRange()end
  if not ok then error(err,0)end
  return true
end

-- Numeric metadata for diagnostics; no FFI allocation or pointer escapes.
function Packed.ranges(mesh)return meshRanges[mesh]end

return Packed
