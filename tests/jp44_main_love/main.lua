-- Real main.lua cold boot and return path; only missing ROM readiness and
-- Game's data-heavy load boundary are substituted. No cartridge required.
local root=assert(os.getenv('JP_QA_ROOT'))
assert(loadfile(root..'/main.lua'))()
local originalLoad,originalUpdate=love.load,love.update
local function run()
 local mode=os.getenv('JP44_CASE') or 'home'
 local checkCount=0
 local function check(ok,label)assert(ok,label);checkCount=checkCount+1;print('PASS '..label)end
 local Save=require('src.core.SaveData')
 local options=Save.defaultOptions()
 options.lastVersion=mode=='other' and 'red' or 'red_jp'
 options.jpStartupScreen=mode=='home' and 'home' or mode=='title' and 'title' or 'continue'
 options.jpSkipIntro=false
 assert(Save.saveOptions(options))
 if mode=='marker' then love.filesystem.write('relaunch_to_launcher.txt','1')end
 local Imp=require('src.import.RomImporter');local originalNew=Imp.new
 local importer,made,loaded,request,game= nil,0,0
 Imp.isReady=function(version)return mode~='missing' and (version=='red_jp' or mode=='other' and version=='red')end
 Imp.new=function(...)
  importer=originalNew(...);made=made+1;return importer
 end
 package.preload['src.core.Game']=function()
  game={data={constants={language='ja'}},focus=function()end,visible=function()end,
    load=function(self,opts)loaded=loaded+1;request=opts end}
  return game
 end
 local args=mode=='forced' and {'--launcher'} or {}
 originalLoad(args)
 if mode=='title' or mode=='continue' then
  check(loaded==1 and made==1,'real cold boot hands off once '..mode)
  check(mode=='continue' and request.jpContinue or mode=='title' and not request.jpContinue,'bootGame forwards chosen start action '..mode)
  check(Save.loadOptions().jpSkipIntro==false,'auto startup does not rewrite movie preference')
  game.returnToLauncher({tab='red_jp'});originalUpdate(1/60)
  check(made==2 and loaded==1 and not importer._handedOff,'return to home does not auto-start again')
  importer:play('red_jp',{jpNewGame=true})
  check(loaded==2 and request.jpNewGame and not request.jpContinue,'home New Game reaches Game.load separately')
 else
  check(loaded==0 and made==1 and not importer._handedOff,'real entry keeps home for '..mode)
 end
 print(checkCount..' JP44 REAL MAIN CHECKS PASSED')
end
function love.load()
 local ok,err=xpcall(run,debug.traceback)
 if not ok then print(err)end
 -- Do not run the ordinary game event loop after this boundary test.
 love.update=function()end;love.draw=function()end;love.quit=function()end
 love.event.quit(ok and 0 or 1)
end
function love.errorhandler(message)
 print('MAIN FIXTURE ERROR '..tostring(message)..'\n'..debug.traceback())
 return function()return 1 end
end
