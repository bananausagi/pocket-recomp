-- Real main.lua editor handoff; only cartridge readiness and Game.load are
-- substituted. Verify save/resume through the actual host callbacks.
local root=assert(os.getenv('JP_QA_ROOT'))
assert(loadfile(root..'/main.lua'))()
local load,draw,focus=love.load,love.draw,love.focus
local function run()
 local checks=0
 local function check(ok,label)assert(ok,label);checks=checks+1;print('PASS '..label)end
 local Save=require('src.core.SaveData');local A=require('src.core.JapaneseTouchAreas')
 local opts=Save.defaultOptions();opts.lastVersion='red_jp';opts.jpStartupScreen='home'
 opts.jpTouchOptimized=true;opts.jpTouchAreas=A.normalize();assert(Save.saveOptions(opts))
 local Imp=require('src.import.RomImporter');local new=Imp.new;local importer,game
 Imp.isReady=function(version)return version=='red_jp'end
 Imp.new=function(...)importer=new(...);return importer end
 local cleared=0
 package.preload['src.core.Game']=function()
  game={data={constants={language='ja'}},focus=function()end,visible=function()end,
   load=function(self)self.save={options=Save.loadOptions()}end,
   clearSessionInput=function()cleared=cleared+1;require('src.core.TouchControls'):reset()end}
  return game
 end
 load({})
 check(type(importer.onEditTouchAreas)=='function','launcher receives actual editor callback')
 importer.onEditTouchAreas('red_jp')
 local E=require('src.ui.JapaneseTouchAreaEditor')
 check(not E.closed and E.onClose~=nil,'launcher opens area editor via main host')
 draw();E.data.portrait.back.x=.4;E.data.portrait.back.y=.6;E.close(true)
 check(Save.loadOptions().jpTouchAreas.portrait.back.x==.4,'launcher editor persists configured position')
 importer:play('red_jp',{jpContinue=true})
 check(game and type(game.openTouchAreasEditor)=='function','booted Japanese game receives editor hook')
 local stack={};local sheet={};game.stack=stack;game.sessionMenu=sheet
 game.save.options.jpBattleSpacing='wide'
 local touch=require('src.core.TouchControls');touch.active=true;touch.sessionMenuActive=true
 game:openTouchAreasEditor();check(not E.closed and cleared==1,'in-game editor clears held input at entry')
 draw();local p=E.layout().preview;E.touchpressed('focus',p.x+p.w*.5,p.y+p.h*.6)
 focus(false);check(not E.pointer and not E.drag,'main forwards focus loss to area editor')
 E.data.portrait.back.x=.55;E.data.portrait.back.y=.7;E.close(true)
 check(game.save.options.jpTouchAreas.portrait.back.x==.55,'closing editor applies saved areas to running game')
 check(game.stack==stack and game.sessionMenu==sheet and game.save.options.jpBattleSpacing=='wide',
   'editor preserves paused state and unrelated live options')
 check(cleared==2 and touch.active and touch.sessionMenuActive,'editor restores controls with no held input')
 game:openTouchAreasEditor();E.data.portrait.back.x=.25;E.close(false)
 check(game.save.options.jpTouchAreas.portrait.back.x==.55,'Cancel returns to game with previous placement')
 print(checks..' JP48 REAL MAIN EDITOR CHECKS PASSED')
end
function love.load()
 local ok,err=xpcall(run,debug.traceback);if not ok then print(err)end
 love.update=function()end;love.draw=function()end;love.quit=function()end
 love.event.quit(ok and 0 or 1)
end
function love.errorhandler(message)
 print('MAIN FIXTURE ERROR '..tostring(message)..'\n'..debug.traceback())
 return function()return 1 end
end
