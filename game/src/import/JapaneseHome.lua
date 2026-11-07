-- Home presentation and explicit JP start requests. Automatic launch is
-- cold-boot only; returning from a game always leaves the home accessible.
local H={}
local Save=require('src.core.SaveData')
function H.summary(imp,version)
  imp:_ensureSlots(version)
  local slot=imp.activeSlot[version]
  local ui=imp._ui
  local key=version..':'..tostring(slot)
  if ui.homeSummaryKey==key then return ui.homeSummary end
  local raw=slot and Save.readSlotSource(version,slot)
  local save=raw and require('src.core.SaveSerializer').decode(raw)
  local info
  if save and save.player and type(save.player.map)=='string' then
    local name,meta=Save.slotSummary(save)
    local id=save.player.map
    local names=require('src.core.JapaneseStringsMenus')
    local place=names[id:gsub('_',' ')]
    local route=id:match('^ROUTE_(%d+)$')
    if route then place=route..'ばんどうろ' end
    if not place and id:find('POKECENTER',1,true) then place='ポケモンセンター' end
    if not place and id:find('REDS_HOUSE',1,true) then place='じぶんの いえ' end
    if not place and id=='OAKS_LAB' then place='オーキドけんきゅうじょ' end
    info={name=name or '',time=meta.timeText,badges=meta.badges,place=place,slot=slot}
  end
  ui.homeSummaryKey,ui.homeSummary=key,info
  return info
end
function H.restore(game)
  if require('src.core.GameVersion').get()~='red_jp' then return false end
  local ok,save,recovered=pcall(Save.load,'red_jp')
  if not ok or type(save)~='table' then return false end
  -- Same validation, MOD migrations, recovery notice and actor setup as the
  -- original Continue callback. Never writes a new or empty report.
  game:restoreSave(save,recovered,{freshBoot=true,continued=true})
  return true
end
function H.startupRequest(options,context)
  context=context or {}
  if context.relaunched or context.launcher or context.forceImport
      or context.version~='red_jp' or not context.ready then return nil end
  local mode=options and options.jpStartupScreen
  if mode=='title' then return {} end -- normal opening/title, with the saved skip choice
  if mode=='continue' then return {jpContinue=true} end
  return nil -- absent/invalid preferences keep the home
end

-- Allocate only if the current slot has any report witness (even damaged).
-- Commit the registry before booting Oak's speech; failure cannot redirect
-- autosave into an existing adventure. No progress files are written here.
function H.newAdventureSlot()
  local version='red_jp'
  local fs=Save.persistenceFs()
  Save.listSlots(version)
  local active=Save.activeSlot(version)
  local function occupied(id)
    if not id then return true end
    local path='saves/red_jp/'..id..'.lua'
    return fs.getInfo(path) or fs.getInfo(path..'.bak') or fs.getInfo(path..'.tmp')
  end
  if active and not occupied(active) then return active end
  local options=Save.loadOptions()
  local registry=(options.saveSlots or {})[version] or {list={}}
  local high=0
  for _,id in ipairs(registry.list or {})do
    high=math.max(high,tonumber(tostring(id):match('^slot(%d+)$')) or 0)
  end
  local id
  repeat high=high+1;id='slot'..high until not occupied(id)
  local witness={}
  for _,n in ipairs({'options.lua','options.lua.bak','options.lua.tmp'})do witness[n]=fs.read(n) or false end
  registry.list=registry.list or {};registry.list[#registry.list+1]=id;registry.active=id
  options.saveSlots=options.saveSlots or {};options.saveSlots[version]=registry
  local ok,written=pcall(Save.saveOptions,options)
  local decoded=require('src.core.SaveSerializer').decode(fs.read('options.lua') or '')
  local stored=decoded and decoded.saveSlots and decoded.saveSlots[version]
  if not ok or not written or not stored or stored.active~=id then
    for n,b in pairs(witness)do
      if b then fs.write(n,b) elseif fs.getInfo(n) then fs.remove(n) end
    end
    Save.invalidateOptions();Save.refreshSlotResolution(version)
    return nil,'レポートを よういできません'
  end
  Save.refreshSlotResolution(version)
  return id
end
function H.startNew(game)
  local id,err=H.newAdventureSlot()
  if not id then return false,err end
  game:startNewGame()
  return true
end
function H.launch(game,options)
  if require('src.core.GameVersion').get()~='red_jp' then return false end
  if options.jpNewGame then return H.startNew(game) end
  if options.jpContinue then return H.restore(game) end
  return false
end
return H
