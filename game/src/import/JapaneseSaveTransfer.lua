-- Lossless Kanto JP backup, carried by the existing Android .sav picker.
-- This is an app backup, not a cartridge SRAM conversion. Only the bounded
-- literal-table parser reads it; imported bytes are never executed as Lua.
local S=require('src.core.SaveSerializer')
local Save=require('src.core.SaveData')
local Settings=require('src.import.SettingsTransfer')
local T={MAGIC='KANTO-JP-SAVE/1\n',MAX_BYTES=8*1024*1024}
local function hash(bytes)
  return love.data.encode('string','hex',love.data.hash('sha256',bytes))
end
function T.matches(bytes)return type(bytes)=='string' and bytes:sub(1,#T.MAGIC)==T.MAGIC end
local function valid(save)
  return type(save)=='table' and save.version=='red_jp'
    and type(save.meta)=='table' and type(save.meta.format)=='number'
    and save.meta.format<=require('src.core.Version').saveFormat
    and type(save.player)=='table' and type(save.player.map)=='string'
    and type(save.player.name)=='string' and type(save.player.x)=='number'
    and type(save.player.y)=='number' and type(save.party)=='table'
    and #save.party<=6 and type(save.inventory)=='table' and type(save.flags)=='table'
end
function T.encode(save,options)
  if not valid(save) then return nil,'にほんごばんの レポートを よめません。' end
  local settings,err=Settings.export(options)
  if not settings then return nil,err end
  local copy={};for k,v in pairs(save)do if k~='options' then copy[k]=v end end
  local ok,body=pcall(S.encode,{game='red_jp',format=1,save=copy,settings=settings})
  if not ok or #body>T.MAX_BYTES-100 then return nil,'レポートを かきだせません。' end
  return T.MAGIC..hash(body)..'\n'..body
end
function T.decode(bytes)
  if not T.matches(bytes) then return nil,'ポケットリコンプの バックアップを えらんでください。' end
  if #bytes>T.MAX_BYTES then return nil,'バックアップが おおきすぎます。' end
  local digest,body=bytes:sub(#T.MAGIC+1):match('^([a-f0-9]+)\n(.*)$')
  if not body or #digest~=64 or hash(body)~=digest then return nil,'バックアップが こわれています。' end
  local doc,err=S.decode(body,{maxBytes=T.MAX_BYTES,maxDepth=48,maxNodes=250000,maxStringBytes=1048576})
  if not doc then return nil,err end
  if doc.format~=1 or doc.game~='red_jp' or not valid(doc.save) or type(doc.settings)~='string' then
    return nil,'このバックアップは よみこめません。'
  end
  return doc
end
function T.import(bytes,version)
  if version~='red_jp' then return false,'にほんごばんの ホームから よみこんでください。' end
  local doc,err=T.decode(bytes);if not doc then return false,err end
  local fs=Save.portableFs() or love.filesystem
  Save.listSlots(version) -- complete any legacy migration before snapshotting
  local candidate,why=Settings.import(doc.settings,Save.loadOptions())
  if not candidate then return false,why end
  local registry=(candidate.saveSlots or {})[version] or {list={}}
  local high=0
  for _,id in ipairs(registry.list or {})do high=math.max(high,tonumber(id:match('^slot(%d+)$')) or 0)end
  local id,path
  repeat
    high=high+1;id='slot'..high;path='saves/red_jp/'..id..'.lua'
  until not fs.getInfo(path) and not fs.getInfo(path..'.bak') and not fs.getInfo(path..'.tmp')
  -- Complete and verify the new slot before making it selectable. Old slots
  -- are never targets, even when an unregistered file was left by a crash.
  doc.save.options=nil
  local encoded=S.encode(doc.save)
  local ok,writeErr=Save.writeSlot(version,id,doc.save)
  if not ok or fs.read(path)~=encoded then
    for _,suffix in ipairs({'','.bak','.tmp'})do fs.remove(path..suffix)end
    return false,'レポートを ほぞんできません。 '..tostring(writeErr or '')
  end
  local witness={}
  for _,n in ipairs({'options.lua','options.lua.bak','options.lua.tmp'})do witness[n]=fs.read(n) or false end
  registry.list=registry.list or {};registry.list[#registry.list+1]=id;registry.active=id
  candidate.saveSlots=candidate.saveSlots or {};candidate.saveSlots[version]=registry
  if not Save.saveOptions(candidate) then
    -- Preserve the existing active slot/settings on a failed commit. Keep
    -- the verified new file orphaned if rollback itself cannot write.
    local restored=true
    for n,b in pairs(witness)do
      if b then if not fs.write(n,b) or fs.read(n)~=b then restored=false end
      elseif fs.getInfo(n) and not fs.remove(n) then restored=false end
    end
    Save.invalidateOptions();Save.refreshSlotResolution(version)
    if restored then for _,suffix in ipairs({'','.bak','.tmp'})do fs.remove(path..suffix)end end
    return false,'せっていを ほぞんできません。もとの レポートは のこっています。'
  end
  Save.refreshSlotResolution(version)
  return true,id
end
return T
