-- Real validated MOD archives, save roundtrips, profiles, rollback and retries.
function love.load()
  local ok,err=xpcall(function()
    local root=assert(os.getenv("JP_UPGRADE_ROOT"))
    package.path=root.."/?.lua;"..root.."/?/init.lua;"..package.path
    local fs=love.filesystem
    local Json,Save,Mods,Pack=require("src.link.Json"),require("src.core.SaveData"),
      require("src.mods.LauncherMods"),require("src.mods.JapaneseStarterPack")
    local prior={}
    for _,label in ipairs({"jp18","jp19"})do
      local f=assert(io.open(assert(os.getenv("JP_UPGRADE_"..label:upper())),"rb"))
      local bytes=f:read("*a");f:close()
      assert(fs.mount(fs.newFileData(bytes,label..".love"),label,true))
      prior[label]=assert(Json.decode(fs.read(label.."/assets/jp-mods/catalog.json")))
    end
    local current=assert(Json.decode(fs.read("assets/jp-mods/catalog.json")))
    local after={};for _,e in ipairs(current)do after[e.id]=e end
    local OLD,NEW="VOXEL_ASCENDANT","DRAMALESS_SHAPE"
    assert(after[NEW] and not after[OLD],"jp20 catalog must omit Ascendant")
    local n=0
    local function check(v,msg)assert(v,msg);n=n+1;print("PASS "..msg)end
    local function snapshot(path)
      local out={}
      local function walk(at,prefix)
        for _,name in ipairs(fs.getDirectoryItems(at)or{})do
          local full=at.."/"..name
          if fs.getInfo(full).type=="directory"then walk(full,prefix..name.."/")
          else out[prefix..name]=fs.read(full)end
        end
      end
      walk(path,"");return out
    end
    local function same(a,b)
      for k,v in pairs(a)do if b[k]~=v then return false end end
      for k in pairs(b)do if a[k]==nil then return false end end
      return true
    end
    local function remove(path)
      for _,name in ipairs(fs.getDirectoryItems(path)or{})do
        local full=path.."/"..name
        if fs.getInfo(full).type=="directory"then remove(full)else assert(fs.remove(full))end
      end
      assert(fs.remove(path))
    end
    local function setup(mode,previous)
      fs.setIdentity("jp20-rollback-"..mode)
      local options={jpStarterPackV1={},jpDisplayDefaultsV3=true,jpDialogScale=0.5,
        mods={},modsByVersion={red_jp={OTHER=false}},
        modOptions={[OLD]={daytime="dusk",terrainHeights="world"},[NEW]={daytime="day",shadowQuality="off"},running_shoes={bike=false}},
        modProfiles={{name="mine",enabled={},slots={red_jp="slot1"},options={},enabledByVersion={red_jp={}}},
          {name="off",enabled={[OLD]=false,[NEW]=false},slots={},options={},enabledByVersion={red_jp={[OLD]=false,[NEW]=false,KEEP=false}}}},
        activeProfile="mine",customFuture={keep="mine"}}
      if previous then
        for _,entry in ipairs(prior[previous])do
          assert(Mods.installZip(previous.."/"..entry.archive,{expectId=entry.id}))
          options.jpStarterPackV1[entry.id]=entry.version
        end
      end
      if previous=="jp19"then
        options.jpRendererMigrationV1="managed"
        options.mods[OLD],options.mods[NEW]=false,true
        options.modsByVersion.red_jp[OLD],options.modsByVersion.red_jp[NEW]=true,false
      end
      if mode:find("missing",1,true)then remove("mods/"..NEW)end
      if mode=="manual"then
        assert(fs.write("mods/"..OLD.."/custom.txt","manual Ascendant edit"))
        assert(fs.write("mods/"..NEW.."/custom.txt","manual fallback edit"))
        options.jpStarterPackV1[OLD]="existing"
        options.jpStarterPackV1[NEW]="existing"
      end
      if mode=="both-off"then
        options.mods[OLD],options.mods[NEW]=false,false
        options.modsByVersion.red_jp[OLD],options.modsByVersion.red_jp[NEW]=false,false
      end
      if mode=="other-renderer"then
        assert(fs.createDirectory("mods/TERRARIUM"))
        assert(fs.write("mods/TERRARIUM/manifest.json",Json.encode({id="TERRARIUM",name="Existing renderer",version="2.0.0",entry="main.lua"})))
        assert(fs.write("mods/TERRARIUM/main.lua","return function() end"))
        options.mods.TERRARIUM=true
      end
      assert(Save.saveOptions(options))
      return options
    end
    local modes={fresh=false,jp18="jp18",jp19="jp19",manual="jp19",missing="jp19",
      ["missing-install-failure"]="jp19",["both-off"]="jp19",["other-renderer"]="jp19",["stale-catalog"]=false}
    for _,mode in ipairs({"fresh","jp18","jp19","manual","missing","missing-install-failure","both-off","other-renderer","stale-catalog"})do
      local options=setup(mode,modes[mode])
      local ascendant=snapshot("mods/"..OLD)
      local fallback=snapshot("mods/"..NEW)
      local deps
      if mode=="missing-install-failure"then
        deps={LauncherMods={installedVersions=Mods.installedVersions,installZip=function(path,cfg)
          if cfg.expectId==NEW then return nil,"fixture disk failure"end
          return Mods.installZip(path,cfg)
        end}}
      elseif mode=="stale-catalog"then
        local stale={};for _,e in ipairs(current)do stale[#stale+1]=e end
        stale[#stale+1]={id=OLD,version="old",archive="missing-ascendant.zip"}
        deps={fs=setmetatable({read=function(path)
          if path=="assets/jp-mods/catalog.json"then return Json.encode(stale)end
          return fs.read(path)
        end},{__index=fs})}
      end
      local result,detail=Pack.install(deps)
      if mode=="missing-install-failure"then
        check(result==nil and detail:find("fixture disk failure",1,true),"missing fallback install failure reported")
        check(Save.loadOptions().jpRendererRollbackV1==nil,"failed repair remains retryable")
        check(not Mods.installedVersions()[NEW],"failed repair does not invent an installed fallback")
        check(Pack.install()~=nil,"fallback repair retry succeeds")
      else check(result~=nil,mode.." installation: "..tostring(detail))end
      local saved,installed=Save.loadOptions(),Mods.installedVersions()
      check(saved.jpRendererRollbackV1==true,mode.." rollback marker persisted")
      check(Save.modEnabled(saved,OLD,"red_jp")==false,mode.." Ascendant disabled")
      check(Save.modEnabled(saved,NEW,"red_jp")== (mode~="both-off" and mode~="other-renderer"),mode.." fallback selection")
      check(installed[NEW]~=nil,mode.." fallback installed")
      if mode~="manual"then check(installed[NEW]==after[NEW].version,mode.." fallback version upgraded")end
      local oldVersion=options.jpStarterPackV1[NEW]
      if modes[mode] and mode~="manual" and not mode:find("missing",1,true) and oldVersion~=after[NEW].version then
        check(same(snapshot("jp-mod-backups/"..modes[mode].."/"..NEW),fallback),mode.." original fallback byte backup retained")
      end
      check(same(snapshot("mods/"..OLD),ascendant),mode.." manual/previous Ascendant files untouched")
      if mode=="fresh"or mode=="stale-catalog"then check(installed[OLD]==nil,mode.." no Ascendant installed")end
      if mode=="manual"then check(same(snapshot("mods/"..NEW),fallback),"manual fallback untouched")end
      check(saved.modOptions[OLD].terrainHeights=="world" and saved.modOptions[OLD].daytime=="dusk",mode.." retired options unchanged")
      check(saved.modOptions[NEW].daytime=="day" and saved.modOptions[NEW].shadowQuality=="off",mode.." fallback options unchanged")
      check(saved.modOptions.running_shoes.bike==false,mode.." explicit bicycle option retained")
      check(saved.jpDialogScale==0.5 and saved.customFuture.keep=="mine",mode.." unrelated preferences retained")
      check(saved.modsByVersion.red_jp.OTHER==false,mode.." unrelated live flag retained")
      check(saved.modProfiles[1].slots.red_jp=="slot1" and saved.activeProfile=="mine",mode.." profile/slot retained")
      check(saved.modProfiles[1].enabledByVersion.red_jp.OTHER==false,mode.." empty profile inherits original unrelated overlay")
      for _,profile in ipairs(saved.modProfiles)do
        check(Mods.applyProfile(profile.name,saved),mode.." applies "..profile.name)
        local live=Save.loadOptions()
        for _,v in ipairs(require("src.core.GameVersion").ORDER)do
          check(Save.modEnabled(live,OLD,v)==false,mode.." profile cannot reactivate Ascendant "..profile.name.." "..v)
        end
        if profile.name=="off"then check(Save.modEnabled(live,NEW,"red_jp")==false,mode.." explicit profile both-off retained")end
        for _,row in ipairs(Mods.list("red_jp"))do
          if row.id==OLD or row.id==NEW then check(row.status~="conflict",mode.." profile no renderer conflict "..row.id)end
        end
      end
      check(Pack.install()==false,mode.." restart does not repeat rollback")
    end
    -- Save failures must undo repaired/updated MOD roots and invalidate the
    -- options cache, including a writer that partially persisted new settings.
    for _,mode in ipairs({"save-fresh","save-jp18","save-jp19","save-missing"})do
      local previous
      if mode~="save-fresh"then previous=mode=="save-jp18"and "jp18"or "jp19"end
      setup(mode,previous)
      local allBefore=snapshot("mods")
      local optionNames={"options.lua","options.lua.bak","options.lua.tmp"}
      local witnesses={};for _,name in ipairs(optionNames)do witnesses[name]=fs.read(name)or false end
      local failingSave=setmetatable({saveOptions=function(value)
        assert(Save.saveOptions(value))
        check(Save.loadOptions().jpRendererRollbackV1==true,mode.." injected writer poisons cache with new marker")
        return nil,"injected partial options failure"
      end},{__index=Save})
      local result,detail=Pack.install({SaveData=failingSave})
      check(result==nil and detail:find("injected partial options failure",1,true),mode.." save failure reported")
      check(same(snapshot("mods"),allBefore),mode.." every installed byte restored")
      for _,name in ipairs(optionNames)do check((fs.read(name)or false)==witnesses[name],mode.." original "..name.." restored")end
      check(Save.loadOptions().jpRendererRollbackV1==nil,mode.." cache invalidated and marker retryable")
      check(Pack.install()~=nil,mode.." retry succeeds")
      local saved=Save.loadOptions()
      check(saved.jpRendererRollbackV1==true and Save.modEnabled(saved,OLD,"red_jp")==false and Save.modEnabled(saved,NEW,"red_jp")==true,mode.." retry restores fallback")
    end
    print("RESULT "..n.." checks passed")
  end,debug.traceback)
  if not ok then print(err)end
  love.event.quit(ok and 0 or 1)
end
