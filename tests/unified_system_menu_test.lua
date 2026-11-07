-- Real Game, native START input, stack, Options rows and registered MOD screens.
-- No ROM; only handwritten state. Rendering has a separate genuine GL fixture.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Unified Japanese system menu')
local Game=require('src.core.Game')
local Input=require('src.core.Input');Input:init()
require('src.core.TouchControls'):init()
local Stack=require('src.core.StateStack');Stack:init()
local Screens=require('src.ui.Screens')
local Save=require('src.core.SaveData')
local Session=require('src.ui.SessionMenu')
local OW=require('src.world.OverworldController')
local Runtime=require('src.mods.Runtime')
local Hooks=require('src.mods.Hooks')
local Fixed=require('src.core.FixedStep')
require('src.core.GameVersion').set('red_jp')
local writes,progress,homes,steps,actions,releases=0,0,0,0,0,0
Game.data={constants={language='ja'},screens={}}
Game.save=Save.newGame();Game.save.player.name='テスト';Game.save.party={};Game.save.flags={}
Game.stack,Game.input=Stack,Input
Game.mods={releaseModInput=function()releases=releases+1 end}
Game.writeOptions=function(self)writes=writes+1;return Save.saveOptions(self.save.options,love.filesystem)end
Game.writeSave=function()progress=progress+1;return true end
Game.applyOptions=function()end
Game.returnToLauncher=function()homes=homes+1 end
require('src.core.Sound').play=function()end
local ow=setmetatable({player={moving=false},scriptMoves={},runner={isRunning=function()return false end}}, {__index=OW})
Game.overworld=ow;Stack.states={ow}
for i=1,100 do local n=debug.getupvalue(OW.handleInput,i);if not n then break end;if n=='Game'then debug.setupvalue(OW.handleInput,i,Game)end end
local oldFixed=Fixed.update
Fixed.update=function()error('underlying fixed simulation must remain paused')end
local function pulse(button)
 Input:sourcePress(button,'qa');Input:sourceRelease(button,'qa');Game:update(1/60)
