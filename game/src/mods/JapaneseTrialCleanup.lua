-- jp.39: the user retired the trial renderer completely. Archive every
-- remaining installed copy, including edited/renamed copies, before uninstall.
-- Backups are outside mods/ and are never discovered or executed.
local M={}
function M.remove(opts,fs,Json,Mods,undo)
  if opts.jpAscendantRemoved39 then return false end
  local id='VOXEL_ASCENDANT'
  local copies={};local valid=false
  for _,folder in ipairs(fs.getDirectoryItems('mods') or {})do
    local root='mods/'..folder
    local raw=fs.read(root..'/manifest.json');local m=raw and Json.decode(raw)
    if (m and m.id==id) or folder==id then
      if m and m.id==id then valid=true end
      local files={}
      local function scan(path,prefix)
        for _,name in ipairs(fs.getDirectoryItems(path) or {})do
          local full,rel=path..'/'..name,prefix..name
          local info=fs.getInfo(full)
          if info and info.type=='directory' then scan(full,rel..'/')
          elseif info and info.type=='file' then files[rel]=assert(fs.read(full))end
        end
      end
      scan(root,'');copies[#copies+1]={id=id,path=root,folder=folder,files=files}
    end
  end
  if #copies>0 then
    local base='jp-mod-backups/jp39-retired';local serial=1
    while fs.getInfo(base..'-'..serial)do serial=serial+1 end
    base=base..'-'..serial
    for _,entry in ipairs(copies)do
      for name,bytes in pairs(entry.files)do
        local path=base..'/'..entry.folder..'/'..name
        assert(fs.createDirectory(path:match('^(.*)/')),'could not create retirement backup')
        assert(fs.write(path,bytes),'could not write retirement backup')
        assert(fs.read(path)==bytes,'retirement backup verification failed')
      end
    end
    for _,entry in ipairs(copies)do undo[#undo+1]=entry end
    if valid then local removed,why=Mods.uninstall(id);assert(removed,why)end
    -- Also close an interrupted install which had already lost its manifest.
    local function erase(path)
      local info=fs.getInfo(path);if not info then return end
      if info.type=='directory' then
        for _,name in ipairs(fs.getDirectoryItems(path) or {})do erase(path..'/'..name)end
      end
      assert(fs.remove(path),'could not remove retired trial')
    end
    for _,entry in ipairs(copies)do erase(entry.path)end
  end
  local function select(bucket)
    if type(bucket)~='table' then return end
    if bucket[id]==true then bucket.DRAMALESS_SHAPE=true end
    bucket[id]=false
  end
  select(opts.mods)
  for _,bucket in pairs(opts.modsByVersion or {})do select(bucket)end
  for _,profile in ipairs(opts.modProfiles or {})do
    select(profile.enabled)
    for _,bucket in pairs(profile.enabledByVersion or {})do select(bucket)end
  end
  opts.jpAscendantRemoved39=true
  return true
end
return M
