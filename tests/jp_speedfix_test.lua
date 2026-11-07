-- jp.74.1 speed fix regression: the game must not stay fast without the
-- player knowing.  (1) skin fast_forward_hold re-entrancy restores the
-- original speed; (2) the one-time options migration puts persisted
-- multipliers (globals and cart buckets) back to 1X without mutating the
-- decoded snapshot, and a speed chosen afterwards persists; (3) the speed
-- hotkey shows an on-screen notice.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('JP74.1 speed fix')
local Game=require('src.core.Game')
local Input=require('src.core.Input')
local Touch=require('src.core.TouchControls')
local SaveData=require('src.core.SaveData')
local SaveSerializer=require('src.core.SaveSerializer')
local Data=require('tests.fixture_data').load()
Data.constants.language='ja'
Game.data=Data;Game.input=Input;Input:init();Touch:init()
local Notice=require('src.ui.JapaneseSpeedNotice')

-- (1) fast_forward_hold: press, press, release must not leave 4X stuck.
Game.speedOverride=nil;Game.skinSpeedSaved=nil
Game:touchSkinHotkey('fast_forward_hold',true)
T.eq(Game.speedOverride,Game.SKIN_FAST_FORWARD,'hold press sets skin fast-forward')
Game:touchSkinHotkey('fast_forward_hold',true)
Game:touchSkinHotkey('fast_forward_hold',false)
T.eq(Game.speedOverride,nil,'press-press-release restores no override (was stuck at 4X)')
Game.speedOverride=2
Game:touchSkinHotkey('fast_forward_hold',true)
Game:touchSkinHotkey('fast_forward_hold',true)
Game:touchSkinHotkey('fast_forward_hold',false)
T.eq(Game.speedOverride,2,'press-press-release restores an existing override')
Game:touchSkinHotkey('fast_forward_hold',false)
T.eq(Game.speedOverride,2,'stray release without a press changes nothing')
Game.speedOverride=nil
Game:touchSkinHotkey('fast_forward_hold',true)
Game:touchcancelled('t1')
T.eq(Game.speedOverride,nil,'touch cancel during a hold ends the fast-forward')
T.eq(Game.skinSpeedSaved,nil,'touch cancel clears the saved speed')

-- (2) one-time migration, pure.
local loaded={speedOverworld=10,speedBattle=2,speedMenu=1,textSpeed='fast',
  cartOptions={red_jp={speedOverworld=4,textSpeed='slow'},green_jp={speedBattle=0/0}}}
local before=SaveSerializer.encode(loaded)
local out=SaveData.migrateSpeedFix(loaded)
T.eq(SaveSerializer.encode(loaded),before,'migration does not mutate the decoded snapshot')
T.eq(out.speedOverworld,1,'global field speed 10X reset to 1X')
T.eq(out.speedBattle,1,'global battle speed 2X reset to 1X')
T.eq(out.speedMenu,1,'1X untouched')
T.eq(out.textSpeed,'fast','unrelated option kept')
T.eq(out.cartOptions.red_jp.speedOverworld,1,'cart bucket field speed reset to 1X')
T.eq(out.cartOptions.red_jp.textSpeed,'slow','cart bucket other keys kept')
T.eq(out.cartOptions.green_jp.speedBattle,1,'NaN cart speed repaired')
T.eq(out[SaveData.SPEED_FIX_FLAG],true,'flag set')
out.speedOverworld=2;out.speedBattle=-3
local again=SaveData.migrateSpeedFix(out)
T.eq(again.speedOverworld,2,'speed chosen after the fix persists')
T.eq(again.speedBattle,1,'invalid speed still repaired after the fix')

-- (2b) through the real options file round trip.
local files={}
local fs={write=function(name,s)files[name]=s;return true end,
  read=function(name)return files[name]end,
  getInfo=function(name)return files[name] and {type='file',size=#files[name]} or nil end,
  remove=function(name)files[name]=nil;return true end}
files['options.lua']=SaveSerializer.encode({speedOverworld=10,speedBattle=10,speedMenu=10})
SaveData.invalidateOptions(fs)
local opts=SaveData.loadOptions(fs)
T.eq(opts.speedOverworld,1,'old options.lua with 10X loads as 1X')
T.eq(opts[SaveData.SPEED_FIX_FLAG],true,'loaded view carries the flag')
opts.speedOverworld=4
T.check(SaveData.saveOptions(opts,fs)~=nil,'options save succeeds')
local reread=SaveData.loadOptions(fs)
T.eq(reread.speedOverworld,4,'4X chosen after the fix survives a reload')
-- a partial write before any full write must not resurrect the old cart 10X
files['options.lua']=SaveSerializer.encode({speedOverworld=10,cartOptions={red_jp={speedOverworld=10}}})
SaveData.invalidateOptions(fs)
SaveData.saveOptions({textSpeed='fast'},fs)
local okDecode=SaveData.loadOptions(fs)
T.eq(okDecode.speedOverworld,1,'partial write does not keep the pre-fix global 10X')
T.eq(okDecode.cartOptions.red_jp.speedOverworld,1,'partial write does not keep the pre-fix cart 10X')

-- logicSpeed reads the fixed options as 1X.
Game.speedOverride=nil;Game.linkSession=nil;Game.linkNet=nil
Game.stack={states={},top=function()return nil end}
Game.save={options=SaveData.migrateSpeedFix({speedOverworld=10,speedBattle=10,speedMenu=10})}
T.eq(Game:logicSpeed(),1,'logic speed is 1X after the migration')

-- (3) the speed hotkey is no longer silent.
Game.overworld=nil
Game.writeOptions=function()end
Game._jpSpeedNotice=nil
Game:_cycleSpeed(1)
T.check(Game._jpSpeedNotice~=nil,'speed hotkey shows a notice')
T.eq(Game._jpSpeedNotice and Game._jpSpeedNotice.text,'はやさ 2X','notice names the new speed')
T.eq(Game:logicSpeed(),2,'hotkey changed the speed to 2X')
Game._jpSpeedNotice.presented=true
for _=1,20 do Notice.update(Game,0.10) end
T.eq(Game._jpSpeedNotice,nil,'notice ages out after it was shown')
T.eq(Notice.label(10),'10X','badge label')

-- (4) jp.75.1: Gold's speed hotkey (Game2:_cycleSpeed) shows the same toast.
local Game2=require('src.core.Game2')
local persisted=0
local g2={options={speed=1},data={constants={language='ja'}},
  persistOptions=function() persisted=persisted+1 end}
Game2._cycleSpeed(g2,1)
T.eq(persisted,1,'gold speed hotkey still persists the option')
T.eq(g2._jpSpeedNotice and g2._jpSpeedNotice.text,'はやさ 2X','gold speed hotkey shows a notice')
T.eq(Notice.badgeSpeed(g2),nil,'gold gets no overworld badge (toast only)')
g2._jpSpeedNotice.presented=true
for _=1,20 do Notice.update(g2,0.10) end
T.eq(g2._jpSpeedNotice,nil,'gold notice ages out')
T.check(type(Game2.update)=='function' and type(Game2.draw)=='function','gold update/draw present')
T.finish()
