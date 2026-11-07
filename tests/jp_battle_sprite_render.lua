-- Exercise the public trainer-image loader, not just the matte helper.
-- The little outlined coat is authored here; no cartridge artwork is used.
return function(Game,check)
  local g,fs=love.graphics,love.filesystem
  local Battle=require("src.battle.BattleState")
  local Palette=require("src.render.PaletteFX")
  local mode=Palette.mode
  local originalPalettes=Game.data.palettes
  local colors={{245,235,215},{160,190,210},{64,80,120},{16,24,40}}
  Game.data.palettes={palettes={MEWMON=colors}}
  Palette.setMode("gbc")
  local legacy=love.image.newImageData(16,16)
  for y=3,12 do for x=3,12 do
    if x==3 or x==12 or y==3 or y==12 then legacy:setPixel(x,y,0,0,0,1) end
  end end
  -- Its enclosed transparent paper has no surviving white reference pixel.
  for _,dir in ipairs({"assets/generated/qa","save/mod-derived/qa","qa-authored"}) do
    assert(fs.createDirectory(dir));assert(fs.write(dir.."/coat.png",legacy:encode("png")))
  end
  local function read(image)
    g.push("all");g.origin();g.setScissor();g.setShader();g.setStencilTest();g.setDepthMode("always",false)
    local canvas=g.newCanvas(16,16,{dpiscale=1})
    g.setCanvas(canvas);g.clear(0,0,0,0);g.setBlendMode("replace","premultiplied");g.setColor(1,1,1,1)
    g.draw(image);g.setCanvas();local pixels=canvas:newImageData();g.pop();canvas:release()
    return pixels
  end
  for _,dir in ipairs({"assets/generated/qa","save/mod-derived/qa"}) do
    local trainer={pic=dir.."/coat.png"}
    local sprite=Battle.trainerSprite(Game.data,trainer)
    local pixels=read(sprite)
    local r,green,b,a=pixels:getPixel(7,7)
    check(math.abs(r-colors[1][1]/255)<.01 and math.abs(green-colors[1][2]/255)<.01
      and math.abs(b-colors[1][3]/255)<.01 and a==1,dir.." legacy white repaired before trainer palette")
    check(select(4,pixels:getPixel(0,0))==0,dir.." exterior stays transparent")
    local gray=read(Battle.picImage({grayPics=true},sprite))
    local gr,gg,gb,ga=gray:getPixel(7,7)
    check(gr==1 and gg==1 and gb==1 and ga==1,dir.." mono animation retains opaque shade zero")
  end
  local authored=read(Battle.trainerSprite(Game.data,{pic="qa-authored/coat.png"}))
  check(select(4,authored:getPixel(7,7))==0,"authored sprite transparency is not repaired")
  Palette.setMode("redpp") -- the mode in which Gen 1 honors trueColor art
  Battle.invalidate()
  local trueColor=read(Battle.trainerSprite(Game.data,{pic="assets/generated/qa/coat.png",trueColor=true}))
  check(select(4,trueColor:getPixel(7,7))==0,"true-color trainer keeps intentional enclosed transparency")
  Game.data.palettes=originalPalettes;Palette.setMode(mode);Battle.invalidate()
end
