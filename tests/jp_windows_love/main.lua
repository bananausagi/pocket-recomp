-- Real GL regression for the user's overlapping report/menu/dialogue view.
-- Only repository fixture data and an independently rasterized font are used.
local function run()
  local root, output = assert(os.getenv("JP_QA_ROOT")), assert(os.getenv("JP_QA_OUT"))
  package.path = root.."/?.lua;"..root.."/?/init.lua;"..package.path
  local g, fs = love.graphics, love.filesystem
  g.setDefaultFilter("nearest", "nearest")
  local checks = 0
  local function check(value, message)
    assert(value, message); checks = checks + 1; print("PASS "..message)
  end
  local function write(name, bytes)
    local file = assert(io.open(output.."/"..name, "wb"))
    file:write(bytes); file:close()
  end
  local Json = require("src.link.Json")
  local Font = require("src.render.Font")
  local manifest = assert(Json.decode(fs.read("tools/rom_manifest_red_jp.json")))
  local sheet = g.newCanvas(128, 128, { dpiscale = 1 })
  g.setCanvas(sheet); g.clear(0, 0, 0, 0)
  local kana = g.newFont(Font.PLAINPIXEL, 10, "mono", 1)
  g.setFont(kana); g.setColor(0, 0, 0, 1)
  local tiles = {}
  for _, entry in ipairs(manifest.fontCharmap) do
    tiles[#tiles+1] = entry.seq
    if entry.code < 256 then
      local x, y = entry.code % 16 * 8, math.floor(entry.code / 16) * 8
      g.setScissor(x, y, 8, 8); g.print(entry.seq, x, y + 7 - kana:getBaseline())
    end
  end
  -- Hand-drawn test border/voicing tiles; no cartridge imagery.
  local function cell(code, draw)
    local x,y=code%16*8,math.floor(code/16)*8
    g.setScissor(x,y,8,8); g.setBlendMode("replace"); g.setColor(0,0,0,0)
    g.rectangle("fill",x,y,8,8); g.setBlendMode("alpha"); g.setColor(0,0,0,1)
    draw(x,y);g.setScissor()
  end
  cell(0x7a,function(x,y)g.rectangle("fill",x,y+3,8,1)end)
  cell(0x7c,function(x,y)g.rectangle("fill",x+3,y,1,8)end)
  for _,c in ipairs({0x79,0x7b,0x7d,0x7e}) do
    cell(c,function(x,y)g.rectangle("fill",x,y+3,8,1);g.rectangle("fill",x+3,y,1,8)end)
  end
  cell(229,function(x,y)g.rectangle("fill",x+4,y+5,1,2);g.rectangle("fill",x+6,y+5,1,2)end)
  cell(228,function(x,y)g.rectangle("line",x+4,y+4,2,2)end)
  g.setScissor(); g.setCanvas()
  fs.write("fixture-font.png", sheet:newImageData():encode("png"))
  local data = require("tests.fixture_data").load()
  require("src.core.GameVersion").set("red_jp")
  require("src.core.Data").seedDefaults(data, "red_jp")
  data.constants.language = "ja"
  data.font = { language="ja", image="fixture-font.png", mainBase=0,
    charmap=manifest.fontCharmap, composites=manifest.fontComposites,
    ttf={size=15, tiles=tiles} }
  Font.load(data)
  require("src.core.Strings").load(data)
  require("src.ui.Theme").load(data)
  local Renderer = require("src.render.Renderer")
  Renderer:init()
  local Stack = require("src.core.StateStack"); Stack:init()
  local Game = require("src.core.Game")
  Game.data, Game.renderer, Game.stack = data, Renderer, Stack
  Game.save = {version="red_jp",options={jpDialogScale=0.75,uiLayout="centered"},
    player={name="レッド"},flags={},party={},pokedex={owned={}},playTime=780}
  Game.input = {wasPressed=function()return false end}
  if os.getenv("JP_QA_BATTLE")=="1" then
    require("tests.jp_battle_scale_render")(Game,Renderer,check,write)
    write("results.json",Json.encode({checks=checks,romUsed=false}))
    print(checks.." REAL BATTLE WINDOW SCALE CHECKS PASSED")
    return
  end
  if os.getenv("JP_QA_STARTUP")=="1" then
    require("tests.jp_startup_render")(Game,Renderer,check,write)
    write("results.json",Json.encode({checks=checks,romUsed=false}))
    print(checks.." REAL STARTUP MENU CHECKS PASSED")
    return
  end
  local Strings = require("src.core.Strings")
  local menu = require("src.ui.StartMenu").new(Game)
  Stack:push(menu)
  for _, item in ipairs(menu.items) do
    if item.label == Strings("SAVE") then item.onSelect(); break end
  end
  check(#Stack.states == 2, "real START menu opens its report panel")
  Renderer:beginFrame(true); Stack:draw(); g.setCanvas()
  local reportOnly = Renderer.canvas:newImageData()
  Stack:push(require("src.render.TextBox").new(Game,
    Strings("Would you like to\nSAVE the game?"), nil, {instant=true}))
  Stack:push(require("src.ui.ChoiceBox").new(Game, function()end,
    require("src.ui.Theme").saveBox))
  local Runtime = require("src.mods.Runtime")
  Runtime.install(require("src.mods.Events").new(), require("src.mods.Hooks").new())
  Runtime.hooks:wrap("render.viewport", function(next, ctx)
    local r=next(ctx); r.capture=true; return r
  end, 0, "window-fixture")
  local Viewport = require("src.render.GameViewport")
  local Position = require("src.core.ScreenPosition")
  local report = {}
  for _, size in ipairs({{480,800},{800,480},{972,1536}}) do
    love.window.setMode(size[1], size[2], {vsync=0})
    for _, position in ipairs({"center","upper","top"}) do
      Position.setMode(position)
      for _, factor in ipairs({0.5,0.75,1}) do
        local label = size[1].."x"..size[2].."-"..position.."-"..factor
        Viewport.begin(1)
        Renderer.uiCentered, Renderer.uiAnchorHold = true, true
        Renderer.uiFill, Renderer.dialogScale = false, factor
        Renderer:beginFrame(true); Stack:draw(); g.setCanvas()
        local source = Renderer.canvas:newImageData()
        if factor == 0.75 and position == "center" then
          local timeVisible=true
          for y=56,71 do for x=56,79 do
            local a,b,c=reportOnly:getPixel(x,y)
            local d,e,f=source:getPixel(x,y)
            if a~=d or b~=e or c~=f then timeVisible=false end
          end end
          check(timeVisible,label.." full TIME label survives YES/NO overlay")
        end
        check(not Renderer.uiAnchors or #Renderer.uiAnchors == 0,
          label.." overlapping windows remain one composition")
        local r = Renderer:frameRects()
        Viewport.setTarget(); g.clear(0.16,0.35,0.24,1)
        Renderer:endFrame()
        local canvas = Viewport.target(); g.setCanvas()
        local result = canvas:newImageData()
        local same = true
        -- Every opaque UI pixel must survive at the same scale. This covers
        -- actual report characters in the area formerly removed by YES/NO.
        for y = 0, 143 do for x = 0, 159 do
          local sr,sg,sb,sa = source:getPixel(x,y)
          if sa > 0.99 then
            local px=math.floor(r.uox+(x+0.5)*r.Ux)
            local py=math.floor(r.uoy+(y+0.5)*r.Uy)
            local rr,rg,rb = result:getPixel(px,py)
            if math.abs(sr-rr)>0.02 or math.abs(sg-rg)>0.02 or math.abs(sb-rb)>0.02 then same=false end
          end
        end end
        check(same, label.." report/menu/dialogue pixels keep equal size with no missing rectangle")
        report[#report+1] = {size=size,position=position,factor=factor,uiPixels=r.Up,worldPixels=r.Sp}
        if factor == 0.75 then
          write("report-"..label..".png", result:encode("png"):getString())
        end
        check(r.Sp==Renderer:fitScale(), label.." world scale remains independent")
      end
    end
  end
  Position.setMode("center")
  love.window.setMode(480,800,{vsync=0}); Viewport.begin(1)
  Renderer.dialogScale=0.75; Renderer:beginFrame(false)
  require("src.ui.OptionRows").draw(Game, {
    {label=Strings("WINDOW SIZE"),value=function()return Strings("COMPACT")end},
    {label=Strings("SCREEN POS"),value=function()return Strings("CENTER")end},
    {label=Strings("DOT MATRIX"),value=function()return Strings("LIGHT")end},
  }, 1, 0, Strings("CANCEL"))
  Renderer:endFrame(); local canvas=Viewport.target(); g.setCanvas()
  write("settings-480x800.png",canvas:newImageData():encode("png"):getString())
  write("results.json",Json.encode({checks=checks,cases=report,romUsed=false}))
  print(checks.." REAL WINDOW COMPOSITION CHECKS PASSED")
end

function love.load()
  local ok, err=xpcall(run, debug.traceback)
  love.graphics.setCanvas()
  if not ok then print(err); love.event.quit(1) else love.event.quit(0) end
end
