return function(Game,Renderer,check,write,imp,original,kept,firstPath)
 local fs,g=love.filesystem,love.graphics
 local Save=require('src.core.SaveData');local Home=require('src.import.JapaneseHome')
 local S=require('src.core.SaveSerializer');local Pref=require('src.ui.JapaneseConvenienceSettings')
 local C=require('src.ui.JapaneseSettingsCatalog');local Transfer=require('src.import.SettingsTransfer')
 local options=Save.loadOptions();options.jpStartupScreen='title';options.jpSkipIntro=false;Save.saveOptions(options)
 check(Save.loadOptions().jpStartupScreen=='title','startup choice persists')
 local settings=assert(Transfer.export(Save.loadOptions()))
 local imported=assert(Transfer.import(settings,Save.defaultOptions()))
 check(imported.jpStartupScreen=='title' and imported.jpSkipIntro==false,'backup/settings retain startup and explicit opening OFF')
 local model=require('src.import.LauncherSettings').open({},'red_jp')
 local found={}
 for _,section in ipairs(model.sections)do for _,row in ipairs(section.rows)do
  if row.id=='jpStartupScreen' or row.id=='jpSkipIntro' then found[row.id]=(found[row.id] or 0)+1 end
 end end
 check(found.jpStartupScreen==1 and found.jpSkipIntro==1,'exactly one startup selector and opening switch')
 check(C.group('jpStartupScreen')=='startup' and C.group('jpSkipIntro')=='startup','startup settings share their own category')
 local pref;for _,row in ipairs(Pref.rows)do if row.id=='jpStartupScreen' then pref=row end end
 local o={};for _,mode in ipairs({'title','continue','home'})do Pref.step(pref,o,1);check(o.jpStartupScreen==mode,'both settings surfaces cycle to '..mode)end
 local ctx={ready=true,version='red_jp'}
 for _,mode in ipairs({'home','title','continue','invalid'})do
  local req=Home.startupRequest({jpStartupScreen=mode},ctx)
  check((mode=='home' or mode=='invalid') and req==nil or mode=='title' and req and not req.jpContinue or mode=='continue' and req and req.jpContinue,'cold startup route '..mode)
 end
 for _,key in ipairs({'relaunched','launcher','forceImport'})do
  ctx[key]=true;check(Home.startupRequest({jpStartupScreen='continue'},ctx)==nil,key..' keeps home available');ctx[key]=nil
 end
 ctx.ready=false;check(not Home.startupRequest({jpStartupScreen='title'},ctx),'missing ROM stays at importer')
 ctx.ready=true;ctx.version='red';check(not Home.startupRequest({jpStartupScreen='title'},ctx),'other games keep their existing boot path')
 ctx.version='red_jp'
 local started,restored=0,0
 local stub={startNewGame=function()started=started+1 end,restoreSave=function()restored=restored+1 end}
 Save.setActiveSlot('red_jp',original)
 check(Home.launch(stub,{jpContinue=true}) and restored==1 and started==0,'Continue uses existing save only')
 local originalPath=Save.saveFilename('red_jp');local originalBytes=fs.read(originalPath)
 check(Home.launch(stub,{jpNewGame=true}) and started==1,'New Game prepares a separate native slot')
 local fresh=Save.activeSlot('red_jp')
 check(fresh~=original and not fs.getInfo(Save.saveFilename('red_jp')),'New Game has a new active slot without inventing progress')
 check(fs.read(originalPath)==originalBytes and fs.read(firstPath)==kept,'all old progress remains byte-identical after New Game')
 check(Home.newAdventureSlot()==fresh,'empty active slot is reused')
 check(not Home.launch(stub,{jpContinue=true}),'empty slot Continue falls back to title')
 Save.writeSlot('red_jp',fresh,Save.newGame({version='red_jp'}))
 check(fs.read(originalPath)==originalBytes,'a later report in the new slot cannot overwrite the old adventure')
 Save.setActiveSlot('red_jp',original)
 local witness=fs.read('options.lua');local native=fs.write;local fail=true
 fs.write=function(n,b,...)
  if n=='options.lua' and fail then fail=false;native(n,'partial');return nil,'fixture full disk' end
  return native(n,b,...)
 end
 local ok=Home.startNew(stub);fs.write=native
 check(not ok and started==1,'failed registry write never starts New Game')
 check(fs.read('options.lua')==witness and Save.activeSlot('red_jp')==original,'failed new slot commit restores selected report')
 check(fs.read(originalPath)==originalBytes,'failed new slot commit preserves old report')
 local function draw(w,h,name)
  love.window.setMode(w,h,{resizable=true});local c=g.newCanvas(w,h);g.setCanvas(c);imp:draw();g.setCanvas()
  write(name..'.png',c:newImageData():encode('png'):getString());c:release()
 end
 imp:_refreshSlots('red_jp');imp._ui.page='games';imp._handedOff=false
 draw(480,800,'home-separated-actions')
 local rows={};for _,row in ipairs(imp._ui.rows)do rows[row.id]=row end
 check(rows.play and rows['new-game'] and rows['open-title'],'Continue/New Game/Title are independent controls')
 check(imp._ui.panel.labels[2].card and imp._ui.panel.labels[3].card,'New Game and Title have separate visible frames')
 local calls,request=0;imp.onComplete=function(_,_,o)calls=calls+1;request=o end
 rows['open-title'].action();check(calls==1 and request==nil,'Title action does not ask to Continue')
 imp._handedOff=false;rows['new-game'].action();check(calls==2 and request.jpNewGame and not request.jpContinue,'New Game has its own explicit request')
 rows['new-game'].action();check(calls==2,'duplicate tap cannot launch twice')
 imp._handedOff=false
 imp:_openSettings();draw(480,800,'settings-categories')
 local startupIndex
 for i,section in ipairs(imp._settings.sections)do if section.id=='startup' or section.title=='きどう・ホーム' then startupIndex=i end end
 check(startupIndex~=nil,'startup category is accessible in actual settings')
 imp._ui.page='settings-detail';imp._ui.settingsSection=startupIndex;imp._ui.focus=1
 draw(480,800,'startup-settings')
 Save.setActiveSlot('red_jp',original)
end
