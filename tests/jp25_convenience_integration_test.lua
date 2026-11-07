package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('JP25 convenience integration')
local Save=require('src.core.SaveData')
local Transfer=require('src.import.SettingsTransfer')
local Json=require('src.link.Json')
local Rules=require('src.core.JapaneseRules')
local Runtime=require('src.mods.Runtime')
Runtime.install(require('src.mods.Events').new(),require('src.mods.Hooks').new())
local data=require('tests.fixture_data').load(); data.constants.language='ja'
require('src.core.Strings').load(data)
require('src.core.GameVersion').set('red_jp')
local Home=require('src.import.LauncherSettings')
local Options=require('src.ui.OptionsMenu')
local function rows(sections,out)
  out=out or {}
  for _,s in ipairs(sections or {}) do
    for _,r in ipairs(s.rows or {}) do out[#out+1]=r end
    rows(s.children,out)
  end
  return out
end
local function find(list,id)
  local result,n
  for _,r in ipairs(list)do if r.id==id then result=r;n=(n or 0)+1 end end
  return result,n
end
local options=Save.defaultOptions()
local game={data=data,save={options=options}}
local home=Home.open({options=options,save=function()return true end},'red_jp')
local ingame=Options.new(game)
for _,id in ipairs({'jpFollower','jpRepelRepeat'}) do
  T.eq(options[id],true,id..' enabled for fresh options')
  T.eq(Save.mergeOptions({[id]=false})[id],false,id..' explicit Off survives loading')
  local hr,hn=find(rows(home.sections),id);local gr,gn=find(ingame.rows,id)
  T.eq(hn,1,id..' appears once in home settings');T.eq(gn,1,id..' appears once in game settings')
  T.eq(hr.value(),'オン',id..' default visible in home')
  hr.step(1);T.eq(options[id],false,id..' home disables');T.eq(gr.value(game),'オフ',id..' game reflects it')
  gr.step(game,1);T.eq(options[id],true,id..' game enables')
  for _,v in ipairs({false,true}) do
    options[id]=v
    Rules.applyPreset(options,'classic');T.eq(options[id],v,id..' independent of classic battle preset')
    Rules.applyPreset(options,'convenient');T.eq(options[id],v,id..' independent of convenient battle preset')
    local decoded=assert(Transfer.import(assert(Transfer.export(options)),{}))
    T.eq(decoded[id],v,id..' JSON settings round trip')
  end
  local invalid=Json.encode({format=Transfer.FORMAT,version=1,options={[id]='true'}})
  T.eq(Transfer.import(invalid,{}),nil,id..' invalid import rejected')
end
-- Save progress is serializable independently of options and object identity.
local progress={jpHabitatVisited={ROUTE_1=true},jpRepelItem='SUPER_REPEL',jpRepelExpired=true,
  repelSteps=0,jpFollowerIdentity=2,jpFollowerNextIdentity=2,
  party={{species='FIXMON_A',jpFollowerIdentity=2}}}
T.same(Save.decode(Save.encode(progress)),progress,'habitat, spray and companion identity survive save encoding')

-- The new list uses the same START/Back branch as existing game menus.
local Stack=require('src.core.StateStack')
local Start=require('src.ui.StartMenu')
local ow={isOverworld=true,player={}}
game={data=data,save={options=options,flags={},party={},player={name='テスト'}},overworld=ow,
  stack=setmetatable({states={ow}},{__index=Stack}),input={wasPressed=function()return false end}}
game.quickSaveAllowed=function()return true end
local menu=Start.new(game);game.stack:push(menu)
local entry,n=find(menu.items,'jp-habitats')
T.eq(n,1,'one habitat entry in native START menu')
T.eq(entry.keepOpen,true,'habitat returns to same START menu')
entry.onSelect()
local panel=game.stack:top()
T.check(panel~=menu and panel.floatingPanel and panel.systemMenuPause,'habitat is a floating paused branch')
game.input.wasPressed=function(_,key)return key=='b' end
panel:update(1/60)
T.eq(game.stack:top(),menu,'B from habitat returns to original START menu')
game.stack:pop()
local notice={};game.openSessionMenu=function()return notice end
menu=Start.new(game,{restricted=true});game.stack:push(menu)
entry=find(menu.items,'jp-habitats');entry.onSelect()
T.eq(game.stack:top(),menu,'restricted event cannot enter habitat screen')
T.check(type(notice.notice)=='string','restricted event explains unavailable action')
T.finish()
