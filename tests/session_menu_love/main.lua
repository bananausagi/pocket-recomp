-- Genuine bitmap UI, physical hit boxes and paging. Handwritten save model;
-- no ROM data and no substitute TTF/pixel-font mock is used by this fixture.
local function run()
  local root, out = assert(os.getenv("SESSION_QA_ROOT")), assert(os.getenv("SESSION_QA_OUT"))
  package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
  local Menu = require("src.ui.SessionMenu")
  local Classic = require("src.ui.ClassicUI")
  local SaveData = require("src.core.SaveData")
  require("src.core.GameVersion").set("red_jp")
  local count = 0
  local function check(ok, label) assert(ok, label); count = count + 1; print("PASS " .. label) end
  local ow = { player = {} }
  local g = { overworld = ow, stack = { top = function() return ow end },
    save = { options = SaveData.defaultOptions() }, quickSaveAllowed = function() return true end,
    applyOptions = function() end, writeOptions = function() return true end,
    writeSave = function() return true end, closeSessionMenu = function(self) self.closed = true end }
  local m = Menu.new(g)
  local scenery=false
  local function drawScenery(w,h)
    local lg=love.graphics
    lg.clear(0.24,0.47,0.28,1)
    for y=0,h,32 do for x=0,w,32 do
      lg.setColor((x/32+y/32)%2==0 and 0.28 or 0.25,0.50,0.30,1)
      lg.rectangle("fill",x+2,y+2,28,28)
    end end
    lg.setColor(0.64,0.57,0.40,1);lg.rectangle("fill",w*0.16,0,w*0.10,h)
    lg.rectangle("fill",0,h*0.62,w,h*0.07)
    lg.setColor(0.19,0.38,0.60,1);lg.rectangle("fill",w*0.69,h*0.10,w*0.23,h*0.36)
    for y=40,h-40,128 do
      lg.setColor(0.36,0.29,0.19,1);lg.rectangle("fill",w*0.45,y+22,12,22)
      lg.setColor(0.12,0.29,0.15,1);lg.rectangle("fill",w*0.45-15,y-3,42,34)
    end
    Classic.bitmapText("ROM-FREE TEST SCENE",16,h-32,2,{1,1,1,1})
    local touch=g.touchControls
    if touch then touch:draw() end
  end
  local function render(w, h, page, filename, section, notice)
    love.window.setMode(w, h, { resizable = true })
    m:open(page, section); m.notice = notice
    local c = love.graphics.newCanvas(w, h)
    love.graphics.setCanvas(c); love.graphics.clear(0.25, 0.25, 0.25, 1)
    if scenery then drawScenery(w,h) end
    m:draw(); love.graphics.setCanvas()
    local l, v = m.geometry, m.geometry.viewport
    local bounds = page == "main" and not notice
      and {48,8,104,80} or {0,0,v.width,v.height}
    check(v.x + bounds[1]*v.sx >= 0 and v.y + bounds[2]*v.sy >= 0
      and v.x + (bounds[1]+bounds[3])*v.sx <= w
      and v.y + (bounds[2]+bounds[4])*v.sy <= h,
      "visible menu stays inside " .. w .. "x" .. h .. " " .. page)
    check(v.scale == math.floor(v.scale), "bitmap uses integer physical pixels " .. page)
    check(v.w / v.sx == v.width and v.h / v.sy == v.height, "logical canvas matches panel " .. page)
    if not l.compact then
      check(v.width>160, "settings and confirmations use the available width")
      check(math.abs(v.y+v.h/2-(v.rect.y+v.rect.h/2))<=1, "panel is centered above touch controls")
    end
    for _, target in ipairs(l.hits) do
      check(target.x >= 0 and target.y >= 0 and target.x + target.w <= v.width and target.y + target.h <= v.height,
        "logical touch target remains in canvas " .. target.id)
      if not l.compact then check(target.h>=12, "controller row keeps a complete hit area "..target.id) end
    end
    if filename then
      local data=c:newImageData()
      if scenery then
        local r,green=data:getPixel(5,math.floor(h*0.2))
        check(green>r*1.2,"terrain color remains visible outside floating window")
      end
      local f = assert(io.open(out .. "/" .. filename, "wb")); f:write(data:encode("png"):getString()); f:close()
    end
    c:release()
  end
  local function native(rect)
    local v = m.geometry.viewport
    return v.x + (rect.x + rect.w / 2) * v.sx, v.y + (rect.y + rect.h / 2) * v.sy
  end
  local function hit(id)
    for _, target in ipairs(m:layout().hits) do if target.id == id then return target end end
    error("missing logical touch target: " .. id)
  end
  check(Menu.drawButton == nil and Menu.buttonContains == nil, "persistent menu chip and hotspot are absent")
  for _, size in ipairs({ { 320, 480 }, { 480, 800 }, { 800, 480 }, { 1024, 768 } }) do
    local w, h = size[1], size[2]
    render(w, h, "main", "session-main-" .. w .. "x" .. h .. ".png")
  end
  local Touch = require("src.core.TouchControls")
  Touch:init()
  local visible = Touch.visible
  Touch.visible = function() return true end
  g.touchControls = Touch
  g.save.options.jpDialogScale = 0.5
  render(1536, 1160, "main", "session-main-fold.png")
  local frame = m.geometry.viewport
  check(frame.x + 100*frame.sx > 1536/2, "pause menu occupies the right side of the playfield")
  check(frame.y + 88*frame.sy < Touch:layout().dpad.cy - Touch:layout().dpad.w/2,
    "pause commands do not cover the directional pad")
  render(1536, 1160, "settings", "session-settings-fold.png")
  check(m.geometry.viewport.w>1536*0.8 and m.geometry.viewport.w<1536*.97,
    "category window uses readable columns and leaves terrain visible")
  scenery=true
  Touch.active=true;Touch.enabled=true;Touch:setPreview(true);Touch.sessionMenuActive=true
  render(1536,1160,"settings","session-settings-world-fold.png")
  render(1536,1160,"settings-detail","session-display-world-fold.png",2)
  g.save.options.jpDialogScale=1
  render(480,800,"settings-detail","session-display-world-portrait.png",2)
  render(960,640,"settings-detail","session-display-world-3x2.png",2)
  local oldSafe=love.window.getSafeArea
  love.window.getSafeArea=function()return 24,32,752,424 end
  render(800,480,"settings-detail","session-display-world-insets.png",2)
  local iv=m.geometry.viewport
  check(iv.x>=24 and iv.y>=32 and iv.x+iv.w<=776 and iv.y+iv.h<=456,
    "floating window respects notch and gesture insets")
  love.window.getSafeArea=oldSafe
  scenery=false
  render(480, 800, "settings-detail", "session-display-touch-480x800.png", 2)
  Touch.visible = visible
  g.save.options.jpDialogScale = 1
  render(480, 800, "home", "session-home-480x800.png")
  render(320, 480, "home", "session-home-320x480.png")
  render(480, 800, "settings", "session-settings-480x800.png")
  render(480, 800, "settings-detail", "session-display-480x800.png", 2)
  render(320, 480, "settings-detail", "session-display-320x480.png", 2)
  render(800, 480, "settings-detail", "session-display-800x480.png", 2)
  check(m.geometry.wide,"landscape settings put names and values on one row")
  render(320, 480, "home", "session-save-failure-320x480.png", nil,
    "レポートを\nかけませんでした！\nゲームは つづけられます")
  local tx, ty = native({ x = 32, y = 100, w = 16, h = 16 })
  m:pressed(1, tx, ty); m:released(1, tx, ty)
  check(m.notice == nil and m.page == "home", "notice touch dismisses only notice, not underlying home action")
  render(480, 800, "settings-detail", nil, 1)
  local before = g.save.options.musicVol
  tx, ty = native(hit("musicVol-"))
  m:pressed(2, tx, ty); m:released(2, tx, ty)
  check(g.save.options.musicVol == before - 1, "pixel-menu minus target changes real audio once")
  tx, ty = native(hit("back"))
  m:pressed(3, tx, ty); m:released(3, tx, ty)
  check(m.page == "settings", "pixel-menu back leaves detail page")
  -- A deliberately long settings provider must still scroll even though the
  -- built-in display rows now fit in far fewer pages.
  local extended=m:settings().sections[2].rows
  for i=1,80 do extended[#extended+1]={id="qa-long-"..i,label="テスト "..i,
    value=function()return "オン"end,step=function()return true end} end
  render(320, 480, "settings-detail", nil, 2)
  local v = m.geometry.viewport
  tx, ty = v.x + 70 * v.sx, v.y + 70 * v.sy
  m:pressed(4, tx, ty); m:moved(4, tx, ty - 35 * v.sy); m:released(4, tx, ty - 35 * v.sy)
  check(m.listPage == 2, "swipe reaches later settings without activating a value")
  m:wheelmoved(-1)
  check(m.listPage == 3, "mouse wheel pages later settings")
  m:wheelmoved(1)
  check(m.listPage == 2, "mouse wheel can return to previous page")
  m:open("settings-detail", 2)
  local firstPage=m:layout().pageRanges[1]
  for _ = firstPage.first, firstPage.last do m:keypressed("down") end
  check(m.focus == firstPage.last+1 and m.listPage == 2, "keyboard automatically advances to next page")
  render(480, 800, "main")
  tx, ty = native(hit("resume"))
  m:pressed(5, tx, ty); m:released(5, tx, ty)
  check(g.closed, "classic first row resumes the game")
  local result="RESULT " .. count .. " checks passed"
  local f=assert(io.open(out.."/session-result.txt","w"));f:write(result.."\n");f:close()
  print(result)
end
function love.load()
  io.stdout:setvbuf("no")
  local ok, err = xpcall(run, debug.traceback)
  if not ok then print(err); love.event.quit(1) else love.event.quit(0) end
end
