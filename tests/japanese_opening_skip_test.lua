package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('JP25 explicit opening skip')
local Save=require('src.core.SaveData')
local Transfer=require('src.import.SettingsTransfer')
local Json=require('src.link.Json')
local Game=require('src.core.Game')
local Stack=require('src.core.StateStack')
local Screens=require('src.ui.Screens')
local Version=require('src.core.GameVersion')
Version.set('red_jp')
local data=require('tests.fixture_data').load();data.constants.language='ja'
require('src.render.Font').load(data);require('src.core.Strings').load(data)
local function document(options)return Json.encode({format=Transfer.FORMAT,version=1,options=options})end
T.eq(Save.defaultOptions().jpSkipIntro,false,'fresh default plays the opening')
for _,legacy in ipairs({true,false})do
 local raw={jpOriginalIntro=legacy,musicVol=6,jpIntroSeenByVersion={red_jp=true}}
 local migrated=Save.mergeOptions(raw)
 T.eq(migrated.jpSkipIntro,not legacy,'old explicit preference inverts to skip '..tostring(legacy))
 T.eq(migrated.jpOriginalIntro,nil,'save migration has one canonical toggle')
 T.eq(raw.jpOriginalIntro,legacy,'migration leaves input record intact')
 T.eq(migrated.musicVol,6,'migration preserves audio')
 T.check(migrated.jpIntroSeenByVersion.red_jp,'migration preserves completion history')
 for _,skip in ipairs({true,false})do
  raw.jpSkipIntro=skip;migrated=Save.mergeOptions(raw)
  T.eq(migrated.jpSkipIntro,skip,'new explicit '..tostring(skip)..' overrides legacy '..tostring(legacy))
 end
 raw.jpSkipIntro=nil
 local imported=assert(Transfer.import(document({jpOriginalIntro=legacy}),{jpSkipIntro=legacy,zoom=9}))
 T.eq(imported.jpSkipIntro,not legacy,'legacy JSON overrides current skip value')
 T.eq(imported.zoom,9,'legacy import preserves unrelated live setting')
 local exported=assert(Transfer.export(raw));local parsed=assert(Json.decode(exported))
 T.eq(parsed.options.jpSkipIntro,not legacy,'legacy export emits canonical skip value')
 T.eq(parsed.options.jpOriginalIntro,nil,'export omits old duplicate toggle')
end
T.eq(Save.mergeOptions({}).jpSkipIntro,false,'missing preference defaults to play')
T.eq(Save.mergeOptions({jpSkipIntro='yes'}).jpSkipIntro,false,'invalid saved skip value safely defaults to play')
for _,skip in ipairs({true,false})do
 local options={jpSkipIntro=skip,jpOriginalIntro=skip,musicVol=4}
 local candidate=assert(Transfer.import(document(options),{}))
 T.eq(candidate.jpSkipIntro,skip,'JSON conflict obeys new explicit skip value')
 local again=assert(Transfer.import(assert(Transfer.export(options)),{}))
 T.eq(again.jpSkipIntro,skip,'canonical JSON round-trip retains '..tostring(skip))
 T.eq(again.musicVol,4,'canonical JSON retains other preferences')
 local persisted=Save.defaultOptions();persisted.jpSkipIntro=skip
 T.check(Save.saveOptions(persisted)~=nil,'actual options file saves '..tostring(skip))
 T.eq(Save.loadOptions().jpSkipIntro,skip,'actual options file reloads '..tostring(skip))
end
for _,key in ipairs({'jpSkipIntro','jpOriginalIntro'})do
 T.eq(Transfer.import(document({[key]='true'}),{}),nil,key..' JSON rejects non-boolean')
end

-- Isolate only the splash factory, while exercising the real boot routing.
-- The existing player_start_menu_test drives the real movie and manual skip.
local original=Screens.push
local launches=0
Screens.push=function(game,id,done)
 launches=launches+1;game.stack:push({screenId=id,isOpeningMovie=true,finish=done})
