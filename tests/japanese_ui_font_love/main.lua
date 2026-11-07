-- Inspect the actual default LÖVE face plus UiFont's bundled fallback.
local function run()
  local root=assert(os.getenv("JP_FONT_ROOT"))
  package.path=root.."/?.lua;"..package.path
  local Json=require("src.link.Json")
  local UiFont=require("src.render.UiFont")
  local UTF8=require("utf8")
  local catalogs={}
  for _,name in ipairs({"JapaneseStringsEditors","JapaneseStringsTouchEditor","JapaneseStringsKit"})do
    for key,value in pairs(require("src.core."..name))do catalogs[key]=value end
  end
  local checks,failures=0,{}
  for _,size in ipairs({16,18,28})do
    local font=UiFont.attach(love.graphics.newFont(size),size)
    for key,value in pairs(catalogs)do
      local clean=value:gsub("%c","")
      checks=checks+1
      if not font:hasGlyphs(clean)then
        local missing={}
        for _,code in UTF8.codes(clean)do
          local char=UTF8.char(code)
          if not font:hasGlyphs(char)then missing[char]=true end
        end
        failures[#failures+1]={key=key,size=size,missing=missing}
      end
    end
    font:release()
  end
  local report={checks=checks,failures=failures,renderer={love.graphics.getRendererInfo()}}
  local path=assert(os.getenv("JP_FONT_OUT"))
  local file=assert(io.open(path,"wb"));file:write(Json.encode(report));file:close()
  print(Json.encode(report))
  assert(#failures==0,"editor UI font has missing glyphs")
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
