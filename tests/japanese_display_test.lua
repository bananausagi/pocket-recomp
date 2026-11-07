-- ROM-free regressions for jp.3: format safety, font metrics, layout, migration.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local Font = require("src.render.Font")
local Json = require("src.link.Json")
local function read(path) local f = assert(io.open(path, "rb")); local s=f:read("*a"); f:close(); return s end
local manifest = assert(Json.decode(read("tools/rom_manifest_red_jp.json")))
local tiles={}
for _,entry in ipairs(manifest.fontCharmap) do tiles[#tiles+1]=entry.seq end
Font.load({font={language="ja", charmap=manifest.fontCharmap,
  composites=manifest.fontComposites, ttf={tiles=tiles}}})
T.eq(Font.lineHeight(),16,"Japanese rows reserve the voiced-mark tile")
T.eq(Font.width("MOD MANAGER 2.0.4+jp.2"),22*8,"Latin fallback fits 8px cells")
T.check(Font.encode("M")[1]<Font.TTF_BASE,"Latin no longer uses 15px TTF")
T.eq(Font.encode("ガ")[1],261,"Japanese composite still uses ROM code")
local OptionRows=require("src.ui.OptionRows")
T.eq(OptionRows.visibleRows(),3,"Japanese settings show three legible groups")
T.eq(OptionRows.clampScroll(4,0,6),1,"fourth option scrolls into view")
local Marquee=require("src.ui.Marquee")
T.eq(Marquee.clip("ドットマトリクス",3),"ドット","clipping keeps UTF-8 glyphs intact")
T.eq(Marquee.at("ドットマトリクス",3,1.5),"トマト","marquee advances whole kana")
local Strings=require("src.core.Strings")
Strings.load({constants={language="ja"}})
local count=0
local function formats(text)
  local out={}
  for spec in text:gmatch("%%([%-%+ #0]*%d*%.?%d*[cdiouxXeEfgGqs%%])") do
    if spec~="%" then out[#out+1]=spec:sub(-1) end
  end
  return table.concat(out,",")
end
for _,module in ipairs({"src.core.JapaneseStrings","src.core.JapaneseStringsExtra"}) do
  for key,value in pairs(require(module)) do
    count=count+1
    T.eq(formats(value),formats(key),"translation format: "..key)
  end
end
T.check(count>400,"base and additional Japanese catalogs are checked")
T.eq(Strings("SHINY RATE"),"でる かくりつ","new mod option translated")

local Renderer=require("src.render.Renderer")
T.eq(Renderer.windowScale(6,0.75),5,"all window pixels share one integer scale")
T.eq(Renderer.windowScale(1,0.5),1,"small displays never lose font pixels")
T.eq(Renderer.windowScale(0.8,0.5),0.8,"subnative display preserves fit")
T.eq(Renderer.windowScale(6,0/0),5,"invalid window size uses normal baseline")
local Game=require("src.core.Game")
local stack=require("src.core.StateStack");stack:init()
stack:push({isOpaque=true,isBattle=true})
stack:push({isTextBox=true})
T.eq(Game.windowScaleInStack(stack,{jpDialogScale=0.5}),0.5,"visible battle and message share window scale")
stack:push({isOpaque=true,screenId="OptionsMenu"})
T.eq(Game.windowScaleInStack(stack,{jpDialogScale=0.5}),0.5,"opaque settings above battle use window scale")
stack:pop();stack:pop();stack:pop()
stack:push({isOverworld=true});stack:push({holdsUIAnchors=true})
T.eq(Game.windowScaleInStack(stack,{jpDialogScale=0.75}),0.75,"held report window does not override menu size")
for _,up in ipairs({0.8,1,2,3,4,7}) do
  local r={Up=up,dpiX=1.25,dpiY=1.5,uox=10,uoy=20,uiw=160,uih=144,
    uvpw=160*up/1.25,uvph=144*up/1.5,vuy=0,vuh=144*up/1.5+60}
  local x,y,w,h,sx,sy=Renderer.dialogPlacement(r,{x=0,y=96,w=160,h=48,dialog=0.5},true)
  local cx,cy,cw,ch=Renderer.dialogPlacement(r,{x=104,y=48,w=56,h=48,dialog=0.5},true)
  T.check(w<=r.uvpw and h<=48*up/r.dpiY,"dialog never grows at scale "..up)
  T.check(math.abs(x+w/2-(r.uox+r.uvpw/2))<1e-6,"dialog remains centered at "..up)
  T.check(math.abs(cy+ch-y)<1e-6 and math.abs(cx+cw-x-w)<1e-6,"choice attaches above right edge at "..up)
  T.check(math.abs(y+h-r.uoy-r.uvph)<1e-6,"dialog stays inside bottom at "..up)
end

local Pack=require("src.mods.JapaneseStarterPack")
local function migration(mode)
  local root="mods/DRAMALESS_SHAPE/"
  local bytes={ [root.."manifest.json"]='{"id":"DRAMALESS_SHAPE"}',[root.."main.lua"]="old source" }
  local old={version="2.0.4+jp.1",files={['manifest.json']=bytes[root.."manifest.json"],['main.lua']="old source"}}
  local entries={{id="DRAMALESS_SHAPE",version="2.0.4+jp.2",archive="pack.zip"}}
  local options={jpStarterPackV1={DRAMALESS_SHAPE=old.version},jpDotMatrix=0,jpDialogScale=1,
    mods={DRAMALESS_SHAPE=false},modOptions={DRAMALESS_SHAPE={renderScale=4}}}
  local calls=0
  if mode=="edited" then bytes[root.."main.lua"]="user source" end
  if mode=="extra" then bytes[root.."mine.lua"]="user file" end
  if mode=="removed" then bytes={} end
  local fs={}
  function fs.read(p)
    if p=="assets/jp-mods/catalog.json" then return Json.encode(entries) end
    if p=="assets/jp-mods/upgrades-jp2.json" then return Json.encode({DRAMALESS_SHAPE=old}) end
    return bytes[p]
  end
  function fs.getDirectoryItems(p)
    local names,out={},{}
    for f in pairs(bytes) do
      if f:sub(1,#p+1)==p.."/" then names[f:sub(#p+2):match("^[^/]+")]=true end
    end
    for n in pairs(names) do out[#out+1]=n end
    return out
  end
  function fs.getInfo(p)
    if bytes[p] then return {type="file"} end
    if #fs.getDirectoryItems(p)>0 then return {type="directory"} end
  end
  function fs.createDirectory() return mode~="backup-failure" end
  function fs.write(p,b) bytes[p]=b; return true end
  local deps={fs=fs,Json=Json,hash=function(b)return b end,
    SaveData={loadOptions=function()return options end,saveOptions=function(o)options=o;return o end},
    LauncherMods={installedVersions=function()return mode=="removed" and {} or {DRAMALESS_SHAPE=old.version} end,
      installZip=function(_,config)
        calls=calls+1; T.check(config.replace,"managed update requests replacement")
        bytes[root.."main.lua"]="new source"
        if mode=="install-failure" then return nil,"fixture disk full" end
        return true
      end}}
  local ok=Pack.install(deps)
  T.eq(options.jpDotMatrix,0,"grid preference survives "..mode)
  T.eq(options.jpDialogScale,1,"dialog preference survives "..mode)
  T.eq(options.mods.DRAMALESS_SHAPE,false,"disabled state survives "..mode)
  T.eq(options.modOptions.DRAMALESS_SHAPE.renderScale,4,"mod options survive "..mode)
  if mode=="pristine" then
    T.eq(calls,1,"pristine copy is upgraded")
    T.eq(options.jpStarterPackV1.DRAMALESS_SHAPE,entries[1].version,"managed version advances")
    T.eq(bytes['jp-mod-backups/jp2/DRAMALESS_SHAPE/main.lua'],"old source","backup holds the previous copy")
  elseif mode=="install-failure" then
    T.eq(ok,nil,"failed replacement reports failure")
    T.eq(bytes[root.."main.lua"],"old source","previous source restored on failure")
    T.eq(options.jpStarterPackV1.DRAMALESS_SHAPE,old.version,"failed replacement stays retryable")
  else
    T.eq(calls,0,"does not overwrite "..mode)
    local expected=mode=="edited" and "user source" or "old source"
    if mode=="removed" then expected=nil end
    T.eq(bytes[root.."main.lua"],expected,"source retained "..mode)
  end
end
for _,mode in ipairs({"pristine","edited","extra","removed","backup-failure","install-failure"}) do migration(mode) end
Strings.load({})
Font.load({font={charmap={}}})
T.eq(OptionRows.visibleRows(),4,"English settings retain four groups")
T.finish("Japanese display and migration")
