-- Actual GL render of generated connected maps through production terrain
-- dispatch + the exact production scene-distance callback. No ROM art/maps.
local function run()
  local root,out=assert(os.getenv('JP_QA_ROOT')),assert(os.getenv('JP_QA_OUT'))
  package.path=root..'/?.lua;'..package.path
  local f=require('tests.ledge_terrain_fixture').new()
  local g=love.graphics;local M=f.V.require('Mat4');local checks,rows=0,{}
  local function check(ok,msg)assert(ok,msg);checks=checks+1;print('PASS '..msg)end
  local function write(name,data)local fp=assert(io.open(out..'/'..name,'wb'));fp:write(data);fp:close()end
  f.modules.Quality.renderDistance=function()return 128 end -- actual FAR=64*2
  local callback
  for i=1,100 do
    local name,value=debug.getupvalue(f.Scene.render,i)
    if not name then break end
    if name=='withinRenderDistance' then callback=value;break end
  end
  check(type(callback)=='function','uses actual VoxelScene render-distance callback')
  local shader=g.newShader([[
    uniform mat4 vp;uniform mat4 model;
    #ifdef VERTEX
    vec4 position(mat4 ignored,vec4 p){return vp*model*p;}
    #endif
    #ifdef PIXEL
    vec4 effect(vec4 color,Image image,vec2 uv,vec2 sc){return Texel(image,uv)*color;}
    #endif
  ]])
  local color=g.newCanvas(640,480,{dpiscale=1})
  local depth=g.newCanvas(640,480,{format='depth24',readable=false,dpiscale=1})
  local function texture(r,gg,b)
    local pixels=love.image.newImageData(128,64)
    pixels:mapPixel(function(x,y)local q=(x+y)%7==0 and .8 or 1;return r*q,gg*q,b*q,1 end)
    return g.newImage(pixels)
  end
  local rootTexture=texture(.2,.3,.9)
  local neighborTexture=texture(.1,.85,.2)
  local rootMap=f:map('ROOT',8,8)
  local north=f:map('NORTH',8,128)
  local west=f:map('WEST',128,8)
  local function mesh(map)
    local vertices,indices=f.Mesher.geometry(map,true)
    local result=g.newMesh(f.Camera.FORMAT,vertices,'triangles','static')
    result:setVertexMap(indices);return result
  end
  local rootMesh,northMesh,westMesh=mesh(rootMap),mesh(north),mesh(west)
  f.Camera.draw=function(m,atlas,model)
    if not m then return end
    m:setTexture(atlas);shader:send('model','row',model or M.identity());g.draw(m)
  end
  local function draw(name,nb,nbMesh,player,eye,focus,old)
    package.loaded['src.core.Game'].overworld={player=player}
    local vp=M.mul(M.mul(M.scale(1,-1,1),M.perspective(.8,640/480,1,4000)),M.lookAt(eye,focus,{0,1,0}))
    g.setCanvas({color,depthstencil=depth});g.clear(.04,.04,.04,1,0,1)
    g.setDepthMode('lequal',true);g.setMeshCullMode('none');g.setBlendMode('replace');g.setColor(1,1,1,1)
    g.setShader(shader);shader:send('vp','row',vp)
    local filter=callback
    if old then filter=function(point)return (point.px-player.px)^2+(point.py-player.py)^2 <=1024^2 end end
    f.Camera.draw3DTerrain(rootMesh,rootTexture,{nb},{nbMesh},filter,function()return neighborTexture end)
    g.setShader();g.setDepthMode();g.setBlendMode('alpha');g.setCanvas()
    local img=color:newImageData();write(name..'.png',img:encode('png'):getString())
    local green,blue=0,0
    for y=0,479 do for x=0,639 do local r,gg,b=img:getPixel(x,y)
      if gg>r*2 and gg>b*2 then green=green+1 end
      if b>r*2 and b>gg*2 then blue=blue+1 end
    end end
    rows[#rows+1]={name=name,green=green,blue=blue}
    return green,blue
  end
  local n={map=north,ox=0,oy=-2048}
  local before=draw('north-before',n,northMesh,{px=64,py=16},{64,180,280},{64,0,-100},true)
  local after,blue=draw('north-after',n,northMesh,{px=64,py=16},{64,180,280},{64,0,-100})
  check(before==0 and after>20000,'FAR north-edge route absent before and visible after nearest-edge fix')
  check(blue>1000,'current map retains its own atlas beside green neighbor')
  local w={map=west,ox=-2048,oy=0}
  before=draw('west-before',w,westMesh,{px=16,py=64},{280,180,64},{-100,0,64},true)
  after,blue=draw('west-after',w,westMesh,{px=16,py=64},{280,180,64},{-100,0,64})
  check(before==0 and after>20000,'FAR west-edge route absent before and visible after nearest-edge fix')
  check(blue>1000,'west seam current palette stays distinct')
  -- Return view at the same north/south seam after exchanging map origins.
  local back={map=rootMap,ox=0,oy=128}
  local original=rootMesh;rootMesh=northMesh
  after=draw('south-return',back,original,{px=64,py=112},{64,180,-150},{64,0,150})
  rootMesh=original
  check(after>1000,'departed area remains visible in the reverse seam direction')
  write('render-results.json',require('src.link.Json').encode({checks=checks,renderer={g.getRendererInfo()},romUsed=false,rows=rows,
    note='Synthetic ground with actual ChunkMesher geometry, Voxel3D terrain dispatcher, production VoxelScene distance callback; test camera shader'}))
  print('PASS '..checks..' actual GL neighbor checks')
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