end
local function hostBack(key)Game:keypressed(key or 'acback');Game:keyreleased(key or 'acback');if (Game.pendingSystemBack or #Input.pressQueue>0) and not Game.sessionMenu then Game:update(1/60)end end
local function rootCount()local n=0;for _,s in ipairs(Stack.states)do if s.isSystemMenuRoot then n=n+1 end end;return n end
local function choose(id)
 local state=Stack:top()
 for i,row in ipairs(state.items or state.view or state.rows or {})do
  if row.id==id then state.index=i;pulse('a');return end
 end
 error('missing row '..id)
end
local function nativeStart()
 Input:sourcePress('start','qa');Input:sourceRelease('start','qa');Input:step();ow:handleInput()
end
local hooks=Hooks.new()
hooks:wrap('ui.options.rows',function(next,game,rows)
 rows=next(game,rows)
 rows[#rows+1]={id='custom-step',label='CUSTOM STEP',value=function()return tostring(steps)end,step=function()steps=steps+1;return true end}
 rows[#rows+1]={id='custom-open',label='CUSTOM SCREEN',activate=function(g)actions=actions+1;Screens.push(g,'IndependentModOptions')end}
 return rows
end)
Runtime.install(Runtime.events,hooks,{})
local customStep=0
Game.data.screens.IndependentModOptions={new=function(g)
 local s={game=g,index=1,scroll=0,isOpaque=true,rows={{label='EXTERNAL OPTION',value=function()return tostring(customStep)end,step=function()customStep=customStep+1 end}}}
 function s:update()if Input:wasPressed('a')then self.rows[self.index].step(g)elseif Input:wasPressed('b')then Stack:pop()end end
 function s:draw()error('old full white renderer must be bypassed')end
 return s
end}
Input:keypressed('right');nativeStart()
local root=Stack:top()
T.check(root.isSystemMenuRoot and not Game.sessionMenu,'native START opens sole native root without separate pause hub')
T.eq(rootCount(),1,'exactly one root')
T.check(not Input:isDown('right') and releases>0,'native START clears gameplay and MOD holds')
T.check(Game:systemMenuCanSave(),'idle root is safe for system save')
choose('system-settings');local options=Stack:top()
T.check(options.floatingPanel and options.systemMenuPause and not options.isOpaque,'native OPTION uses floating dense panel')
T.eq(Stack.states[#Stack.states-1],root,'settings retains same parent root')
T.check(Game:systemMenuCanSave(),'known Options chain still permits safe save/import')
choose('group.audio');T.eq(Stack:top().screenId,'OptionsMenu','category opens same actual Options implementation')
local prior=Game.save.options.musicVol;pulse('left')
T.eq(Game.save.options.musicVol,prior-1,'actual audio row changes')
T.eq(Save.loadOptions(love.filesystem).musicVol,prior-1,'actual keyboard row persists')
hostBack();T.eq(Stack:top(),options,'one host Back closes one category')
choose('custom-step');T.eq(steps,1,'original ui.options.rows step executes once')
choose('custom-open');local custom=Stack:top()
T.eq(actions,1,'original hook action executes once')
T.eq(custom.screenId,'IndependentModOptions','registered screen identity preserved')
T.check(custom.floatingPanel and custom.systemMenuPause,'descriptor-based original MOD screen inherits dense floating panel')
T.check(not Game:systemMenuCanSave(),'custom screen is not mistaken for trusted Options save context')
pulse('a');T.eq(customStep,1,'original custom update and callback retained')
hostBack();T.eq(Stack:top(),options,'custom B returns to original Options')
choose('jpSettingsFiles');local file=Game.sessionMenu
T.check(file and file.page=='settings-files','settings import/export reachable from unified root')
T.check(file:canSave(),'file import remains allowed over exact safe root and Options')
local candidate=Save.defaultOptions();candidate.musicVol=3;candidate.jpDialogScale=.5
T.check(file:applyImportedSettings(candidate),'settings import applies safely from in-game root')
T.eq(Game.save.options.jpDialogScale,.5,'explicit imported preference preserved')
Game:closeSessionMenu()
hostBack();T.eq(Stack:top(),root,'Options Back returns to one retained START root')
hostBack();T.eq(Stack:top(),ow,'root Back resumes original world')
T.eq(rootCount(),0,'no duplicate root remains')
Game:gamepadpressed(nil,'guide');Game:gamepadreleased(nil,'guide')
T.check(Stack:top().isSystemMenuRoot and not Game.sessionMenu,'Guide opens same root as START')
choose('system-close');T.eq(Stack:top(),ow,'Close means resume, without reset/title')
T.eq(homes,0,'closing does not return home')
Game:keypressed('acback');Game:keyreleased('acback');choose('system-home')
local home=Game.sessionMenu;T.check(home and home:canSave(),'home confirmation sees safe root')
T.check(home:goHome(true),'save and home works from root')
T.eq(progress,1,'safe home writes one progress report');T.eq(homes,1,'home callback fires once')
Game:closeSessionMenu();hostBack()
for _,reason in ipairs({'battle','dialogue','moving','inputLocked','flyAnim','teleportOut','hopLand'})do
 Stack.states={ow};Game.sessionMenu=nil;ow.player.moving=false;ow.player.inputLocked=false;ow.flyAnim=nil;ow.teleportOut=nil;ow.hopLand=nil
 local base=ow
 if reason=='battle' or reason=='dialogue'then base={screenId=reason,update=function()error('underlying state advanced')end};Stack:push(base)
 elseif reason=='moving' or reason=='inputLocked'then ow.player[reason]=true
 elseif reason=='hopLand'then ow.hopLand=2 else ow[reason]={frames=9}end
 Game:keypressed('acback');Game:keyreleased('acback');local restricted=Stack:top()
 T.check(restricted.isSystemMenuRoot and not restricted.systemMenuSafe,reason..' gets restricted same menu')
 T.check(not Game:systemMenuCanSave(),reason..' refuses save/import')
 -- Every non-system native/mod action is blocked, including SAVE and BAG.
 for i,row in ipairs(restricted.items)do if not row.systemOperation then
  restricted.index=i;pulse('a')
  T.check(Game.sessionMenu and Game.sessionMenu.page=='blocked',reason..' blocks '..row.label)
  Game:keypressed('acback');Game:keyreleased('acback')
  T.check(not Game.sessionMenu and Stack:top()==restricted,'blocked notice returns directly to menu')
 end end
 choose('system-settings');local opt=Stack:top();choose('group.graphics')
 local graphic=Stack:top();choose('colors')
 T.check(Game.sessionMenu and Game.sessionMenu.page=='blocked',reason..' color activation is guarded')
 Game.sessionMenu:acknowledge();T.check(not Game.sessionMenu and Stack:top()==graphic,'color notice closes without empty extra hub')
 hostBack();hostBack();hostBack()
 T.eq(Stack:top(),base,reason..' resumes exact original state')
 T.eq(progress,1,reason..' never writes progress')
end
Stack.states={ow};ow.player.moving=false;ow.player.inputLocked=false;ow.flyAnim=nil;ow.teleportOut=nil;ow.hopLand=nil
ow.player.inputLocked=true;nativeStart()
T.check(not Stack:top().systemMenuSafe,'native START also restricts a locked player')
T.check(not Game:systemMenuCanSave(),'native START cannot bypass locked-world save safety')
hostBack();ow.player.inputLocked=false
nativeStart();choose('system-settings');local parent=Stack:top()
local bindings=require('src.ui.BindingsMenu').new(Game);bindings.systemMenuBranch=true;bindings.systemMenuPause=true;Stack:push(bindings)
bindings:beginCapture(bindings.items[1]);hostBack()
T.check(not bindings.capture and Stack:top()==bindings,'host Back cancels binding capture exactly one level')
hostBack();T.eq(Stack:top(),parent,'second Back closes bindings')
local static={};Stack:push(static)
T.check(pcall(Game.update,Game,1/60),'direct-pushed static MOD child remains paused with optional update');Stack:pop()
Fixed.update=oldFixed
Runtime.reset()
T.finish()
