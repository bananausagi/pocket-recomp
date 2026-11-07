-- Exercise real shipped jp18 ZIPs, installer, saved options and named profiles.
function love.load()
  local ok,err=xpcall(function()
    local root=assert(os.getenv("JP_UPGRADE_ROOT"))
    package.path=root.."/?.lua;"..root.."/?/init.lua;"..package.path
    local fs=love.filesystem
    local Json,Save,Mods,Pack=require("src.link.Json"),require("src.core.SaveData"),
      require("src.mods.LauncherMods"),require("src.mods.JapaneseStarterPack")
    local f=assert(io.open(assert(os.getenv("JP_UPGRADE_PREVIOUS_LOVE")),"rb"))
    local bytes=f:read("*a");f:close()
    assert(fs.mount(fs.newFileData(bytes,"previous.love"),"previous",true))
    local prior=assert(Json.decode(fs.read("previous/assets/jp-mods/catalog.json")))
    local current=assert(Json.decode(fs.read("assets/jp-mods/catalog.json")))
    local before,after={},{}
    for _,entry in ipairs(prior)do before[entry.id]=entry end
    for _,entry in ipairs(current)do after[entry.id]=entry end
    local OLD,NEW="DRAMALESS_SHAPE","VOXEL_ASCENDANT"
    assert(before[OLD].version=="2.0.4+jp.12" and after[NEW])
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
    for _,mode in ipairs({"fresh","pristine","disabled","edited","extra","missing-file",
      "manual","removed","duplicate","other-renderer","existing-ascendant","install-failure"})do
      fs.setIdentity("jp19-real-upgrade-"..mode)
      local options={jpStarterPackV1={},jpDisplayDefaultsV3=true,jpDialogScale=0.5,
        mods={},modsByVersion={red_jp={OTHER=false}},
        modOptions={[OLD]={daytime="dusk",renderScale=1,shadowQuality="off"}},
        modProfiles={{name="mine",enabled={},slots={},options={}},
          {name="disabled",enabled={[OLD]=false},slots={},options={}}},
        activeProfile="mine",customFuture={keep="mine"}}
      if mode~="fresh"then
        for _,entry in ipairs(prior)do
          assert(Mods.installZip("previous/"..entry.archive,{expectId=entry.id}))
          options.jpStarterPackV1[entry.id]=entry.version
        end
      end
      local original=snapshot("mods/"..OLD)
      local shoesOriginal=snapshot("mods/running_shoes")
      if mode=="disabled"then options.mods[OLD]=false end
      if mode=="edited"then assert(fs.write("mods/"..OLD.."/main.lua",original["main.lua"].."\n-- user edit\n"))end
      if mode=="extra"then assert(fs.write("mods/"..OLD.."/custom.txt","user file"))end
      if mode=="missing-file"then assert(fs.remove("mods/"..OLD.."/main.lua"))end
      if mode=="manual"then options.jpStarterPackV1[OLD]="existing"end
      if mode=="removed"then remove("mods/"..OLD)end
      if mode=="duplicate"then
        assert(fs.createDirectory("mods/duplicate"));assert(fs.write("mods/duplicate/manifest.json",original["manifest.json"]))
      end
      if mode=="other-renderer"then
        assert(fs.createDirectory("mods/STADIUM_BATTLE_FX"))
        assert(fs.write("mods/STADIUM_BATTLE_FX/manifest.json",Json.encode({id="STADIUM_BATTLE_FX",name="Existing renderer",version="2.0.0",entry="main.lua"})))
        assert(fs.write("mods/STADIUM_BATTLE_FX/main.lua","return function() end"))
      end
      if mode=="existing-ascendant"then
        assert(Mods.installZip(after[NEW].archive,{expectId=NEW}));options.mods[NEW]=false
      end
      assert(Save.saveOptions(options))
      local expected=snapshot("mods/"..OLD)
      local deps
      if mode=="install-failure"then
        deps={LauncherMods={installedVersions=Mods.installedVersions,installZip=function(path,cfg)
          if cfg.expectId==NEW then return nil,"fixture disk failure"end
          return Mods.installZip(path,cfg)
        end}}
      end
      local result,detail=Pack.install(deps)
      if mode=="install-failure"then
        check(result==nil and detail:find("fixture disk failure",1,true),mode.." reported")
        local saved=Save.loadOptions()
        check(saved.jpRendererMigrationV1==nil and saved.mods[OLD]~=false,"failed replacement leaves active fallback")
        check(Pack.install()~=nil,"replacement retry succeeds after fallback upgrade")
      else check(result~=nil,mode.." installation: "..tostring(detail))end
      local saved,installed=Save.loadOptions(),Mods.installedVersions()
      local adopt=mode=="fresh"or mode=="pristine"or mode=="disabled"or mode=="install-failure"
      check(installed[NEW]==after[NEW].version,mode.." new renderer installed")
      check(installed.running_shoes==after.running_shoes.version,mode.." running shoes adapter updated")
      if mode~="fresh"then
        check(same(snapshot("jp-mod-backups/jp18/running_shoes"),shoesOriginal),mode.." original running shoes backed up")
      end
      check(Save.modEnabled(saved,NEW,"red_jp")== (adopt and mode~="disabled"),mode.." actual selection")
      check(saved.jpDialogScale==0.5 and saved.customFuture.keep=="mine",mode.." unrelated preferences retained")
      check(saved.modsByVersion.red_jp.OTHER==false,mode.." unrelated version flag retained")
      check(saved.modOptions[OLD].daytime=="dusk" and saved.modOptions[OLD].shadowQuality=="off",mode.." fallback options retained")
      if mode~="fresh"and not adopt and mode~="other-renderer"and mode~="existing-ascendant"then
        check(same(snapshot("mods/"..OLD),expected),mode.." custom/deleted/duplicate fallback preserved")
      elseif mode=="pristine"or mode=="disabled"or mode=="install-failure"then
        check(installed[OLD]==after[OLD].version,mode.." fallback adapter updated")
        check(same(snapshot("jp-mod-backups/jp18/"..OLD),original),mode.." original bytes backed up")
      end
      for _,profile in ipairs(saved.modProfiles)do
        if mode~="existing-ascendant"then
          check(Mods.applyProfile(profile.name,saved),mode.." applies "..profile.name)
          for _,row in ipairs(Mods.list("red_jp"))do
            if row.id==OLD or row.id==NEW then check(row.status~="conflict",mode.." profile no renderer conflict "..row.id)end
          end
        end
      end
      local repeatResult=Pack.install()
      check(repeatResult==false,mode.." repeated startup unchanged")
    end
    -- Installation and option state form one transaction. A failed settings
    -- write must restore every upgraded tree, not merely remove Ascendant;
    -- otherwise the old managed tags no longer match and retry cannot adopt.
    for _,mode in ipairs({"fresh","pristine","disabled","manual","edited","partial-write","cached-write"})do
      fs.setIdentity("jp19-save-failure-"..mode)
      local options={jpStarterPackV1={},jpDisplayDefaultsV3=true,
        mods={},modsByVersion={red_jp={OTHER=false}},
        modOptions={[OLD]={daytime="dusk"},running_shoes={bike=false}},
        modProfiles={{name="mine",enabled={},options={}}},activeProfile="mine"}
      if mode~="fresh"then
        for _,entry in ipairs(prior)do
          assert(Mods.installZip("previous/"..entry.archive,{expectId=entry.id}))
          options.jpStarterPackV1[entry.id]=entry.version
        end
      end
      if mode=="disabled"then options.mods[OLD]=false end
      if mode=="manual"then options.jpStarterPackV1[OLD]="existing"end
      if mode=="edited"then assert(fs.write("mods/"..OLD.."/custom.txt","user file"))end
      assert(Save.saveOptions(options))
      local allBefore,oldBefore,shoesBefore=snapshot("mods"),snapshot("mods/"..OLD),snapshot("mods/running_shoes")
      local optionNames={"options.lua","options.lua.bak","options.lua.tmp"}
      local witnesses={}
      for _,name in ipairs(optionNames)do witnesses[name]=fs.read(name)or false end
      local writes=0
      local failingSave=setmetatable({saveOptions=function(value)
        writes=writes+1
        if mode=="partial-write"or mode=="cached-write"then assert(Save.saveOptions(value))end
        if mode=="cached-write"then
          check(Save.loadOptions().jpRendererMigrationV1~=nil,"failed writer cached its new migration marker")
        end
        return nil,"injected options write failure"
      end},{__index=Save})
      local result,detail=Pack.install({SaveData=failingSave})
      check(result==nil and detail:find("injected options write failure",1,true),mode.." settings failure reported")
      check(writes==1,mode.." settings failure does not silently write again")
      check(same(snapshot("mods"),allBefore),mode.." every prior MOD byte restored and new files removed")
      for _,name in ipairs(optionNames)do
        check((fs.read(name)or false)==witnesses[name],mode.." previous "..name.." restored")
      end
      local rolled=Save.loadOptions()
      check(rolled.jpRendererMigrationV1==nil,mode.." failed migration remains retryable")
      check(rolled.mods[OLD]==options.mods[OLD],mode.." original renderer enable choice retained")
      check(rolled.modOptions.running_shoes.bike==false,mode.." explicit bike setting retained")
      if mode~="fresh"then
        check(same(snapshot("jp-mod-backups/jp18/running_shoes"),shoesBefore),mode.." previous backup retained after rollback")
      end
      local retried,why=Pack.install()
      check(retried~=nil,mode.." retry succeeds: "..tostring(why))
      local saved,installed=Save.loadOptions(),Mods.installedVersions()
      local adopt=mode=="fresh"or mode=="pristine"or mode=="partial-write"or mode=="cached-write"
      check(installed[NEW]==after[NEW].version,mode.." retry installs Ascendant")
      check(installed.running_shoes==after.running_shoes.version,mode.." retry upgrades running shoes")
      check(Save.modEnabled(saved,NEW,"red_jp")==adopt,mode.." retry preserves renderer policy")
      if mode=="manual"or mode=="edited"then
        check(same(snapshot("mods/"..OLD),oldBefore),mode.." retry leaves user-owned renderer unchanged")
      end
    end
    print("RESULT "..n.." checks passed")
  end,debug.traceback)
  if not ok then print(err)end
  love.event.quit(ok and 0 or 1)
end
