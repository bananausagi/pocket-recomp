-- Real editor rendering and localization with isolated save storage; no ROM.
local function run()
  local out = assert(os.getenv('JP_EDITORS_QA_OUT'))
  local Editor = require('src.ui.TouchControlsEditor')
  local Theme = require('src.ui.kit.Theme')
  local Touch = require('src.core.TouchControls')
  local Skin = require('src.core.TouchSkin')
  local UIStrings = require('src.ui.JapaneseUIStrings')
  local checks = 0
  local function check(value, label) assert(value, label); checks=checks+1; print('PASS '..label) end
  local prints, oldPrint, oldPrintf = {}, love.graphics.print, love.graphics.printf
  love.graphics.print = function(text, ...) if type(text)=='string' then prints[#prints+1]=text end; return oldPrint(text, ...) end
  love.graphics.printf = function(text, ...) if type(text)=='string' then prints[#prints+1]=text end; return oldPrintf(text, ...) end
  local function render(version, w, h)
    love.window.setMode(w, h, {resizable=true,vsync=0})
    Editor.load({version=version})
    if version == "red_jp" then check(not Touch:hotbarShown(), "JP preview hides the unused hotbar over Save") end
    prints={}
    local c = love.graphics.newCanvas(w,h)
    love.graphics.setCanvas(c); love.graphics.clear(); Editor.draw(); love.graphics.setCanvas()
    local f=assert(io.open(out..'/touch-'..version..'-'..w..'x'..h..'.png','wb'))
    f:write(c:newImageData():encode('png'):getString());f:close();c:release()
    for _, font in pairs(Editor.fonts) do
      check(font:hasGlyphs('タッチ操作保存よこたて画めん'), 'editor font can draw Japanese')
      local clipped=Theme.ellipsize(font, 'ながいにほんごのボタン', 60)
      check(require('utf8').len(clipped)~=nil, 'truncation keeps complete UTF-8')
      check(font:getWidth(clipped)<=60, 'truncated Japanese fits width')
    end
    local joined=table.concat(prints,'\n')
    check(joined:find(version=='red_jp' and 'もとに戻す' or 'Reset',1,true), 'locale used by real buttons')
    check(joined:find(version=='red_jp' and 'がめんのボタン' or 'On-screen controls',1,true), 'locale used by editor label')
    check(not joined:find(version=='red_jp' and 'Touch Controls' or 'タッチ操作',1,true), 'other locale does not leak')
    Editor.unload()
  end
  for _,size in ipairs({{480,800},{800,480},{320,480}}) do render('red_jp',size[1],size[2]) end
  render('red',480,800)
  Editor.version='red_jp'; Editor.skins={{id='My Custom Skin'}};Touch.skinId='My Custom Skin'
  Skin.active={pages={{},{}}}
  check(Editor.skinLabel()=='My Custom Skin（2ページ）','user skin name is preserved')
  Editor.version='red'
  check(Editor.skinLabel()=='My Custom Skin (2 pages)','English mode is unchanged')
  local oldExport=Skin.export
  Skin.export=function() return 'skins/My Custom Skin.zip',{'missing.png'} end
  Editor.version='red_jp';Editor.exportSkin()
  check(Editor.exportMsg:find('skins/My Custom Skin.zip',1,true) and Editor.exportMsg:find('画像1個',1,true),'export path and missing-image count survive formatting')
  Skin.export=function() return nil,'ENOENT' end
  Editor.exportSkin()
  check(Editor.exportMsg=='書き出せませんでした: ENOENT','error details are retained')
  Skin.export=oldExport;Skin.active=nil
  check(UIStrings.lookup('TouchEditor: Done','ja')=='保存','editor dictionary is available before game load')
  check(UIStrings.lookup('TouchEditor: Done','en')=='TouchEditor: Done','English helper does not translate')
  love.graphics.print,love.graphics.printf=oldPrint,oldPrintf
  print('RESULT '..checks..' checks passed')
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err);love.event.quit(1) else love.event.quit(0) end
end
