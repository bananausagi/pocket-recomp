local M={}
local function same(a,b)
 if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
function M.cold(options,check)
 local priorLanguage=options.jpLauncherLanguage;options.jpLauncherLanguage='ja'
 local fs=love.filesystem;local Json=require('src.link.Json')
 local snapshot=fs.read('mod_option_schemas.json')
 local original=options.modOptions.DRAMALESS_SHAPE
 for _,mode in ipairs({'missing','stale'})do
  if mode=='missing' then fs.remove('mod_option_schemas.json')
  else fs.write('mod_option_schemas.json',Json.encode({mods={DRAMALESS_SHAPE={{key='grid',type='toggle',label='GRID',default=false}}}}))end
  local before=fs.read('mod_option_schemas.json')
  options.modOptions.DRAMALESS_SHAPE={borderDepth=20,clouds=false,weather='clear',buildingHeight=1,sceneryFade=false}
  local model=require('src.import.LauncherSettings').open({options=options},'red_jp')
  local rows,world={},nil
  for _,section in ipairs(model.sections)do
   if section.id=='world'then world=section end
   for _,row in ipairs(section.rows)do rows[row.id]=row end
  end
  local r=assert(rows['DRAMALESS_SHAPE.borderDepth'])
  check(r.label=='そとの けしきの ひろさ' and r.value()=='ひろい',mode..' snapshot: exterior row visible before game boot ['..tostring(r.label)..' / '..tostring(r.value())..']')
  check(world.rows[2]==r,mode..' snapshot: exterior row second, directly below 3D view')
  check(rows['DRAMALESS_SHAPE.weather'].value()=='はれ',mode..' snapshot: new weather values visible')
  local fade=assert(rows['DRAMALESS_SHAPE.sceneryFade'])
  check(fade.label=='えんけいの フェード' and fade.value()=='オフ',mode..' cold launcher preserves scenery fade OFF')
  check(require('src.ui.JapaneseSettingsCatalog').group(fade.id)=='fieldEffects',mode..' fade belongs to field effects')
  check(rows['DRAMALESS_SHAPE.clouds']==nil,mode..' snapshot: obsolete cloud setting removed')
  check(rows['DRAMALESS_SHAPE.buildingHeight'].value()=='もとの たかさ',mode..' snapshot: house scale can be restored')
  r.step(1);check(options.modOptions.DRAMALESS_SHAPE.borderDepth==4,mode..' cold launcher writes real scenery key')
  check(fs.read('mod_option_schemas.json')==before,mode..' opening launcher executes no MOD schema writer')
 end
 options.modOptions.DRAMALESS_SHAPE=original;options.jpLauncherLanguage=priorLanguage
 if snapshot then fs.write('mod_option_schemas.json',snapshot)else fs.remove('mod_option_schemas.json')end
end
function M.live(Game,check)
 local fs=love.filesystem
 local data=assert(require('src.core.SaveSerializer').decode(fs.read('mods/DRAMALESS_SHAPE/options.lua'),{allowArray=true,allowComments=true}))
 check(same(data,Game.mods.optionSchemas.DRAMALESS_SHAPE),'shipped cold schema matches every actual runtime definition')
 local rows=require('src.ui.OptionsMenu').new(Game).rows;local seen={}
 for _,r in ipairs(rows)do seen[r.id]=r end
 check(seen['DRAMALESS_SHAPE:clouds']==nil,'obsolete cloud row absent in live menu')
 for _,key in ipairs({'borderDepth','buildingHeight','weather','daytime','sceneryFade'})do
  check(seen['DRAMALESS_SHAPE:'..key]~=nil,'in-game row available: '..key)
 end
end
return M
