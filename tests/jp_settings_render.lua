-- Live schemas from all bundled ZIPs; no MOD source rewriting or ROM art.
return function(Game,Renderer,check,write)
  local Strings=require("src.core.Strings")
  local UIStrings=require("src.ui.JapaneseUIStrings")
  local Json=require("src.link.Json")
  local SaveData=require("src.core.SaveData")
  local g=love.graphics
  local function formats(text)
    local out={}
    for spec in text:gmatch("%%([%-%+ #0]*%d*%.?%d*[cdiouxXeEfgGqs%%])") do
      if spec~="%" then out[#out+1]=spec:sub(-1) end
    end
    return table.concat(out,",")
  end
  for source,target in pairs(require("src.core.JapaneseStringsSettings")) do
    check(formats(source)==formats(target),"settings translation preserves format arguments: "..source)
  end
  local function clone(value)
    if type(value)~="table" then return value end
    local out={};for k,v in pairs(value) do out[k]=clone(v) end;return out
  end
  local entries,seen={},{}
  local function add(source,context)
    if type(source)~="string" or seen[source] then return end
    seen[source]=true
    entries[#entries+1]={source=source,translated=UIStrings.lookup(source),context=context}
  end
  for id,schema in pairs(Game.mods.optionSchemas) do
    local mod=Game.mods.mods[id]
    if mod then
      local m=mod.manifest or mod
      add(m.name,id.." name");add(m.description,id.." description")
    end
    for _,def in ipairs(schema) do
      add(def.label,id.."."..def.key)
      add(def.description,id.."."..def.key.." help")
      add(def.help,id.."."..def.key.." help")
      for _,choice in ipairs(def.choices or {}) do add(choice[1],id.."."..def.key.." choice") end
    end
  end
  local Options=require("src.ui.OptionsMenu").new(Game)
  for _,row in ipairs(Options.rows) do
    add(row.label,"native."..tostring(row.id))
    if row.value then local ok,value=pcall(row.value,Game);if ok then add(value,"native."..tostring(row.id).." value") end end
  end
  for _,name in ipairs({"UPPER","REVERSE LANDSCAPE","OG RED","OG BLUE","OG YELLOW","ADVANCED","OG INV","SGB INV",
      "TREES","DD-MM-YYYY","MM-DD-YYYY","YYYY-MM-DD","UP","DOWN","LEFT","RIGHT",
      "FULL COLOUR","SINGLE COLOUR","GREYSCALE"}) do
    add(name,"native alternate setting")
  end
  table.sort(entries,function(a,b)return a.source<b.source end)
  write("runtime-inventory.json",Json.encode(entries))
  check(#entries>50,"runtime inventory includes bundled MOD schemas and native settings")
  local function technical(text)
    return not text:match("[A-Za-z]") or text:find("[\128-\255]")
      or text:match("^x?[%d./]+X?$") or text:match("^[%d.]+HZ$") or text=="MOD"
  end
  for _,entry in ipairs(entries) do
    check(technical(entry.translated),"localized live presentation: "..entry.context)
  end

  local options=clone(Game.save.options)
  options.jpLauncherLanguage="ja"
  local model=require("src.import.LauncherSettings").open({options=options},"red_jp")
  local function indexRows()
    local out={};for _,section in ipairs(model.sections) do
      for _,row in ipairs(section.rows) do out[row.id]=row end
    end;return out
  end
  local indexed=indexRows()
  local tested=0
  for id,schema in pairs(Game.mods.optionSchemas) do
    options.modOptions[id]=options.modOptions[id] or {}
    for _,def in ipairs(schema) do
      local row=indexed[id.."."..def.key]
      check(row~=nil,"launcher exposes installed schema "..id.."."..def.key)
      check(row.label==UIStrings.lookup(def.label),"launcher resolves schema caption before game load")
      for _,candidate in ipairs(def.choices or {}) do
        options.modOptions[id][def.key]=candidate[2]
        check(row.value()==UIStrings.lookup(candidate[1]),"launcher translates choice while preserving its stored ID")
        check(options.modOptions[id][def.key]==candidate[2],"choice display does not mutate options")
        check(require("src.render.Font").width(row.value())<=88,"finite MOD choice fits between launcher arrows")
        tested=tested+1
      end
      options.modOptions[id][def.key]=def.default
    end
  end
  check(tested>25,"all finite bundled MOD choice ladders are covered")
  options.jpLauncherLanguage="en";model.refreshLabels()
  check(indexed["DRAMALESS_SHAPE.daytime"].label=="DAYTIME","English launcher keeps original MOD caption")
  options.modOptions.DRAMALESS_SHAPE.daytime="cycle"
  check(indexed["DRAMALESS_SHAPE.daytime"].value()=="CYCLE","English launcher keeps original choice")
  options.jpLauncherLanguage="ja";model.refreshLabels()
  check(indexed["DRAMALESS_SHAPE.daytime"].value()=="ひるよるを くりかえす","language switch refreshes dynamic choices")
  check(UIStrings.lookup("Unrelated Custom Mod") == "Unrelated Custom Mod","unrecognized author labels are preserved")

  local oldStrings=Game.data.strings
  Game.data.strings={DAYTIME="MODの じこく"}
  check(UIStrings.lookup("DAYTIME")=="MODの じこく","loaded MOD translation remains authoritative")
  Game.data.strings=oldStrings
  Strings.load(nil)
  check(UIStrings.lookup("UPPER")=="すこし うえ","cold launcher does not require a loaded game catalog")
  Strings.load(Game.data)

  -- Capture the actual launcher and native MOD manager with the JP atlas.
  local View=require("src.import.LauncherView")
  local Manager=require("src.mods.ManagerState")
  local Classic=require("src.ui.ClassicUI")
  local manager=Manager.new(Game)
  local function capture(name,w,h,draw)
    love.window.setMode(w,h,{vsync=0})
    local canvas=g.newCanvas(w,h,{dpiscale=1})
    g.setCanvas(canvas);g.clear(1,1,1,1);draw();g.setCanvas()
    local pixels=canvas:newImageData()
    local bytes=pixels:getString();local ink=0
    for i=1,#bytes,4 do if bytes:byte(i)<128 then ink=ink+1 end end
    check(ink>100,name.." renders visible text and frames")
    write(name..".png",pixels:encode("png"):getString())
    canvas:release();pixels:release()
  end
  for _,size in ipairs({{972,1536},{1536,1160}}) do
    local suffix=size[1].."x"..size[2]
    for _,id in ipairs({"DRAMALESS_SHAPE","SHINY_POKEMON","running_shoes"}) do
      local at
      for i,section in ipairs(model.sections) do
        if section.rows[1] and section.rows[1].id:sub(1,#id+1)==id.."." then at=i;break end
      end
      local imp={tab="red_jp",ready={},_settings=model,
        _ui={page="settings-detail",settingsSection=at,options=options,sheet=1,focus=1}}
      capture("launcher-"..id.."-"..suffix,size[1],size[2],function()View.draw(imp)end)
      local rows=manager:buildOptionRows({id=id},Game.mods.optionSchemas[id])
      capture("native-"..id.."-"..suffix,size[1],size[2],function()
        Classic.begin(Game);require("src.ui.OptionRows").draw(Game,rows,1,0,"BACK");Classic.finish()
      end)
    end
  end
  local importer=require("src.import.RomImporter").new(nil,{launcher=true})
  local persisted=SaveData.loadOptions()
  persisted.jpLauncherLanguage="ja";SaveData.saveOptions(persisted)
  importer:setError("Could not open the file picker.","red_jp")
  check(importer.detail==UIStrings.lookup("Could not open the file picker."),"Android picker error translates before boot")
  importer:startData("fixture", "test.gb")
  check(importer.detail:find("ファイルの おおきさが",1,true)~=nil,"invalid-size ROM notice uses Japanese format template")
  persisted.jpLauncherLanguage="en";SaveData.saveOptions(persisted)
  importer:setError("Could not open the file picker.","red_jp")
  check(importer.detail=="Could not open the file picker.","English import errors remain English")
  persisted.jpLauncherLanguage="ja";SaveData.saveOptions(persisted)
  capture("prelaunch-ja",972,1536,function()
    require("src.core.Prelaunch").draw({version="red_jp",status="Updating 42%"})
  end)
  write("settings-summary.json",Json.encode({romUsed=false,inventory=#entries,modChoices=tested,renderCases=13,
    deliberateLatin={"A/B/START/SELECT and keyboard/controller button IDs","ROM/MOD/GB/SGB/GBC/GBA/BGM and Hz","numeric multipliers and ratios","author names, preset names, file paths, URLs and required attribution"}}))
end
