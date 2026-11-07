local source=assert(os.getenv('JP_SOURCE'), 'Set JP_SOURCE to the source root') .. '/'
package.path=source..'?.lua;'..source..'?/init.lua;'..package.path
function love.load()
 local ok,why=pcall(function()
  local M=require('src.mods.LauncherMods')
  local S=require('src.core.SaveData')
  local fs=love.filesystem
  local checks=0
  local function check(value,description) checks=checks+1; assert(value,description); print('PASS '..description) end
  local function erase(path)
   local i=fs.getInfo(path);if not i then return end
   if i.type=='directory' then for _,n in ipairs(fs.getDirectoryItems(path)) do erase(path..'/'..n) end end
   fs.remove(path)
  end
  erase('mods');erase('jp-mod-transactions');fs.remove('options.lua');fs.remove('options.lua.bak');fs.remove('options.lua.tmp')
  local installed,id=M.installZip('fixtures/valid.zip')
  check(installed and id=='qa_mod','real ZIP installs through LOVE filesystem: '..tostring(id))
  check(M.installedVersions().qa_mod=='1.0.0','installed version discovery')
  local schemas=M.optionSchemas('red_jp')
  check(#schemas==1 and #schemas[1].schema==1 and schemas[1].schema[1].default==true,'schema data arrays and comments parse without script execution')
  check(M.translationStrings()['Import ROM']=='ROMを読む','translation catalog parses')
  check(not M.installZip('fixtures/update.zip'),'duplicate id denied without explicit replacement')
  for _,filename in ipairs({'traversal.zip','case.zip','rom.zip','symlink.zip','badmanifest.zip','missingentry.zip','backslash-traversal.zip','drive.zip','alias.zip'}) do
   local accepted,err=M.installZip('fixtures/'..filename,{replace=true})
   check(not accepted and type(err)=='string','reject '..filename)
   check(M.installedVersions().qa_mod=='1.0.0','keep previous MOD after '..filename)
  end
  for _,filename in ipairs({'dot.zip','backslash.zip'}) do
   check(M.installZip('fixtures/'..filename,{replace=true,expectId='qa_mod'}),'safe path normalization '..filename)
  end
  fs.createDirectory('mods/qa_mod/baseroms');fs.write('mods/qa_mod/baseroms/local.dat','user-private-data')
  check(M.setEnabled('qa_mod',false,'red_jp'),'toggle reports successful persistence')
  check(M.setModOptions('qa_mod',{toggle=false}),'options report successful persistence')
  check(M.installZip('fixtures/update.zip',{replace=true,expectId='qa_mod'}),'valid replacement installs')
  check(M.installedVersions().qa_mod=='2.0.0','updated version is discoverable')
  check(fs.read('mods/qa_mod/baseroms/local.dat')=='user-private-data','updates preserve local imported data')
  check(M.list('red_jp')[1].enabled==false and M.modOptions().qa_mod.toggle==false,'updates preserve enabled flags and options')
  -- A filesystem failure after the first old directory moved must restore it.
  local realRename=os.rename
  os.rename=function(from,to)
   if from:match('/new$') then return nil,'injected commit failure' end
   return realRename(from,to)
  end
  local accepted=M.installZip('fixtures/valid.zip',{replace=true})
  os.rename=realRename
  check(not accepted and M.installedVersions().qa_mod=='2.0.0','failed activation rolls back previous version')
  check(fs.read('mods/qa_mod/baseroms/local.dat')=='user-private-data','rollback preserves private imported data')
  M.saveProfile('test');M.setEnabled('qa_mod',true,'red_jp');M.saveProfile('enabled')
  M.setEnabled('qa_mod',false,'red_jp');M.applyProfile('test')
  check(M.list('red_jp')[1].enabled==true,'active profile sync retains edited profile independently')
  check(M.uninstall('qa_mod') and not M.installedVersions().qa_mod,'uninstall removes installed MOD')
  check(not M.uninstall('../escape'),'uninstall rejects unsafe ids')
  for _,name in ipairs({'DRAMALESS_SHAPE','running_shoes','erilab_bottomless_bag','SHINY_POKEMON','ACCESS_PC_ANYWHERE','CONTROLLER_RUMBLE','all_pokemon_catchable_151_mod'}) do
   local ok,id=M.installZip(source..'assets/jp-mods/'..name..'.zip',{expectId=name})
   check(ok and id==name,'bundled original-format ZIP '..name..': '..tostring(id))
  end
  local originals=os.getenv('JP_ORIGINAL_MODS')
  if originals then
   for _,name in ipairs({'DRAMALESS_SHAPE','running_shoes','erilab_bottomless_bag','SHINY_POKEMON','ACCESS_PC_ANYWHERE','CONTROLLER_RUMBLE','useful_move_info','exp_share','trainer_rematch'}) do
    local ok,id=M.installZip(originals..'/'..name..'.zip',{expectId=name,replace=true})
    check(ok and id==name,'unmodified author ZIP '..name..': '..tostring(id))
   end
  end
  print('JP independent MOD service: '..checks..' checks passed')
 end)
 if not ok then print('FAIL '..tostring(why)) end
 love.event.quit(ok and 0 or 1)
end
