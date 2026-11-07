local function run()
  local root,out=assert(os.getenv("JP_QA_ROOT")),assert(os.getenv("JP_QA_OUT"))
  package.path=root.."/?.lua;"..root.."/?/init.lua;"..package.path
  local g,fs=love.graphics,love.filesystem
  local UI=require("src.ui.ClassicUI")
  local Json=require("src.link.Json")
  local checks=0
  local function check(ok,label)assert(ok,label);checks=checks+1;print("PASS "..label)end
  local function write(name,bytes)local f=assert(io.open(out.."/"..name,"wb"));f:write(bytes);f:close()end
  local function screenshot(canvas,name)g.setCanvas();write(name..".png",canvas:newImageData():encode("png"):getString())end
  check(UI.width("がめん MOD")==7*8,"Japanese/Latin share eight-pixel advance")
  check(UI.clip("あいうえお",32)=="あい..","clipping never cuts UTF-8")
  local lines=UI.wrap("abcdef\nがぎぐげご",24)
  check(table.concat(lines,"|")=="abc|def|がぎぐ|げご","bitmap wrapping keeps glyph boundaries")
  local atlas=love.image.newImageData("assets/fonts/misaki/misaki8x8.png")
  local binary=true
  for y=0,atlas:getHeight()-1 do for x=0,atlas:getWidth()-1 do
    local r,b,c,a=atlas:getPixel(x,y)
    if a~=0 and a~=1 then binary=false end
    if a==1 and (r~=1 or b~=1 or c~=1)then binary=false end
  end end
  check(binary,"font atlas has only exact binary bitmap pixels")
  local function paint(game,options,label)
    local target=g.newCanvas(g.getDimensions());g.setCanvas(target);g.clear(0,0,0,1)
    local layout=UI.begin(game,options)
    UI.box(0,0,20,18)
    UI.text("ポケモンと いっしょに",8,16)
    UI.text("つづきから",24,40);UI.cursor(8,40)
    UI.text("はじめから",24,56)
    UI.text("がめんの おおきさ",16,88)
    UI.text("MOD 123 abc",16,104)
    UI.text("もどる",16,128)
    UI.finish()
    check(g.getCanvas()==target,label.." restores caller canvas")
    screenshot(target,label)
    local x,y,inside=UI.hit(layout,layout.x+42*layout.sx,layout.y+57*layout.sy)
    check(inside and math.abs(x-42)<1e-6 and math.abs(y-57)<1e-6,label.." hit coordinates invert canvas placement")
    return layout,target:newImageData():getString()
  end
  for _,size in ipairs({{320,480},{480,800},{800,480},{972,1536}})do
    love.window.setMode(size[1],size[2],{vsync=0})
    local label="misaki-"..size[1].."x"..size[2]
    local layout=paint(nil,{},label)
    check(layout.font=="bitmap",label.." pre-ROM uses native bitmap atlas")
    check(layout.scale%1==0 and layout.sx==layout.sy,label.." square native pixels")
  end
  -- A synthetic, independently drawn cache verifies version isolation and
  -- tile identity. It is deliberately not extracted from a retail ROM.
  local manifest=Json.decode(fs.read("tools/rom_manifest_red_jp.json"))
  local map=Json.decode(fs.read("assets/fonts/misaki/glyphs.json"))
  local png=g.newImage("assets/fonts/misaki/misaki8x8.png");png:setFilter("nearest","nearest")
  local function makeFont(base,count,path)
    local c=g.newCanvas(128,count/16*8,{dpiscale=1});g.setCanvas(c);g.clear(0,0,0,0)
    g.setColor(0,0,0,1)
    for _,entry in ipairs(manifest.fontCharmap)do
      if entry.code>=base and entry.code<base+count and map[entry.seq]then
        local i,n=map[entry.seq],entry.code-base
        local q=g.newQuad(i%128*8,math.floor(i/128)*8,8,8,png:getDimensions())
        g.draw(png,q,n%16*8,math.floor(n/16)*8)
      end
    end
    g.setCanvas();fs.createDirectory(path:match("^(.*)/"));fs.write(path,c:newImageData():encode("png"))
  end
  makeFont(0x80,128,"red_jp/assets/generated/fonts/font.png")
  makeFont(0x60,32,"red_jp/assets/generated/fonts/font_extra.png")
  fs.write("red_jp/rom-cache.complete","synthetic-fixture-jp8")
  local CacheFs=require("src.import.CacheFs")
  CacheFs.prefix="unrelated/"
  require("src.core.GameVersion").set("red")
  love.window.setMode(480,800,{vsync=0})
  local cached,cachedPixels=paint(nil,{version="red_jp"},"private-cache-font")
  check(cached.font=="cache","imported home uses its version-qualified bitmap")
  check(require("src.core.GameVersion").get()=="red","launcher font does not change active game")
  check(CacheFs.prefix=="unrelated/","launcher font never changes cache prefix")
  local Font=require("src.render.Font")
  local data={font={language="ja",image="red_jp/assets/generated/fonts/font.png",
    imageExtra="red_jp/assets/generated/fonts/font_extra.png",mainBase=0x80,extraBase=0x60,
    charmap=manifest.fontCharmap,composites=manifest.fontComposites}}
  Font.load(data)
  local count,original=0,Font.drawCode
  Font.drawCode=function(...)count=count+1;return original(...)end
  local gameLayout,gamePixels=paint({data=data},{},"game-font")
  Font.drawCode=original
  check(gameLayout.font=="game" and count>50,"in-game text and frame use actual Font tile renderer")
  check(cachedPixels==gamePixels,"imported home and game render the same font/frame pixels")
  require("tests.classic_ui_love.status_labels")(data,check,write)
  require("tests.classic_ui_love.machine_names")(data,check,write)
  require("tests.classic_ui_love.menus")(data,check,write)
  require("src.render.Assets").releaseSession()
  check(paint(nil,{version="red_jp"},"cache-after-release").font=="cache","private font remains valid after session asset release")
  fs.remove("red_jp/rom-cache.complete")
  check(paint(nil,{version="red_jp"},"cache-removed").font=="bitmap","removed cache falls back to safe bundled font")
  -- Different per-axis DPI ratios still produce square physical pixels.
  local originalDimensions=g.getPixelDimensions
  g.getPixelDimensions=function()return 720,1600 end
  local layout=UI.layout({x=0,y=0,w=480,h=800})
  check(layout.sx*1.5==layout.scale and layout.sy*2==layout.scale,"anisotropic DPI uses one common physical pixel scale")
  g.getPixelDimensions=originalDimensions
  require("tests.classic_ui_love.palette")(UI,check,write)
  write("results.json",Json.encode({checks=checks,romUsed=false}))
  print(checks.." CLASSIC UI CHECKS PASSED")
end
function love.load()
  local ok,err=xpcall(run,debug.traceback);love.graphics.setCanvas()
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
