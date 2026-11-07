return function(V,map,check,write)
  local g=love.graphics
  local mesh=V.require('ChunkMesher').grass(map)
  local quads=V.require('Structures').forMap(map).grassQuads
  check(mesh and mesh.voxelMeshParts and #mesh.voxelMeshParts>1,'large grass uses bounded mesh parts')
  local parts=mesh.voxelMeshParts
  local total,matching,order=0,true,true
  for _,part in ipairs(parts)do
    local count=part:getVertexCount()
    check(count<=4096*4,'each auxiliary allocation is at most 4096 quads')
    for _,index in ipairs({1,2,3,4,count-3,count-2,count-1,count})do
      local original=total+index;local q=quads[math.floor((original-1)/4)+1]
      local corner=(original-1)%4+1;local v={part:getVertex(index)}
      local uv=q.uv and q.uv[corner] or {q.u,q.v}
      local expected={q[corner][1],q[corner][2],q[corner][3],uv[1],uv[2],q.shade}
      for j=1,6 do if math.abs(v[j]-expected[j])>1e-5 then matching=false end end
    end
    local idx=part:getVertexMap()
    for _,start in ipairs({1,#idx-5})do
      local base=(start-1)/6*4
      for i,v in ipairs({1,2,3,1,3,4})do if idx[start+i-1]~=base+v then order=false end end
    end
    total=total+count
  end
  check(total==#quads*4 and mesh:getVertexCount()==total,'combined vertex count keeps every original quad')
  check(matching,'XYZ UV and shade agree at every part boundary')
  check(order,'triangle winding and source order remain 1 2 3 1 3 4')
  local count=parts[1]:getVertexCount()+parts[2]:getVertexCount()
  local vertices,indices={},{}
  for i=1,count do vertices[i]={mesh:getVertex(i)}end
  for i=0,count/4-1 do for _,n in ipairs({1,2,3,1,3,4})do indices[#indices+1]=i*4+n end end
  local old=g.newMesh(V.require('Voxel3D').FORMAT,vertices,'triangles','static');old:setVertexMap(indices)
  local shader=g.newShader([[
    varying float shade;
    #ifdef VERTEX
    attribute float VertexShade;
    vec4 position(mat4 transform,vec4 p){shade=VertexShade;return transform*vec4(p.x*.9+10.,p.z*.7-p.y*2.+20.,0.,1.);}
    #endif
    #ifdef PIXEL
    vec4 effect(vec4 c,Image image,vec2 uv,vec2 sc){return Texel(image,uv)*vec4(shade,shade,shade,1.);}
    #endif
  ]])
  local target=g.newCanvas(640,360,{dpiscale=1})
  local function draw(grouped)
    g.push('all');g.setCanvas(target);g.clear(.2,.3,.4,1)
    g.setShader(shader);g.setColor(1,1,1,1)
    local start=g.getStats().drawcalls
    if grouped then
      for i=1,2 do parts[i]:setTexture(map.renderer.image);g.draw(parts[i])end
    else old:setTexture(map.renderer.image);g.draw(old)end
    local calls=g.getStats().drawcalls-start
    g.pop();local pixels=target:newImageData()
    return pixels,calls
  end
  local reference,oldCalls=draw(false);local split,newCalls=draw(true)
  check(reference:getString()==split:getString(),'split and previous single-mesh GL output are byte-identical')
  write('aux-before.png',reference:encode('png'):getString());write('aux-after.png',split:encode('png'):getString())
  old:release();shader:release();target:release()
  return {quads=#quads,parts=#parts,maximumPartQuads=4096,comparedQuads=count/4,
    oldSampleDrawcalls=oldCalls,newSampleDrawcalls=newCalls,byteIdenticalPixels=true}
end
