-- Real prior-APK ZIPs, normal validated installer and isolated application data.
function love.load()
  local ok, err = xpcall(function()
    local root = assert(os.getenv("JP_UPGRADE_ROOT"))
    local previous = assert(os.getenv("JP_UPGRADE_PREVIOUS_LOVE"))
    package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
    local fs,Json = love.filesystem,require("src.link.Json")
    local Save,Mods,Pack = require("src.core.SaveData"),require("src.mods.LauncherMods"),require("src.mods.JapaneseStarterPack")
    local f=assert(io.open(previous,"rb"));local bytes=f:read("*a");f:close()
    assert(fs.mount(fs.newFileData(bytes,"previous.love"),"previous",true))
    local prior=assert(Json.decode(fs.read("previous/assets/jp-mods/catalog.json")))
    local current=assert(Json.decode(fs.read("assets/jp-mods/catalog.json")))
    local old,new
    for _,e in ipairs(prior)do if e.id=="DRAMALESS_SHAPE" then old=e end end
    for _,e in ipairs(current)do if e.id=="DRAMALESS_SHAPE" then new=e end end
    assert(old.version=="2.0.4+jp.11" and new.version=="2.0.4+jp.12")
    local count=0
    local function check(value,message) assert(value,message);count=count+1;print("PASS "..message) end
    local function snapshot(path)
      local files={}
      local function visit(at,prefix)
        for _,name in ipairs(fs.getDirectoryItems(at))do
          local full=at.."/"..name
          if fs.getInfo(full).type=="directory" then visit(full,prefix..name.."/")
          else files[prefix..name]=assert(fs.read(full)) end
        end
      end
      visit(path,"");return files
    end
    local function same(a,b)
      for n,v in pairs(a)do if b[n]~=v then return false end end
      for n in pairs(b)do if a[n]==nil then return false end end
      return true
    end
    local function remove(path)
      for _,name in ipairs(fs.getDirectoryItems(path))do
        local p=path.."/"..name
        if fs.getInfo(p).type=="directory" then remove(p)else assert(fs.remove(p))end
      end
      assert(fs.remove(path))
    end
    for _,mode in ipairs({"pristine","edited","extra","missing-file","manual","removed","duplicate","backup-failure","install-failure"})do
      fs.setIdentity("jp18-upgrade-"..mode)
      for _,entry in ipairs(prior)do assert(Mods.installZip("previous/"..entry.archive,{expectId=entry.id}))end
      local original=snapshot("mods/DRAMALESS_SHAPE")
      local other={}
      for _,entry in ipairs(prior)do if entry.id~=old.id then other[entry.id]=snapshot("mods/"..entry.id)end end
      local options={jpStarterPackV1={},jpDisplayDefaultsV3=true,jpDialogScale=0.5,jpDotMatrix=0,
        mods={DRAMALESS_SHAPE=false},modOptions={DRAMALESS_SHAPE={daytime="dusk",renderScale=1,renderDistanceSetting=16}},
        activeProfile="my-profile",fpsCap=60,customFuture={keep="mine"}}
      for _,entry in ipairs(prior)do options.jpStarterPackV1[entry.id]=entry.version end
      if mode=="edited" then assert(fs.write("mods/DRAMALESS_SHAPE/main.lua",original["main.lua"].."\n-- custom\n"))end
      if mode=="extra" then assert(fs.write("mods/DRAMALESS_SHAPE/custom.txt","custom"))end
      if mode=="missing-file" then assert(fs.remove("mods/DRAMALESS_SHAPE/main.lua"))end
      if mode=="manual" then options.jpStarterPackV1.DRAMALESS_SHAPE="existing" end
      if mode=="removed" then remove("mods/DRAMALESS_SHAPE")end
      if mode=="duplicate" then
        assert(fs.createDirectory("mods/duplicate"))
        assert(fs.write("mods/duplicate/manifest.json",original["manifest.json"]))
      end
      assert(Save.saveOptions(options))
      local expected=snapshot("mods/DRAMALESS_SHAPE")
      local deps,installCalls=nil,0
      if mode=="backup-failure" then
        local blocked=setmetatable({createDirectory=function(path)
          if path:match("^jp%-mod%-backups/")then return false end
          return fs.createDirectory(path)
        end},{__index=fs})
        deps={fs=blocked}
      elseif mode=="install-failure" then
        deps={LauncherMods={installedVersions=Mods.installedVersions,installZip=function()
          installCalls=installCalls+1
          assert(fs.write("mods/DRAMALESS_SHAPE/main.lua","partial write"))
          return nil,"fixture installation failure"
        end}}
      end
      local result,detail=Pack.install(deps)
      local failed=mode=="backup-failure" or mode=="install-failure"
      check(failed and result==nil or not failed and result~=nil,mode.." result: "..tostring(detail or "ok"))
      local after=Save.loadOptions()
      check(after.jpDialogScale==0.5 and after.jpDotMatrix==0,mode.." display preferences retained")
      check(after.mods.DRAMALESS_SHAPE==false,mode.." disabled preference retained")
      check(after.modOptions.DRAMALESS_SHAPE.daytime=="dusk" and after.modOptions.DRAMALESS_SHAPE.renderScale==1 and after.modOptions.DRAMALESS_SHAPE.renderDistanceSetting==16,mode.." MOD options retained")
      check(after.activeProfile=="my-profile" and after.fpsCap==60 and after.customFuture.keep=="mine",mode.." other settings retained")
      for mid,files in pairs(other)do check(same(snapshot("mods/"..mid),files),mode.." preserves "..mid)end
      local versions=Mods.installedVersions()
      if mode=="pristine" then
        check(versions.DRAMALESS_SHAPE==new.version,"pristine actual jp.17 ZIP upgraded")
        check(after.jpStarterPackV1.DRAMALESS_SHAPE==new.version,"managed version advanced")
        check(same(snapshot("jp-mod-backups/jp17/DRAMALESS_SHAPE"),original),"every prior file backed up byte for byte")
      elseif mode=="removed" then
        check(versions.DRAMALESS_SHAPE==nil,"deleted MOD not restored")
      else
        check(versions.DRAMALESS_SHAPE==old.version,mode.." version retained")
        check(same(snapshot("mods/DRAMALESS_SHAPE"),expected),mode.." all files retained/restored")
        if mode=="install-failure" then check(installCalls==1,"failed installer invoked exactly once")end
      end
      if failed then
        check(Pack.install()~=nil,mode.." later normal startup retries successfully")
        check(Mods.installedVersions().DRAMALESS_SHAPE==new.version,mode.." retry reaches new version")
      end
      check(Pack.install()==false,mode.." repeat startup idempotent")
    end
    print("RESULT "..count.." checks passed")
  end,debug.traceback)
  if not ok then print(err)end
  love.event.quit(ok and 0 or 1)
end
