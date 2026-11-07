-- Real GL colors from production terrain/OBJ/battle-image/shader routes.
-- Art is generated four-shade geometry; no ROM or extracted game assets.
local function run()
  local root,out=assert(os.getenv('JP_QA_ROOT')),assert(os.getenv('JP_QA_OUT'))
  package.path=root..'/?.lua;'..package.path
  local g,fs=love.graphics,love.filesystem
  local P=require('src.render.PaletteFX')
  local Version=require('src.core.GameVersion')
  local Assets=require('src.render.Assets')
  local Tile=require('src.render.TileRenderer')
  local Sprite=require('src.render.SpriteRenderer')
  local Battle=require('src.battle.BattleState')
  local Classic=require('src.ui.ClassicPalette')
  local checks,rows=0,{}
  local function check(ok,msg)assert(ok,msg);checks=checks+1;print('PASS '..msg)end
  local function write(name,bytes)local f=assert(io.open(out..'/'..name,'wb'));f:write(bytes);f:close()end
  local function sameRGB(a,b)
    for i=1,3 do if math.abs(a[i]-b[i]/255)>1.1/255 then return false end end
    return true
  end
  local function readImage(image)
    local c=g.newCanvas(image:getDimensions());g.push('all');g.setCanvas(c)
    g.clear(0,0,0,0);g.setBlendMode('replace');g.setShader();g.setColor(1,1,1,1)
    g.draw(image);g.setCanvas();g.pop();local d=c:newImageData();c:release();return d
  end
  local art=love.image.newImageData(128,128)
  art:mapPixel(function(x,y)local s=({1,2/3,1/3,0})[math.floor(x%8/2)+1];return s,s,s,1 end)
  fs.write('jp22-art.png',art:encode('png'))
  local pic=love.image.newImageData(16,16)
  pic:mapPixel(function(x,y)
    local s=({1,2/3,1/3,0})[math.floor(x/4)+1]
    return s,s,s,y==0 and 0 or 1
  end)
  fs.write('jp22-pic.png',pic:encode('png'))
  local src=g.newImage(art);src:setFilter('nearest','nearest')
  local data={pokemon={BULBASAUR={name='SYNTHETIC',types={'GRASS'},spriteFront='jp22-pic.png',spriteBack='jp22-pic.png',
    baseStats={hp=45,attack=49,defense=49,speed=45,special=65}}},palettes=P.gbcPack()}
  local V={require=function(name)
    if name=='BuildBudget' then return {check=function()end,tick=function()end} end
    return {}
  end}
  local Atlas=assert(loadfile(root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/TerrainAtlas.lua'))(V)
  local images={}
  for _,mode in ipairs({'redpp','redpp_soft','redpp'}) do
    Version.set('red_jp');P.setMode(mode);P.setCustomRamp(nil)
    local map={id='SYNTHETIC',def={width=4,height=4,tileset='OVERWORLD'},
      tileset={id='OVERWORLD',image='jp22-art.png',tilesPerRow=16,animatedTiles={},blocks={}}}
    map.renderer=Tile.new(map,data)
    local texture=Atlas.forMap(map,P.pal(data,'ROUTE'))
    local pixels=readImage(texture)
    local groups=P.worldGroupColors(data,'OVERWORLD',map.id)
    local chroma,total=0,0
    for tile=0,255 do
      local group=P.worldGroupAt('OVERWORLD',map.id,tile)
      if group then
        local colors=groups[group+1]
        for shade=1,4 do
          local rgb={pixels:getPixel(tile%16*8+(shade-1)*2,math.floor(tile/16)*8)}
          check(sameRGB(rgb,colors[shade]),mode..' terrain GPU tile '..tile..' shade '..shade)
          chroma=chroma+math.max(rgb[1],rgb[2],rgb[3])-math.min(rgb[1],rgb[2],rgb[3]);total=total+1
        end
      end
    end
    local sprite=Sprite.new({image='jp22-pic.png',source='ROM:SpriteSheetPointerTable[0]',frames=1},'player')
    local sheet=sprite:resolveImage();local sp=readImage(sheet);local sc=P.spriteObp(sprite.def,'player')
    check(sameRGB({sp:getPixel(5,5)},sc[2]),mode..' actor sheet uses same profile')
    check(select(4,sp:getPixel(1,5))==0,mode..' OBJ shade zero stays transparent')
    local battler=Battle.makeBattler(data,{species='BULBASAUR',level=5,hp=20,stats={hp=20,attack=10,defense=10,speed=10,special=10},moves={}},false)
    local bp=readImage(battler.sprite);local bc=P.monPal(data,'BULBASAUR')
    check(sameRGB({bp:getPixel(5,5)},bc[2]),mode..' battle image uses same profile')
    local canvas=g.newCanvas(400,360,{dpiscale=1})
    g.setCanvas(canvas);g.clear(1,1,1,1);g.setColor(1,1,1,1)
    -- A skewed terrain plane samples the exact atlas used by 3D rendering.
    local plane=g.newMesh({{20,185,0,1},{78,36,0,0},{335,36,1,0},{388,185,1,1}},'fan','static')
    plane:setTexture(texture);g.draw(plane)
    g.draw(sheet,44,96,0,4,4);g.draw(battler.sprite,244,92,0,4,4)
    local shader=P.shader();g.setShader(shader)
    for n,name in ipairs({'GREENBAR','YELLOWBAR','REDBAR','LOGO2'}) do
      P.sendColors(shader,P.pal(data,name));g.draw(src,20+(n-1)*92,220,0,.5,.25)
    end
    P.sendColors(shader,P.GRAYS);g.draw(src,20,270,0,2,.25)
    g.setShader();g.setColor(0,0,0,1);g.print(mode,20,320)
    g.setCanvas();local rendered=canvas:newImageData()
    local r,gg,b=rendered:getPixel(20,270);check(r==1 and gg==1 and b==1,mode..' shader paper remains exact white')
    r,gg,b=rendered:getPixel(33,270);check(r==0 and gg==0 and b==0,mode..' shader ink remains exact black')
    local cc=Classic.colors({data=data,save={options={colors=mode}}})
    check(cc[1][1]==1 and cc[1][2]==1 and cc[1][3]==1,mode..' session window remains white')
    local label=mode..'-'..(#rows+1)
    write(label..'.png',rendered:encode('png'):getString())
    rows[#rows+1]={mode=mode,meanChroma=chroma/total,samples=total}
    images[#images+1]=rendered
  end
  check(rows[2].meanChroma<rows[1].meanChroma*.7,'gentle terrain reduces mean chroma by at least 30%')
  check(math.abs(rows[3].meanChroma-rows[1].meanChroma)<1e-8,'switching back restores original vivid atlas')
  local comparison=g.newCanvas(800,360,{dpiscale=1});g.setCanvas(comparison);g.clear(1,1,1,1);g.setColor(1,1,1,1)
  g.draw(g.newImage(images[1]));g.draw(g.newImage(images[2]),400,0);g.setCanvas()
  write('comparison.png',comparison:newImageData():encode('png'):getString())
  local name,version,vendor,device=g.getRendererInfo()
  write('result.json',require('src.link.Json').encode({checks=checks,rows=rows,renderer={name,version,vendor,device},art='synthetic four-shade geometry only'}))
  print('jp22 color GL: '..checks..' checks passed')
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err) end
  love.event.quit(ok and 0 or 1)
end
