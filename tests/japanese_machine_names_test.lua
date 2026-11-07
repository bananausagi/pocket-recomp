-- Existing import caches keep stable item/move ids; only presentation changes.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local Names=require('src.inventory.ItemNames')
local Strings=require('src.core.Strings')
local function fixture(language)
  return {constants={language=language},field={},text={},
    items={TM_TOXIC={name='TM06',price=3000,machine={kind='TM',number=6,move='TOXIC'}},
      HM_CUT={name='HM01',price=0,machine={kind='HM',number=1,move='CUT'}}},
    moves={TOXIC={name='どくどく',pp=10},CUT={name='いあいぎり',pp=30},
      GROWL={name='なきごえ',pp=40},POUND={name='はたく',pp=35},TACKLE={name='たいあたり',pp=35}},
    pokemon={FIX={name='ピカチュウ',tmhm={'TOXIC','CUT'}}}}
end
local data=fixture('ja');Strings.load(data)
for _,kind in ipairs({'TM','HM'})do
  for n=1,(kind=='TM' and 50 or 5)do
    local d={constants=data.constants,items={TEST={name=('%s%02d'):format(kind,n),machine={kind=kind,number=n,move='CUSTOM'}}}}
    T.eq(Names.get(d,'TEST'),((kind=='TM' and 'わざマシン' or 'ひでんマシン')..'%02d'):format(n),'all standard machine numbers localize')
  end
