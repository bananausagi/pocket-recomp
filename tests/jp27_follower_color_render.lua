-- Actual color and native-direction integration over the shared icon tests.
return function(Game,V,check,write)
  require('tests.jp26_follower_icon_render')(Game,V,check,write)
  local g=love.graphics
  local F=require('src.render.JapaneseFollowerSprite')
  local P=require('src.render.PaletteFX')
  local A=require('src.render.Assets')
  local Runtime=require('src.mods.Runtime')
  local Scene,V3,Voxel=V.require('VoxelScene'),V.require('Voxel3D'),V.require('VoxelState')
  local function pixels(image)
    local c=g.newCanvas(image:getWidth(),image:getHeight(),{dpiscale=1})
    g.setCanvas(c);g.clear(0,0,0,0);g.setShader();g.setScissor();g.origin()
    g.setBlendMode('replace');g.setColor(1,1,1,1);g.draw(image);g.setCanvas()
    local p=c:newImageData();c:release();g.setBlendMode('alpha');return p
  end
  local function expectRGB(data,x,y,c,message)
    local r,gg,b,a=data:getPixel(x,y)
    check(math.abs(r-c[1]/255)<.006 and math.abs(gg-c[2]/255)<.006
      and math.abs(b-c[3]/255)<.006 and a>.99,message)
  end
  local palettes={
    FIRE={{255,255,255},{248,144,64},{168,48,16},{0,0,0}},
    WATER={{255,255,255},{64,192,248},{32,88,168},{0,0,0}},
    GRASS={{255,255,255},{136,216,96},{48,112,56},{0,0,0}},
  }
  Game.data.palettes=Game.data.palettes or{palettes={},pokemon={}}
  Game.data.palettes.palettes=Game.data.palettes.palettes or{}
  Game.data.palettes.pokemon=Game.data.palettes.pokemon or{}
  local monsters,sprites={},{}
  for name,colors in pairs(palettes) do
    local id='JP27_'..name
    local palette='JP27_PALETTE_'..name
    Game.data.pokemon[id]={dex=1,palette=palette,spriteFront='MUST_NOT_LOAD_BATTLE.png'}
    Game.data.palettes.palettes[palette]=colors
    Game.data.icons.bySpecies[id]='MON'
    monsters[name]={species=id,hp=20,stats={hp=20}}
    sprites[name]=assert(F.new(Game.data,monsters[name]))
  end
  P.setMode('redpp')
  local colorComparisons=0
  for name,sprite in pairs(sprites) do
    local colors=palettes[name]
    local image=pixels(sprite:resolveImage())
    -- MON rest uses native row 3. The synthetic source deliberately has
    -- a light-body index 1 and dark-body index 2, before the OBP collapse.
    expectRGB(image,6,9,colors[2],name..' light body uses the species main color')
    expectRGB(image,6,6,colors[3],name..' dark body uses the species secondary color')
    expectRGB(image,3,7,colors[4],name..' native outline stays the palette ink')
    check(select(4,image:getPixel(0,0))==0,name..' species color leaves OBJ background transparent')
    check(sprite.frameCount==6 and sprite.def.jpFollowerDirections,name..' keeps original back and side frames')
    colorComparisons=colorComparisons+2
  end
  local mono=sprites.WATER
  P.setMode('og')
  local old=pixels(mono:resolveImage())
  expectRGB(old,6,9,{255,255,255},'GB mode keeps original OBP white body')
  expectRGB(old,6,6,{170,170,170},'GB mode keeps original OBP gray body')
  P.setMode('classic')
  expectRGB(pixels(mono:resolveImage()),6,9,P.CLASSIC[1],'classic GB mode retains the green display palette')
  P.setMode('redpp_soft')
  local soft=P.displayColors(palettes.WATER,'redpp_soft')
  local softImage=pixels(mono:resolveImage())
  expectRGB(softImage,6,9,soft[2],'soft full color applies the existing display profile exactly once')
  check((math.max(unpack(soft[2]))-math.min(unpack(soft[2])))
    <(math.max(unpack(palettes.WATER[2]))-math.min(unpack(palettes.WATER[2]))),
    'soft full color reduces the species color spread')
  P.setMode('redpp')
  expectRGB(pixels(mono:resolveImage()),6,9,palettes.WATER[2],'switching back to full color restores species color immediately')

  -- Compare real field rendering with the exact native unmirrored back /
  -- left source rows. Right is the same row with the engine's X mirror.
  local function field(sprite,facing,phase)
    local c=g.newCanvas(24,24,{dpiscale=1})
    g.setCanvas(c);g.clear(0,0,0,0);g.setShader();g.setColor(1,1,1,1)
    sprite:draw(4,8,0,0,facing,phase,false);g.setCanvas()
    local data=c:newImageData();c:release();return data
  end
  local raw=A.imageData('jp26-icon-sheet.png')
  local directionComparisons=0
  local order={'down','up','left','right'}
  local gallery=g.newCanvas(4*144,3*192,{dpiscale=1});g.setCanvas(gallery);g.clear(.82,.90,.82,1);g.setCanvas()
  for row,name in ipairs({'FIRE','WATER','GRASS'}) do
    local sprite=sprites[name]
    for col,facing in ipairs(order) do
      for phase=0,1 do
        local actual=field(sprite,facing,phase)
        if facing~='down' then
          local sourceFrame=(facing=='up'and 1 or 2)+(phase==1 and 3 or 0)
          local equal=true
          for y=0,15 do for x=0,15 do
            local sx=facing=='right'and 15-x or x
            local r,_,_,a=raw:getPixel(sx,sourceFrame*16+y)
            local ar,ag,ab,aa=actual:getPixel(x+4,y+4)
            if r>.83 or a==0 then equal=equal and aa==0
            else
              local c=palettes[name][r>.5 and 2 or r>.17 and 3 or 4]
              equal=equal and math.abs(ar-c[1]/255)<.006 and math.abs(ag-c[2]/255)<.006
                and math.abs(ab-c[3]/255)<.006 and aa>.99
            end
          end end
          check(equal,name..' '..facing..' pose '..phase..' exactly uses the original native row')
          directionComparisons=directionComparisons+1
        end
        local picture=g.newImage(actual);picture:setFilter('nearest','nearest')
        g.setCanvas(gallery);g.setColor(1,1,1,1)
        g.draw(picture,(col-1)*144,(row-1)*192+phase*96,0,4,4);g.setCanvas();picture:release()
      end
    end
  end
  write('species-color-directions.png',gallery:newImageData():encode('png'):getString());gallery:release();raw:release()

  -- An externally replaced six-frame-tall file is still a replacement,
  -- not proof of native facings. Also preserve already-colored icon art.
  local target=monsters.FIRE
  Runtime.hooks:wrap('pokemon.icon',function(next,path,ctx)
    if ctx.mon==target then return'jp26-icon-single.png'end
    return next(path,ctx)
  end,0,'jp27-follower-hook')
  local sprite=sprites.FIRE
  sprite:resolveImage()
  check(not sprite.def.jpFollowerDirections and sprite.frameCount==2,'replacement icon without native directions keeps two front poses')
  Runtime.hooks:removeOwner('jp27-follower-hook')
  love.filesystem.write('jp27-tall-replacement.png',love.filesystem.read('jp26-icon-sheet.png'))
  Runtime.hooks:wrap('pokemon.icon',function(next,path,ctx)
    if ctx.mon==target then return'jp27-tall-replacement.png'end
    return next(path,ctx)
  end,0,'jp27-follower-hook')
  sprite:resolveImage()
  check(not sprite.def.jpFollowerDirections,'arbitrary tall icon replacement never gains inferred walking frames')
  Runtime.hooks:removeOwner('jp27-follower-hook')
  Runtime.hooks:wrap('pokemon.icon',function(next,path,ctx)
    if ctx.mon==target then ctx.trueColor=true;return'jp26-icon-mod.png'end
    return next(path,ctx)
  end,0,'jp27-follower-hook')
  expectRGB(pixels(sprite:resolveImage()),6,9,{64,166,230},'existing true-color icon takes precedence over fire species palette')
  Runtime.hooks:removeOwner('jp27-follower-hook');sprite:resolveImage()
  check(sprite.def.jpFollowerDirections,'removing icon replacement restores native directions without restart')

  -- Visible and sun passes resolve poses in the same VoxelScene selector.
  -- Capture the actual mesh used by drawEntity, not a hand-drawn mock-up.
  Voxel.angle=math.rad(35);Voxel.level=3
  local original=V3.draw;local meshes={}
  for _,facing in ipairs(order) do
    local expectedTexture=mono:resolveImage()
    expectRGB(pixels(expectedTexture),6,9,palettes.WATER[2],'3D '..facing..' source uses the water species palette')
    assert(V3.beginScene(480,360,40,48,96,72,{.2,.4,.6,1}));V3.lighting(false)
    V3.draw=function(mesh,texture,...)
      meshes[facing]=mesh
      check(texture==expectedTexture,'3D '..facing..' draws the same species-colored texture')
      return original(mesh,texture,...)
    end
    check(Scene.drawEntity(mono,32,48,facing,1,false,0,nil,0),'actual 3D native icon draws '..facing)
    local canvas=V3.endScene();g.setCanvas()
    write('voxel-color-'..facing..'.png',canvas:newImageData():encode('png'):getString())
  end
  V3.draw=original
  check(meshes.down~=meshes.up and meshes.up~=meshes.left and meshes.left==meshes.right,
    '3D uses separate front/back/left native cards and the same mirrored right card')
  local reads,uploads,canvases=0,0,0
  local oldRead,oldImage,oldCanvas=A.imageData,g.newImage,g.newCanvas
  mono:resolveImage()
  A.imageData=function(...)reads=reads+1;return oldRead(...)end
  g.newImage=function(...)uploads=uploads+1;return oldImage(...)end
  g.newCanvas=function(...)canvases=canvases+1;return oldCanvas(...)end
  for i=1,120 do mono:poseOffset(i%2);mono:resolveImage();mono:selectFrame(order[i%4+1],i%2)end
  A.imageData,g.newImage,g.newCanvas=oldRead,oldImage,oldCanvas
  check(reads==0 and uploads==0 and canvases==0,'120 colored walking frames allocate/read no images or canvases')
  for _,s in pairs(sprites)do s:release()end
  P.setMode('og')
  write('color-results.json',assert(require('src.link.Json').encode({actualLoveGL=true,physicalAndroid=false,
    sourceArt='native-layout synthetic icon sheets, production uses imported ROM party icons',
    colorComparisons=colorComparisons,nativeDirectionComparisons=directionComparisons,
    fullColorSpeciesPalette=true,softProfileOnce=true,trueColorOverridePreserved=true,
    warmImageReads=reads,warmGPUUploads=uploads,warmCanvases=canvases})))
end
