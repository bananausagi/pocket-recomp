-- Player-facing Gen1 menus must localize without changing saves or MOD text.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local Strings=require('src.core.Strings')
local catalog=require('src.core.JapaneseStringsMenus')
local function formats(s)local out={} for spec in s:gmatch('%%[%-+ #0%d%.]*[cdiouxXeEfgGqs%%]')do out[#out+1]=spec end return table.concat(out,'|')end
local function slots(s)local out={}for token in s:gmatch('%b{}')do out[#out+1]=token end table.sort(out)return table.concat(out,'|')end
for source,value in pairs(catalog)do
 T.eq(formats(value),formats(source),'format directives retained for '..source)
 T.eq(slots(value),slots(source),'named substitutions retained for '..source)
end
local data={constants={language='ja'},text={},field={flyOrder={'PALLET_TOWN','VIRIDIAN_CITY'},townMap={locations={PALLET_TOWN={name='マサラの ひろば'}}}},
 maps={PALLET_TOWN={index=0},VIRIDIAN_CITY={index=1}},items={POTION={name='キズぐすり'},ETHER={name='ピーピーエイド'},REVIVE={name='げんきのかけら'},PP_UP={name='ポイントアップ'}},
 moves={GROWL={name='なきごえ',pp=40}},pokemon={FIX={name='ピカチュウ'}}}
Strings.load(data)
T.eq(Strings('MONEY/¥%d',999999),'おかね/999999えん','trainer money uses native kana currency')
T.eq(Strings('Saved to\n%s.','/Pictures/印刷.png'),'/Pictures/印刷.pngに\nほぞんしました。','file paths remain literal in Japanese notification')
package.loaded['src.core.Sound']={play=function()end,playCry=function()end}
package.loaded['src.mods.Runtime']={wantsHook=function()return false end,call=function(_,fn,...)return fn(...)end}
package.loaded['src.world.PikachuFollower']={modifyHappiness=function()end}
local realText=require('src.render.TextBox')
local Text={PAUSE='\1',strip=realText.strip,substitute=realText.substitute,
 new=function(game,text,done,opts)return{text=text,onDone=done,opts=opts or {}}end,
 soundOpts=function(_,_,opts)return opts or {}end}
package.loaded['src.render.TextBox']=Text
local game={data=data,save={version='red_jp',player={name='レッド'},money=999999,coins=10,inventory={},bagOrder={},pcItems={},visited={PALLET_TOWN=true,VIRIDIAN_CITY=true},party={}},input={wasPressed=function()return false end}}
game.stack={states={},push=function(self,s)self.states[#self.states+1]=s end,pop=function(self)return table.remove(self.states)end,top=function(self)return self.states[#self.states]end}
local fly=require('src.ui.FlyMenu').new(game)
T.eq(fly.items[1].label,'マサラの ひろば','Fly uses supplied ROM/MOD location before id fallback')
T.eq(fly.items[2].label,'トキワシティ','old map metadata fallback is Japanese')
T.eq(fly.items[2].value,'VIRIDIAN_CITY','flight destination id is unchanged')
local TownMap=require('src.ui.TownMap')
local map=setmetatable({fly=false},TownMap)
T.eq(map:bannerText({name='SEA ROUTE 20'}),'20ばんすいどう','sea route metadata is Japanese')
T.eq(map:bannerText({name='MY CUSTOM LAND'}),'MY CUSTOM LAND','MOD location name is preserved')
local pc=require('src.ui.PlayerPC').new(game)
pc.items[1].onSelect();T.eq(game.stack:top().text,'なにも\nあずかっていません。','empty PC withdrawal fallback is Japanese')
pc.items[2].onSelect();T.eq(game.stack:top().text,'あずける どうぐを\nもっていません。','empty PC deposit fallback is Japanese')
data.text._NothingStoredText='CUSTOM STORED';pc.items[1].onSelect();T.eq(game.stack:top().text,'CUSTOM STORED','PC imported/MOD dialogue remains authoritative');data.text._NothingStoredText=nil
local ItemEffects=require('src.inventory.ItemEffects')
local mon={nickname='ピカチュウ',species='FIX',hp=5,stats={hp=30},moves={{id='GROWL',pp=0}}}
game.save.party={mon}
local result,msg=ItemEffects.use(data,game.save,'POTION',mon)
T.eq(result,'consumed','Potion behavior is unchanged');T.eq(mon.hp,25,'Potion amount is unchanged')
T.eq(msg[1],'ピカチュウの\nたいりょくが かいふくした！','healing fallback is Japanese')
result,msg=ItemEffects.use(data,game.save,'ETHER',mon,nil,1)
T.eq(mon.moves[1].pp,10,'Ether restores original PP amount');T.eq(msg[1],'PPが\nかいふくした！','PP restoration fallback is Japanese')
mon.hp=0;result,msg=ItemEffects.use(data,game.save,'REVIVE',mon)
T.eq(mon.hp,15,'Revive still restores half HP');T.eq(msg[1],'ピカチュウは\nげんきを とりもどした！','Revive fallback is Japanese')
result,msg=ItemEffects.use(data,game.save,'PP_UP',mon,nil,1)
T.eq(msg[1],'なきごえの\nPPが ふえた！','PP Up uses imported move name in Japanese fallback')
local drawn={};local Font=require('src.render.Font');local draw=Font.draw
Font.draw=function(s,x,y)drawn[#drawn+1]={s=s,x=x,y=y}end
local Slots=require('src.ui.SlotMachine');local slot=Slots.new(game)
local function linesFor(stage)
 drawn={};Font.draw=function(s,x,y)drawn[#drawn+1]={s=s,x=x,y=y}end
 slot.stage=stage;slot:drawBottom();Font.draw=draw
 return drawn[1].s..'\n'..drawn[2].s
end
T.eq(linesFor('bet'),'コインを\nなんまい かけますか？','slot bet prompt is Japanese')
T.eq(linesFor('onemore'),'もういちど\nあそびますか？','slot retry prompt is Japanese')
slot:resolveLose();T.eq(slot.message,'ざんねん！','slot loss is Japanese')
T.eq(slot.stage,'message','slot loss flow remains unchanged')
data.text._NotThisTimeText='MOD LOSE';slot:resolveLose();T.eq(slot.message,'MOD LOSE','slot MOD dialogue is preserved')
slot:resolveWin({symbol='CHERRY',payout=8});T.check(slot.message:find('チェリーが そろった！',1,true)~=nil,'slot result translates symbolic id')
T.eq(slot.win.symbol,'CHERRY','slot symbol id is unchanged');T.eq(slot.payoutRemaining,8,'slot payout remains unchanged')
Font.draw=draw
local Trade=require('src.ui.TradeAnim')
local function tradeText(phase,sub,t)
 local trade=setmetatable({game=game,phase=phase,sub=sub,t=t or 0,sent={species='FIX'},received={species='FIX'},enemyName='100% MOD',skipHeld=function()return false end},Trade)
 trade:update();return trade.dialogText
end
T.eq(tradeText('went_to'),'ピカチュウは\n100% MODの もとへ！','trade fallback uses names without format interpolation')
data.text._TradeWentToText='MOD {RAM:wStringBuffer} → {RAM:wLinkEnemyTrainerName}'
T.eq(tradeText('went_to'),'MOD ピカチュウ → 100% MOD','trade custom dialogue and percent names remain literal')
data.text._TradeWentToText=nil
T.check(not tradeText('for_sends'):find('_Trade',1,true),'trade for phase never exposes internal label')
T.check(not tradeText('for_sends','for_text',80):find('_Trade',1,true),'trade sends phase never exposes internal label')
T.check(not tradeText('farewell'):find('_Trade',1,true),'trade farewell phase never exposes internal label')
T.check(not tradeText('farewell','farewell_text',80):find('_Trade',1,true),'trade transfer phase never exposes internal label')
local Boxes=require('src.pokemon.Boxes');Boxes.ensure(game.save);game.save.currentBox=8
local boxMenu=require('src.ui.BoxMenu').new(game)
boxMenu.items[4].onSelect();game.stack:top().opts.choice(true)
local choose=game.stack:top()
T.eq(choose.index,8,'last Japanese storage box remains selected')
T.eq(choose.scroll,3,'last box is visible in Japanese scroll window')
T.eq(choose.rowStep,2,'voiced box names reserve their own upper glyph row')
T.eq(#choose.items,8,'all Japanese boxes remain accessible')
choose.items[7].onSelect();T.eq(game.save.currentBox,7,'choosing box still selects stable numeric index')
Strings.load({constants={language='en'}});data.constants.language='en'
T.eq(Strings('¥%d',999999),'¥999999','non-Japanese currency is unchanged')
T.eq(linesFor('bet'),'Bet how many\ncoins?','English slot prompt is unchanged')
T.eq(tradeText('went_to'),'_TradeWentToText','non-Japanese missing trade fallback is unchanged')
local enFly=require('src.ui.FlyMenu').new(game);T.eq(enFly.items[1].label,'PALLET TOWN','non-Japanese Fly display is unchanged')
Strings.load({constants={language='ja'},strings={['Coin count:\n%d']='CUSTOM %d'}})
T.eq(Strings('Coin count:\n%d',42),'CUSTOM 42','MOD catalog overrides added Japanese catalog')
Strings.load({})
T.finish('Japanese menu and inventory presentation')
