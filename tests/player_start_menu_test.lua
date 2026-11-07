-- ROM-free input/boot coverage for the Japanese title and safe start menu.
package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.modkit")
local Game=require("src.core.Game")
local Save=require("src.core.SaveData")
local Screens=require("src.ui.Screens")
local Stack=require("src.core.StateStack")
local Version=require("src.core.GameVersion")
local Runtime=require("src.mods.Runtime")
local Strings=require("src.core.Strings")
Strings.load({constants={language="ja"}})
Version.set("red_jp"); Stack:init(); Runtime.reset()
local saved, recovered, loadError
local originalLoad=Save.load
Save.load=function()
  if loadError then error("fixture read error") end
  local reason=recovered; recovered=nil
  return saved, reason
end
local key
local calls={new=0,home=0,settings=0,restore=0}
local game=setmetatable({data={constants={language="ja"},field={}},save={options={jpDialogScale=0.75,jpSkipIntro=true,
  jpIntroSeenByVersion={red_jp=true}}},stack=Stack,
  input={wasPressed=function(_,value)return value==key end}}, {__index=Game})
game.startNewGame=function()calls.new=calls.new+1 end
game.openSessionMenu=function(_,page)calls.settings=calls.settings+1;calls.page=page end
game.returnToLauncher=function()calls.home=calls.home+1 end
game.restoreSave=function(_,value,reason,options)
  calls.restore=calls.restore+1;calls.loaded=value;calls.reason=reason;calls.options=options
end
local function press(state,value)key=value;state:update(1/60);key=nil end
local function boot()
  Stack:clear()
  local title=game:pushBootTitle()
  T.eq(Stack:top(),title,"JP cold boot enters the real title without IntroMovie")
  T.check(title.isTitleScreen and not title.isPlayerStartMenu,"title art precedes start commands")
  T.eq(Game.windowScaleInStack(Stack,game.save.options),1,"title picture is independent of dialogue scale")
  for _=1,300 do if title.phase=="loop" then break end; Stack:update(1/60) end
  T.eq(title.phase,"loop","original logo animation reaches interactive title")
  return title
end
local function openMenu(title,button)
  press(title,button or "a")
  T.eq(title.phase,"exitCry","A/START leaves title through its existing sound transition")
  for _=1,30 do if Stack:top().isPlayerStartMenu then break end; Stack:update(1/60) end
  local menu=Stack:top()
  T.check(menu.isPlayerStartMenu,"title transition opens the safe JP command menu")
  T.eq(Game.windowScaleInStack(Stack,game.save.options),0.75,"post-title menu retains selected window scale")
  return menu
