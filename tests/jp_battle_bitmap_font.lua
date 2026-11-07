-- Test-only cartridge-shaped pages built from the redistributable Misaki bitmap.
return function(data)
  local g,fs=love.graphics,love.filesystem
  local Json=require('src.link.Json')
  local manifest=Json.decode(fs.read('tools/rom_manifest_red_jp.json'))
  local map=Json.decode(fs.read('assets/fonts/misaki/glyphs.json'))
  local atlas=g.newImage('assets/fonts/misaki/misaki8x8.png');atlas:setFilter('nearest','nearest')
  local function fontPage(base,count,path)
    local canvas=g.newCanvas(128,count/16*8,{dpiscale=1})
    g.setCanvas(canvas);g.clear(0,0,0,0);g.setColor(0,0,0,1)
    local drawn={}
    local authored={[0xE4]=true,[0xE5]=true,[0xEC]=true,[0xED]=true,[0xEE]=true}
    for _,e in ipairs(manifest.fontCharmap)do
      if e.code>=base and e.code<base+count and map[e.seq] and not drawn[e.code] and not authored[e.code] then
        drawn[e.code]=true
        local i,n=map[e.seq],e.code-base
        g.draw(atlas,g.newQuad(i%128*8,math.floor(i/128)*8,8,8,atlas:getDimensions()),n%16*8,math.floor(n/16)*8)
      end
    end
    -- A cartridge page stores one base glyph per code. Voiced kana are
    -- composed by Font with a separate mark in the lower part of the tile
    -- above the baseline; an ordinary Unicode spacing mark sits too high.
    for _,value in ipairs({0xE4,0xE5})do
      if value>=base and value<base+count then
        local n=value-base;local x,y=n%16*8,math.floor(n/16)*8
        if value==0xE5 then
          for _,p in ipairs({{3,5},{4,6},{6,5},{7,6}})do g.rectangle('fill',x+p[1],y+p[2],1,1)end
        else
          for _,p in ipairs({{5,4},{4,5},{6,5},{5,6}})do g.rectangle('fill',x+p[1],y+p[2],1,1)end
        end
      end
    end
    -- Independently drawn hardware cursor slots for the selection regression.
    for _,code in ipairs({0xEC,0xED,0xEE})do
      if code>=base and code<base+count then
        local n=code-base;local x,y=n%16*8,math.floor(n/16)*8
        for row=0,5 do g.rectangle('fill',x,y+row,math.min(row+1,6-row),1)end
      end
    end
    g.setCanvas();fs.createDirectory('fixture');fs.write(path,canvas:newImageData():encode('png'));canvas:release()
  end
  fontPage(0x80,128,'fixture/font.png');fontPage(0x60,32,'fixture/extra.png')
  data.font={language='ja',image='fixture/font.png',imageExtra='fixture/extra.png',mainBase=0x80,extraBase=0x60,charmap=manifest.fontCharmap,composites=manifest.fontComposites}
  require('src.render.Font').load(data)
end
