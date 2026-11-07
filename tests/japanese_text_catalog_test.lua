-- Actual Strings.load/get plus native Font.split on every shipped JP entry.
-- Graphics are stubbed: character maps are from the import manifest, not ROM.
package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
package.loaded["src.render.Assets"]={
  image=function()return {getDimensions=function()return 128,128 end}end,
  register=function()end,
}
local Json=require("src.link.Json")
local f=assert(io.open("tools/rom_manifest_red_jp.json","rb"))
local manifest=assert(Json.decode(f:read("*a")));f:close()
local Font=require("src.render.Font")
Font.load({font={language="ja",image="synthetic-font",mainBase=0,
  charmap=manifest.fontCharmap,composites=manifest.fontComposites}})
local Strings=require("src.core.Strings")
local catalog={}
local moduleFile=assert(io.open("src/core/Strings.lua","rb"))
local moduleSource=moduleFile:read("*a");moduleFile:close()
local block=assert(moduleSource:match("for%s+_,%s*module%s+in%s+ipairs%s*%(%s*%{(.-)%}%s*%)"))
local modules={"JapaneseStrings","JapaneseStringsExtra"}
for suffix in block:gmatch('"([%w_]+)"')do modules[#modules+1]="JapaneseStrings"..suffix end
for _,name in ipairs(modules)do
  local path="src/core/"..name..".lua"
  local exists=io.open(path,"rb")
  if exists then
    exists:close()
    for key,value in pairs(require("src.core."..name))do catalog[key]=value end
  end
end
Strings.load({constants={language="ja"}})
local checks,formatChecks,glyphs=0,0,0
for key,translation in pairs(catalog)do
  local context,source=key:match("^([%w_.]+)|(.+)$")
  source=source or key
  assert(Strings.lookup(source,context)==translation,"catalog lookup: "..key)
  checks=checks+1
  local args={}
  local escaped=source:gsub("%%%%","")
  for kind in escaped:gmatch("%%[-+ #0]*%d*%.?%d*([cdiouxXeEfgGqs])")do
    args[#args+1]=(kind=="s" or kind=="q") and "てすと"
      or kind=="c" and 65 or (kind=="f" or kind=="e" or kind=="E" or kind=="g" or kind=="G") and 1.25 or 7
  end
  local rendered=translation
  if #args>0 and not context then
    local expected=string.format(translation,unpack(args))
    rendered=Strings(source,unpack(args))
    assert(rendered==expected,"formatted catalog lookup: "..key)
    formatChecks=formatChecks+1
  end
  rendered=rendered:gsub("%b{}",""):gsub("<[^<>]*>",""):gsub("%c","")
  if not key:match("^TouchEditor: ") and not key:match("^SkinStudio: ") and not key:match("^Kit: ") and not key:match("^UIKit: ") and not key:match("^UI kit: ") then
  for _,span in ipairs(Font.split(rendered))do
    assert(span.code~=nil,"native font missing "..rendered:sub(span.from,span.to).." in "..key)
    glyphs=glyphs+1
  end
  end
end
print(string.format("PASS %d Japanese catalog lookups, %d real formatted lookups, %d native glyph spans",checks,formatChecks,glyphs))

-- The pre-ROM catalog must work with no game/Strings data, and preserve an
-- explicit English locale plus current Japanese MOD overrides at display time.
local uiSourceFile=assert(io.open("src/ui/JapaneseUIStrings.lua","rb"))
local uiSource=uiSourceFile:read("*a");uiSourceFile:close()
local uiCatalog={}
for module in uiSource:gmatch('require%("(src.core.JapaneseStrings[%w_]*)"%)')do
  for key,value in pairs(require(module))do if uiCatalog[key]==nil then uiCatalog[key]=value end end
end
package.loaded["src.core.Game"]=nil
local UIStrings=require("src.ui.JapaneseUIStrings")
local uiChecks=0
for key,value in pairs(uiCatalog)do
  assert(UIStrings.lookup(key,"ja")==value,"pre-ROM catalog lookup: "..key)
  assert(UIStrings.lookup(key,"en")==key,"English opt out: "..key)
  uiChecks=uiChecks+2
end
package.loaded["src.core.Game"]={data={constants={language="ja"},strings={["UI kit: Clear"]="MODの ことば"}}}
assert(UIStrings.lookup("UI kit: Clear","ja")=="MODの ことば","active MOD presentation override")
assert(UIStrings.lookup("UI kit: Clear","en")=="UI kit: Clear","English ignores JP MOD override")
package.loaded["src.core.Game"]=nil
print(string.format("PASS %d pre-ROM UI lookup/English-locale checks and 2 live MOD override checks",uiChecks))