end
T.eq(data.items.TM_TOXIC.name,'TM06','cached item definition remains unchanged')
T.eq(data.items.TM_TOXIC.machine.move,'TOXIC','machine move id remains unchanged')
local custom=fixture('ja');custom.items.TM_TOXIC.name='MOD special disc'
T.eq(Names.get(custom,'TM_TOXIC'),'MOD special disc','MOD display spelling remains authoritative')
custom.items.TM_TOXIC.name='わざマシン06'
T.eq(Names.get(custom,'TM_TOXIC'),'わざマシン06','already localized name is retained')
custom.items.TM_TOXIC.machine=nil;custom.items.TM_TOXIC.name='TM06'
T.eq(Names.get(custom,'TM_TOXIC'),'TM06','ordinary item with TM spelling is untouched')
T.eq(Names.get(data,'UNKNOWN'),'UNKNOWN','missing item retains stable fallback')
for _,language in ipairs({'en','fr','de'})do T.eq(Names.get(fixture(language),'TM_TOXIC'),'TM06','non-Japanese names unchanged')end
package.loaded['src.core.Sound']={play=function()end}
package.loaded['src.mods.Runtime']={wantsHook=function()return false end,call=function(_,fn,...)return fn(...)end}
package.loaded['src.world.PikachuFollower']={modifyHappiness=function()end}
local Text={PAUSE='\1',new=function(game,text,done,opts)return {text=text,onDone=done,opts=opts or {}}end,soundOpts=function(_,_,opts)return opts or {}end}
package.loaded['src.render.TextBox']=Text
package.loaded['src.ui.Screens']={push=function(game,id,opts)local screen={screenId=id,opts=opts};game.stack:push(screen);return screen end}
local function gameWith(d)
  local game={data=d,save={inventory={TM_TOXIC=2,HM_CUT=1},bagOrder={'TM_TOXIC','HM_CUT'},pcItems={TM_TOXIC=1},player={name='レッド'},money=9999,party={}},input={wasPressed=function()return false end}}
  game.stack={states={},push=function(self,s)self.states[#self.states+1]=s end,pop=function(self)return table.remove(self.states)end,top=function(self)return self.states[#self.states]end}
  return game
end
local game=gameWith(data)
local BagMenu=require('src.ui.BagMenu')
local bag=BagMenu.new(game)
T.eq(bag.items[1].label,'わざマシン06','bag displays localized TM from old cache')
T.eq(bag.items[2].label,'ひでんマシン01','bag displays localized HM')
T.eq(bag.items[1].value,'TM_TOXIC','bag retains serialized item id')
T.eq(bag.items[2].count,nil,'HM quantity suppression remains unchanged')
local function openMachine(index)
  bag.onChoose(bag.items[index]);game.stack:top().items[1].onSelect();return game.stack:top()
end
local intro=openMachine(1)
T.check(intro.text:find('わざマシンを',1,true)~=nil,'TM boot fallback is Japanese')
T.check(intro.text:find('どくどく',1,true)~=nil and not intro.text:find('TOXIC',1,true),'teach text uses imported move name')
intro.opts.choice(true)
local picker=game.stack:top()
T.eq(picker.opts.tmhm.move,'TOXIC','teach picker keeps the original move id')
local mon={nickname='ピカチュウ',species='FIX',moves={}}
picker.opts.onSwitch(mon)
T.eq(mon.moves[1].id,'TOXIC','TM still teaches internal TOXIC id')
T.eq(game.save.inventory.TM_TOXIC,1,'TM is consumed once after learning')
T.eq(game.stack:top().text,'ピカチュウは\nどくどくを おぼえた！','learning completion is Japanese')
intro=openMachine(2)
T.check(intro.text:find('ひでんマシンを',1,true)~=nil,'HM boot fallback is Japanese')
intro.opts.choice(true);game.stack:top().opts.onSwitch(mon)
T.eq(mon.moves[2].id,'CUT','HM still teaches internal CUT id')
T.eq(game.save.inventory.HM_CUT,1,'HM is retained after learning')
local Items=require('src.inventory.ItemEffects')
local result,messages=Items.use(data,game.save,'TM_TOXIC',mon)
T.eq(result,'failed','already-known move still refuses')
T.eq(messages[1],'その わざは\nすでに おぼえている！','already-known fallback is Japanese')
data.pokemon.FIX.tmhm={}
result,messages=Items.use(data,game.save,'TM_TOXIC',mon)
T.eq(result,'failed','incompatible species still refuses')
T.eq(messages[1],'ピカチュウは\nその わざを おぼえられない！','compatibility fallback is Japanese')
local shop=require('src.ui.ShopMenu').new(game,{'TM_TOXIC'})
shop.items[1].onSelect();local buy=game.stack:top()
T.eq(buy.items[1].label,'わざマシン06','shop buy list uses localized name')
buy.onChoose(buy.items[1]);game.stack:top().onDone(1)
T.check(buy.footer:find('わざマシン06',1,true)~=nil,'shop confirmation uses localized name')
shop.items[2].onSelect();T.eq(game.stack:top().items[1].label,'わざマシン06','shop sell list uses localized name')
local pc=require('src.ui.PlayerPC').new(game)
pc.items[1].onSelect();T.eq(game.stack:top().items[1].label,'わざマシン06','PC withdrawal list uses localized name')
pc.items[2].onSelect();T.eq(game.stack:top().items[2].label,'ひでんマシン01','PC deposit list uses localized HM name')
local Commands=require('src.script.Commands')
local sound=Commands.text_sound;Commands.text_sound=function()end
Commands.give_item({game=game,save=game.save},'TM_TOXIC',1,false)
Commands.text_sound=sound
T.eq(game.stringBuffer,'わざマシン06','script gift buffer contains localized display name')
T.eq(game.save.inventory.TM_TOXIC,2,'script gift inventory still uses original id')
local Learn=require('src.ui.MoveLearnMenu')
local learn=Learn.new(game,mon,'TOXIC',function()end)
learn:enter();T.check(not game.stack:top().text:find('trying',1,true),'full-moveset fallback is Japanese')
learn:confirmAbandon();T.eq(game.stack:top().text,'どくどくを おぼえるのを\nあきらめますか？','abandon confirmation is Japanese')
learn.forgot='なきごえ'
data.text._PoofText=' ポカン！\f{RAM:wLearnMoveMonName}は\n{RAM:wNameBuffer}を わすれた！\fそして……'
learn:finish(true);local learned=game.stack:top().text
T.check(not learned:find('{RAM:',1,true),'JP combined PoofText RAM slots are substituted')
local _,forgotCount=learned:gsub('わすれた！','')
T.eq(forgotCount,1,'combined JP forgetting sentence appears once')
T.check(learned:find('なきごえ',1,true)~=nil,'forgotten imported move name is preserved')
data.text={_BootedUpTMText='MOD boot',_TeachMachineMoveText='MOD {RAM:a} / {RAM:b}'}
intro=openMachine(1);T.eq(intro.text,'MOD boot\fMOD どくどく / どくどく','MOD teach text and placeholder order remain authoritative')
data.text={_PoofText='MOD poof',_ForgotAndText='MOD {RAM:a} / {RAM:b}'}
learn:finish(true);T.check(game.stack:top().text:find('MOD poof\1MOD ピカチュウ / なきごえ',1,true)~=nil,'MOD split forgetting text stays authoritative')
local en=fixture('en');Strings.load(en)
local enGame=gameWith(en);local enBag=BagMenu.new(enGame)
T.eq(enBag.items[1].label,'TM06','English bag is unchanged')
enBag.onChoose(enBag.items[1]);enGame.stack:top().items[1].onSelect()
T.eq(enGame.stack:top().text,'Booted up a TM!\fIt contained\nどくどく!\fTeach どくどく\nto a POKéMON?','English teach flow and imported custom move name are unchanged')
Strings.load({})
T.finish('Japanese machine presentation')