end
for _,seen in ipairs({true,false})do for _,skip in ipairs({true,false})do
 local writes=0
 local game=setmetatable({data={constants={language='ja'},field={}},
  save={options={jpSkipIntro=skip,jpIntroSeenByVersion=seen and {red_jp=true}or nil},
    player={map='FIX_START',x=4,y=5}},
  stack=setmetatable({states={}},{__index=Stack})},{__index=Game})
 game.makeTitleState=function()return{isTitleScreen=true}end
 game.writeOptions=function()writes=writes+1;return true end
 local progress=Json.encode(game.save.player)
 local before=launches;local title=game:pushBootTitle()
 T.eq(game.stack:top()==title,skip,'skip '..tostring(skip)..' applies with seen '..tostring(seen))
 T.eq(launches-before,skip and 0 or 1,'boot route starts expected number of movies')
 T.eq(writes,0,'starting/skipping movie never writes options')
 T.eq(Json.encode(game.save.player),progress,'boot route preserves progress')
 if not seen then T.eq(game.save.options.jpIntroSeenByVersion,nil,'explicit skip does not invent completion history')end
 if not skip then
  local pending=game.stack:pop();pending.finish()
  T.eq(game.stack:top(),title,'movie completion reaches same title')
  T.eq(writes,seen and 0 or 1,'only new completion writes watched marker')
 end
end end
for _,version in ipairs({'red','blue','yellow'})do
 Version.set(version)
 local game=setmetatable({data={field={}},save={options={jpSkipIntro=true}},
  stack=setmetatable({states={}},{__index=Stack}),makeTitleState=function()return{}end},{__index=Game})
 local before=launches;game:pushBootTitle()
 T.eq(launches,before+1,'JP setting does not alter '..version..' boot')
end
Version.set('red_jp');Screens.push=original

-- Both actual settings models expose one identical row, and update the same
-- boolean; the removed launcher-only original-intro control cannot disagree.
do
 local options=Save.defaultOptions();local game={data=data,save={options=options}}
 local home=require('src.import.LauncherSettings').open({options=options,save=function()return true end},'red_jp')
 local menu=require('src.ui.OptionsMenu').new(game)
 local function flatten(sections,out)
  out=out or{};for _,section in ipairs(sections or{})do
   for _,row in ipairs(section.rows or{})do out[#out+1]=row end;flatten(section.children,out)
  end;return out
 end
 local function find(rows,id)
  local found,count=nil,0;for _,r in ipairs(rows)do if r.id==id then found=r;count=count+1 end end
  return found,count
 end
 local hr,hn=find(flatten(home.sections),'jpSkipIntro');local gr,gn=find(menu.rows,'jpSkipIntro')
 T.eq(hn,1,'launcher has exactly one skip toggle');T.eq(gn,1,'game has exactly one skip toggle')
 local _,oldHome=find(flatten(home.sections),'jpOriginalIntro');local _,oldGame=find(menu.rows,'jpOriginalIntro')
 T.eq(oldHome,0,'launcher has no duplicate original-intro toggle');T.eq(oldGame,0,'game has no duplicate original-intro toggle')
 T.eq(gr.label,'オープニングを スキップ','game row explains explicit skip action')
 T.eq(hr.value(),'オフ','launcher default shown Off');T.eq(gr.value(game),'オフ','game default shown Off')
 hr.step(1);T.eq(options.jpSkipIntro,true,'launcher ON sets same boolean');T.eq(gr.value(game),'オン','game reflects launcher toggle')
 gr.step(game,1);T.eq(options.jpSkipIntro,false,'game OFF updates same boolean');T.eq(hr.value(),'オフ','launcher reflects game toggle')
 options.jpSkipIntro=true
 require('src.core.JapaneseRules').applyPreset(options,'classic')
 T.eq(options.jpSkipIntro,true,'battle convenience preset never changes opening preference')
end
T.finish()
