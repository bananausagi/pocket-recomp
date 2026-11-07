local function run()
  local root,out=assert(os.getenv('JP_QA_ROOT')),assert(os.getenv('TERRAIN_QA_OUT'))
  package.path=root..'/?.lua;'..package.path
  local F=require('tests.ledge_terrain_fixture');local f=F.new()
  local g=love.graphics;local M=f.V.require('Mat4');local checks=0
  local function check(v,s)assert(v,s);checks=checks+1;print('PASS '..s)end
  local function write(n,s)local fp=assert(io.open(out..'/'..n,'wb'));fp:write(s);fp:close()end
  local atlas=love.image.newImageData(128,64)
  for y=0,63 do for x=0,127 do
    local tile=math.floor(y/8)*16+math.floor(x/8)
    local r,gg,b=.38,.64,.26
    if tile==55 or tile==39 or tile==13 then r,gg,b=.57,.35,.15
    elseif tile==20 then r,gg,b=.12,.36,.76
    elseif tile==99 then r,gg,b=.65,.65,.67 end
    local k=(x+y)%4==0 and .87 or 1
    atlas:setPixel(x,y,r*k,gg*k,b*k,1)
  end end
  local texture=g.newImage(atlas);texture:setFilter('nearest','nearest')
  local shader=g.newShader([[
    uniform mat4 vp;varying float shade;
    #ifdef VERTEX
    attribute float VertexShade;
    vec4 position(mat4 ignored,vec4 p){shade=VertexShade;return vp*p;}
    #endif
    #ifdef PIXEL
    vec4 effect(vec4 color,Image image,vec2 uv,vec2 sc){return Texel(image,uv)*vec4(shade,shade,shade,1);}
    #endif
  ]])
  local color=g.newCanvas(960,640,{dpiscale=1})
  local depth=g.newCanvas(960,640,{format='depth24',readable=false,dpiscale=1})
  local stats={}
  local function render(name,title,placed,focus,eye)
    local meshes={}
    for _,p in ipairs(placed)do
      local vertices,indices=f.Mesher.geometry(p[1],true)
      for _,v in ipairs(vertices)do v[1]=v[1]+(p[2]or 0);v[3]=v[3]+(p[3]or 0)end
      local mesh=g.newMesh(f.Camera.FORMAT,vertices,'triangles','static');mesh:setVertexMap(indices);mesh:setTexture(texture)
      meshes[#meshes+1]=mesh
    end
    local vp=M.mul(M.mul(M.scale(1,-1,1),M.perspective(.75,960/640,1,3000)),M.lookAt(eye,focus,{0,1,0}))
    g.setCanvas({color,depthstencil=depth});g.clear(.055,.08,.12,1,0,1)
    g.setDepthMode('lequal',true);g.setMeshCullMode('none');g.setBlendMode('replace');g.setColor(1,1,1,1)
    g.setShader(shader);shader:send('vp','row',vp)
    for _,mesh in ipairs(meshes)do g.draw(mesh)end
    g.setShader();g.setDepthMode();g.setBlendMode('alpha')
    g.setColor(1,1,1,1);g.print(title,22,18);g.print('Original synthetic map / actual terrain mesh / height scale 1:1',22,40)
    g.setCanvas()
    local image=color:newImageData();write(name..'.png',image:encode('png'):getString())
    local green,brown=0,0
    for y=60,639 do for x=0,959 do local r,gg,b=image:getPixel(x,y)
      if gg>r*1.3 and gg>b*1.3 then green=green+1 end
      if r>gg*1.3 and gg>b*1.3 then brown=brown+1 end
    end end
    check(green>20000,name..' contains continuous flat ground');check(brown>400,name..' preserves original road-hop tile art')
    for _,mesh in ipairs(meshes)do mesh:release()end
  end
  local function ledge(map,y,x0,x1)for x=x0 or 0,x1 or map.widthCells-1 do map.cells[F.key(x,y)]=55 end end
  local straight=f:map('STRAIGHT',12,16);ledge(straight,9);f:build(straight)
  render('straight-after','jp16: original six-unit road ledge blocks',{{straight}},{96,6,128},{350,180,370})
  local vertices=f.Mesher.geometry(straight,true)
  local raised=false;for _,p in ipairs(vertices)do assert(p[2]==0 or p[2]==6,'unexpected road elevation');raised=raised or p[2]==6 end
  check(raised,'actual GL terrain contains six-unit ledge blocks and level surrounding floor')
  check(f.Scene.groundAt(straight,4,9)==6,'actor and battle floor matches the six-unit road block')
  local stairs=f:map('STAIRS',12,24);ledge(stairs,8);ledge(stairs,16);f:build(stairs)
  render('two-rows-blocks','Multiple road-hop rows restore independent original blocks',{{stairs}},{96,6,192},{365,240,500})
  local mixed=f:map('NORMAL',12,16);ledge(mixed,9);mixed.cells[F.key(3,4)]=99
  for x=7,9 do mixed.cells[F.key(x,4)]=20 end;f:build(mixed)
  render('normal-objects','Original ledge blocks; ordinary wall height and water depth are preserved',{{mixed}},{96,6,128},{350,180,370})
  local dir=root..'/vendor/jp-mods/DRAMALESS_SHAPE/'
  package.loaded['src.render.TileRenderer']={borderBlockFor=function()return false end,defaultAnimatedTiles=function()return {}end}
  package.loaded['src.render.Assets'].imageData=function()error('fixture has no ROM atlas')end
  f.V.data=function(n)return assert(loadfile(dir..'data/'..n..'.lua'))()end
  f.modules.TileShape=assert(loadfile(dir..'lib/TileShape.lua'))(f.V)
  f.modules.Buildings=assert(loadfile(dir..'lib/Buildings.lua'))(f.V)
  local Structures=assert(loadfile(dir..'lib/Structures.lua'))(f.V)
  package.loaded['src.core.Game'].data.field.ledges=f.rules
  straight.walkable={[44]=true};straight.waterTiles={}
  local real=Structures.forMap(straight)
  check(real.terrain and real.terrain.seeds==12,'production Structures classifies imported road-hop rows')
  check(Structures.forMap(straight)==real,'production classification cache is reused')
  check(f.T.height(straight,80,40)==0,'no inferred terrain heightfield is reintroduced')
  local ledge=real.shapeAt[F.key(8,19)]
  check(ledge and ledge.h==6,'production profile and Structures preserve original six-unit ledge height')
  local result={checks=checks,renderer=({g.getRendererInfo()})[1],romUsed=false,solverIterations=0,blockHeight=6,meshCacheRevision=5}
  write('love-results.json',require('src.link.Json').encode(result))
  print('PASS '..checks..' real LOVE block-road checks')
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