end
local title=boot()
T.check(title.hideRomCopyright,"standard Japanese title suppresses its footer only")
local menu=openMenu(title,"start")
T.check(menu.centerInPlayfield,"safe start menu opts into usable-playfield centering")
T.eq(#menu.menu.items,3,"no save offers new game/settings/home")
press(menu,"a");T.eq(calls.new,1,"A chooses new game without extra confirmation on empty slot")
press(menu,"down");press(menu,"a")
T.eq(calls.settings,1,"settings command is actionable")
T.eq(calls.page,"settings","settings goes directly to settings page")
press(menu,"b")
T.eq(calls.home,0,"B returns to the title without leaving the game")
T.eq(Stack:top(),title,"B pops only the command menu")
T.eq(title.phase,"drop","B restarts the original title animation")
for _=1,300 do if title.phase=="loop" then break end; Stack:update(1/60) end
menu=openMenu(title)
press(menu,"down");press(menu,"down");press(menu,"a")
T.eq(calls.home,1,"explicit home command returns to launcher")
saved={player={name="レッド"},options={}}; recovered="bak"
menu=openMenu(boot())
T.eq(#menu.menu.items,4,"valid save adds Continue")
press(menu,"a")
T.eq(calls.restore,1,"Continue restores actual save")
T.eq(calls.reason,"bak","probe recovery reason survives the fresh Continue read")
T.check(calls.options.continued and calls.options.freshBoot,"Continue preserves restoration flags")
press(menu,"down");press(menu,"a")
T.check(menu.confirming,"new game with an existing report asks first")
T.eq(menu.menu.index,1,"confirmation defaults to returning safely")
press(menu,"b");T.check(not menu.confirming,"B cancels new-game confirmation")
T.eq(calls.new,1,"cancel does not start or overwrite a save")
press(menu,"down");press(menu,"a");press(menu,"down");press(menu,"a")
T.eq(calls.new,2,"explicit confirmation starts new game")
menu=openMenu(boot());saved=nil;press(menu,"a")
T.check(menu.notice~=nil,"vanished save keeps menu visible and reports failure")
T.eq(Stack:top(),menu,"failed Continue stays on the menu, without blank title")
saved={};menu=openMenu(boot());loadError=true;press(menu,"a")
T.check(menu.notice~=nil,"read exception also stays in the menu")
menu=openMenu(boot());T.check(not menu.hasSave,"probe exceptions do not invent a save")
loadError=false;saved=false;menu=openMenu(boot())
T.check(not menu.hasSave,"non-table save result cannot enable Continue")
saved=nil;game.save.options.jpSkipIntro=false
title=game:makeTitleState()
T.check(title.isTitleScreen and title.onOpenMenu,"original-intro opt-in retains title and safe JP menu")
game.save.options.jpSkipIntro=true
Version.set("red");title=game:makeTitleState()
T.check(title.isTitleScreen and not title.onOpenMenu,"other versions retain their original title menu")
T.check(not title.hideRomCopyright,"overseas title retains copyright footer")
Version.set("red_jp")
do
  local Title=require("src.ui.TitleState")
  local Font=require("src.render.Font")
  local draw=Font.draw
  local drawn={}
  Font.draw=function(text)drawn[#drawn+1]=text end
  local clean=Title.new(game)
  clean:drawCopyright(136)
  T.eq(#drawn,0,"missing-art JP title does not reintroduce GAME FREAK text fallback")
  game.data.field.title={copyrightText="CUSTOM CREDIT"}
  local custom=Title.new(game);custom:drawCopyright(136)
  T.eq(drawn[1],"CUSTOM CREDIT","explicit conversion text credit is preserved")
  game.data.field.title=nil
  game.data.field.boot={title={gamefreakInc="custom-credit.png"}}
  T.check(not Title.new(game).hideRomCopyright,"explicit conversion footer artwork is preserved")
  game.data.field.boot=nil
  drawn={}
  local opening=require("src.ui.IntroMovie").new(game,function()end)
  opening.copyright,opening.gfInc=nil,nil
  opening:drawCopyright()
  T.eq(drawn[#drawn],"GAME FREAK inc.","first opening copyright fallback remains intact")
  Font.draw=draw
end
local factory={new=function(_,callbacks)return{custom=true,callbacks=callbacks}end}
game.data.screens={TitleState=factory};Screens.invalidate()
title=game:makeTitleState()
T.check(title.custom and not title.callbacks.onOpenMenu,"registered TitleState mod retains its own menu")
game.data.screens={CustomTitle=factory};game.data.field.boot={screens={title="CustomTitle"}}
Screens.invalidate();title=game:makeTitleState()
T.check(title.custom and not title.callbacks.onOpenMenu,"custom boot title id takes precedence")
game.data.screens={CustomSplash={new=function(_,done)return{customSplash=true,done=done}end}}
game.data.field.boot={screens={splash="CustomSplash"}}
Screens.invalidate();Stack:clear();game:pushBootTitle()
T.check(Stack:top().customSplash,"custom splash actually enters stack")
Stack:top().done();T.check(Stack:top().isTitleScreen,"custom splash callback reaches real title")
game.data.screens=nil;game.data.field.boot={screens={splash="IntroMovie"}}
Screens.invalidate();title=boot()
game.data.screens={IntroMovie={new=function(_,done)return{customSplash=true,done=done}end}}
Screens.invalidate();Stack:clear();game:pushBootTitle()
T.check(Stack:top().customSplash,"mod overriding built-in splash id keeps its boot flow")
game.data.screens=nil;Screens.invalidate()
game.save.options.jpSkipIntro=false;Stack:clear();game:pushBootTitle()
T.eq(Stack:top().screenId,"IntroMovie","opt-in boot pushes original intro before title")
game.save.options.jpSkipIntro=true;game:returnToTitle()
T.check(Stack:top().isTitleScreen and #Stack.states==1,"return to title clears old states and shows ROM title")
T.eq(Game.windowScaleInStack({states={{isBattle=true}}},game.save.options),0.75,"battle window multiplier stays intact")
T.eq(Game.windowScaleInStack({states={{isTitleScreen=true,menuOpen=true}}},game.save.options),0.75,"inactive title cannot override dialogue multiplier")
local optionsWrites, writeFailure = 0, nil
local persisted
game.writeOptions=function(self)
  optionsWrites=optionsWrites+1
  if writeFailure=="throw" then error("fixture options write failure") end
  if writeFailure then return nil end
  -- Use the real serializer/persistence path, not a synthetic saved marker.
  persisted=Save.saveOptions(self.save.options)
  return persisted
end
local function finishOpening()
  for _=1,2500 do if Stack:top().isTitleScreen then break end;Stack:update(1/60)end
  T.check(Stack:top().isTitleScreen,"opening sequence completes into ROM title")
end
-- The explicit OFF default plays the opening even with no seen marker.
game.save.options=Save.defaultOptions()
game.save.options.jpSkipIntro=false
game.save.options.jpDialogScale=0.75
game.save.options.musicVol=7
Stack:clear();game:pushBootTitle()
T.check(Stack:top().isOpeningMovie,"skip OFF and no marker plays original opening")
T.check(game.save.options.jpIntroSeenByVersion==nil,"starting the movie does not mark it watched")
game.save.options.jpIntroSeenByVersion={blue=true}
Stack:clear();game:pushBootTitle()
T.check(Stack:top().isOpeningMovie,"an interrupted first opening replays next launch")
finishOpening()
T.eq(optionsWrites,1,"completed first opening writes preferences once")
T.check(game.save.options.jpIntroSeenByVersion.red_jp,"completed opening marks this version only")
T.check(game.save.options.jpIntroSeenByVersion.blue,"other version completion flags survive")
local fromDisk=Save.loadOptions()
T.check(fromDisk.jpIntroSeenByVersion.red_jp,"opening marker survives real options serialization/reload")
T.eq(fromDisk.musicVol,7,"first-opening migration preserves existing audio preference")
T.eq(fromDisk.jpDialogScale,0.75,"first-opening migration preserves existing window preference")
game.save.options=fromDisk
Stack:clear();game:pushBootTitle()
T.check(Stack:top().isOpeningMovie,"skip OFF replays opening after persisted completion")
finishOpening();T.eq(optionsWrites,1,"replaying watched opening performs no extra preference write")
game.save.options.jpSkipIntro=true
Stack:clear();game:pushBootTitle()
T.check(Stack:top().isTitleScreen,"skip ON starts directly at title")
T.eq(optionsWrites,1,"explicit skip avoids extra preference write")
game.save.options.jpSkipIntro=false
for _,mode in ipairs({"nil","throw"})do
  game.save.options.jpIntroSeenByVersion=nil;writeFailure=mode
  Stack:clear();game:pushBootTitle();finishOpening()
  T.check(game.save.options.jpIntroSeenByVersion==nil,"failed marker write restores old options: "..mode)
  Stack:clear();game:pushBootTitle()
  T.check(Stack:top().isOpeningMovie,"failed marker persistence retries next launch: "..mode)
end
writeFailure=nil;game.save.options.jpIntroSeenByVersion=nil
Stack:clear();game:pushBootTitle()
for _=1,250 do
  if Stack:top().phase==2 and Stack:top().timer>=65 then break end
  Stack:update(1/60)
end
press(Stack:top(),"start");finishOpening()
T.check(game.save.options.jpIntroSeenByVersion.red_jp,"intentional START skip counts as completed first opening")
game.save.options.jpIntroSeenByVersion=nil;game.data.field.intro={skip=true}
Stack:clear();game:pushBootTitle();finishOpening()
T.check(game.save.options.jpIntroSeenByVersion==nil,"MOD-configured skip does not consume first original opening")
game.data.field.intro=nil
local standAlone=require("src.ui.PlayerStartMenu").new(game)
press(standAlone,"b");T.eq(calls.home,2,"standalone command menu still has a usable back destination")
Save.load=originalLoad;Screens.invalidate();Runtime.reset()
T.finish("Japanese title and safe start menu")
