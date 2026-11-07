-- ROM-free JP battle text: format/control-code invariants plus actual battle,
-- status, trainer item, ghost, evolution and menu display paths.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Japanese battle strings')
local Strings=require('src.core.Strings')
local Battle=require('src.battle.BattleState') -- require before loading a catalog
local Wide=require('src.battle.WideBattle')
local Status=require('src.battle.Status')
local Effects=require('src.battle.MoveEffects')
local Trainer=require('src.battle.TrainerAI')
local Evolution=require('src.pokemon.Evolution')
local TypeChart=require('src.battle.TypeChart')
local Font=require('src.render.Font')
local TextBox=require('src.render.TextBox')
local RomText=require('src.core.RomText')
local Pokemon=require('src.pokemon.Pokemon')
local data=require('tests.fixture_data').load()
data.constants.language='ja';data.text={}
for _,p in pairs(data.pokemon)do p.name='テスト' end
for _,m in pairs(data.moves)do m.name='テストわざ' end
local f=assert(io.open('tools/rom_manifest_red_jp.json','r'))
local manifest=assert(require('src.link.Json').decode(f:read('*a')));f:close()
data.font.charmap=manifest.fontCharmap;data.font.composites=manifest.fontComposites
Font.load(data);Strings.load(data)
local function specs(s)
  local list={}
  for v in s:gmatch('%%[-+ #0]*%d*%.?%d*([cdiouxXeEfgGqs%%])')do
    if v~='%' then list[#list+1]=v end
  end
  return table.concat(list,',')
end
local function controls(s)return (s:gsub('[^\v\f]',''))end
local function expanded(source,value)
  local args={}
  for v in source:gmatch('%%[-+ #0]*%d*%.?%d*([cdiouxXeEfgGqs%%])')do
    if v~='%' then args[#args+1]=v=='s' and 'ピカチュウ' or 12345 end
  end
  return string.format(value,unpack(args))
end
for source,value in pairs(require('src.core.JapaneseStringsBattle'))do
  local key=source:match('^[^|]+|(.+)$') or source
  T.eq(specs(value),specs(key),'format types/order retained: '..source)
  T.eq(controls(value),controls(key),'scroll/page controls retained: '..source)
  local rendered=expanded(key,value)
  rendered=rendered:gsub('%b{}','テスト')
  local widths=true
  for _,page in ipairs(TextBox.paginate(rendered,18))do
    for _,line in ipairs(page)do if Font.width(line)>144 then widths=false end end
  end
  T.check(widths,'real ROM-glyph pagination fits 18 columns: '..source)
  T.check(not rendered:find('[A-Za-z]'),'no English prose in translated output: '..source)
end
T.eq(RomText(data,'_ButItFailedText','But, it failed!'),'しかし うまく きまらなかった！','missing ROM label uses Japanese fallback')
data.text._ButItFailedText='ROMの ぶん{PROMPT}'
T.eq(RomText(data,'_ButItFailedText','But, it failed!'),data.text._ButItFailedText,'supplied ROM text remains authoritative')
data.text._ButItFailedText=nil
local function newGame()
  local mon=Pokemon.new(data,'FIXMON_A',10)
  local game={data=data,save={party={mon},options={},inventory={},player={name='レッド'},flags={},pokedex={seen={},owned={}}},
    input={wasPressed=function()return false end},stack={push=function()end,top=function()end}}
  return game,mon
end
local game,mon=newGame()
local battle=Battle.newWild(game,'FIXMON_C',5)
T.eq(battle.introText,'やせいの テストが\nとびだしてきた！','wild intro fallback is Japanese')
battle:makeGhost()
T.eq(battle.enemy.name,'ゆうれい','ghost HUD never displays hardcoded GHOST')
T.eq(battle.enemy.mon.species,'FIXMON_C','ghost display translation leaves species id unchanged')
T.eq(battle.introText,'ゆうれいが\nあらわれた！','ghost intro uses translated display name')
battle:makeOldManDemo('PROF.OAK')
T.eq(battle.demoName,'オーキド','built-in professor display name is localized')
T.eq(battle.oakDemo,true,'professor demo identity/picture selection stays unchanged')
battle:makeOldManDemo('MOD GUIDE')
T.eq(battle.demoName,'MOD GUIDE','custom MOD demo name is unchanged')
local rival={id='OPP_RIVAL1',name='ライバル',baseMoney=10,parties={{{species='FIXMON_C',level=5}}}}
data.trainers.OPP_RIVAL1=rival
local r=Battle.newTrainer(game,'OPP_RIVAL1',1)
T.eq(r.trainer.name,'グリーン','missing rival nickname uses Japanese fallback')
game.save.player.rival='MY RIVAL'
r=Battle.newTrainer(game,'OPP_RIVAL1',1)
T.eq(r.trainer.name,'MY RIVAL','user-provided rival name is never translated')
-- JP original text slots are trainer, enemy, item; English is trainer,item,enemy.
battle=Battle.newWild(game,'FIXMON_C',5);battle.trainer={name='トレーナー'}
data.items.POTION={name='キズぐすり'};battle.enemy.mon.hp=1
local before=battle.enemy.mon.hp
data.text._AIBattleUseItemText='{RAM:wTrainerName}は {RAM:wEnemyMonNick}に\n{RAM:wNameBuffer}を つかった！{DONE}'
local used=Trainer.useItem(battle,'POTION')
T.eq(used[1],'トレーナーは テストに\nキズぐすりを つかった！{DONE}','JP trainer item text keeps target and item in correct slots')
T.check(battle.enemy.mon.hp>before,'trainer item still performs its original healing')
data.text._AIBattleUseItemText='MODからの おしらせ'
T.eq(Trainer.useItem(battle,'POTION')[1],'MODからの おしらせ','custom literal trainer text remains authoritative')
data.text._AIBattleUseItemText=nil
T.eq(Trainer.useItem(battle,'POTION')[1],'トレーナーは\nキズぐすりを つかった！','missing trainer item template has Japanese fallback')
local status=Status.beforeMove({name='テスト',isPlayer=true,mon={status='SLP'},sleepTurns=2},function()return 1 end,battle)
local _,messages=Status.beforeMove({name='テスト',isPlayer=true,mon={status='SLP'},sleepTurns=2},function()return 1 end,battle)
T.check(messages[1]:find('ねむ',1,true)~=nil,'status runtime remains Japanese without ROM message')
local effect=Effects.changeStage(battle,battle.player,'attack',1,false)
T.check(effect[1]:find('こうげき',1,true)~=nil and not effect[1]:find('ATTACK',1,true),'stat change resolves Japanese stat label')
T.eq(Evolution.METHODS.TRADE.describe(),'つうしんこうかん','evolution detail no longer displays raw Trade')
T.eq(RomText(data,'_EvolvedText','%s evolved','テスト')..RomText(data,'_IntoText','\ninto %s!','テスト２'),
  'テストは しんかして\nテスト２に なった！','evolution fallback fragments join into one Japanese sentence')
-- Before registry setup, ROM typeNames still win over built-in fallbacks.
local chart={constants={language='ja'},type_chart={typeNames={FIRE='ROMほのお'}}}
T.eq(TypeChart.displayName('FIRE',chart),'ROMほのお','pre-registry display uses supplied ROM type name')
chart.type_chart.types={FIRE={name='MOD FLAME'}}
T.eq(TypeChart.displayName('FIRE',chart),'MOD FLAME','merged MOD type label remains authoritative')
chart.type_chart.types=nil;chart.type_chart.typeNames={}
T.eq(TypeChart.displayName('NORMAL',chart),'ノーマル','type fallback uses type context, not generic ふつう')
T.eq(TypeChart.displayName('PSYCHIC_TYPE',chart),'エスパー','type fallback hides PSYCHIC_TYPE identifier')
T.eq(TypeChart.displayName('MOD_TYPE',chart),'MOD_TYPE','unknown MOD type identifier remains untouched')
-- Real wide menu draws subject first and a complete second-line question.
battle.phase='menu';battle.menuIndex=1;game.save.options.battleLayout='wide'
local draw,code,box=Font.draw,Font.drawCode,Font.drawBox;local rows={}
Font.draw=function(text,x,y)rows[#rows+1]={text,x,y}end;Font.drawCode=function()end;Font.drawBox=function()end
Wide.draw(battle);Font.draw,Font.drawCode,Font.drawBox=draw,code,box
local first,second
for _,row in ipairs(rows)do if row[2]==8 and row[3]==112 then first=row[1] elseif row[2]==8 and row[3]==128 then second=row[1] end end
T.eq(first,'テストは','wide Japanese prompt names its subject first')
T.eq(second,'どうする？','wide Japanese prompt ends with a complete question')
-- Strings MOD overrides and overseas behavior retain priority.
Strings.load({constants={language='ja'},strings={['But, it failed!']='MOD RESULT',['battle|GHOST']='MOD GHOST'}})
T.eq(RomText({},'missing','But, it failed!'),'MOD RESULT','MOD translation overrides builtin fallback')
T.eq(Strings('GHOST','battle'),'MOD GHOST','MOD context translation overrides ghost display')
Strings.load({constants={language='en'}})
T.eq(Evolution.METHODS.TRADE.describe(),'Trade','English evolution description unchanged')
T.eq(Strings('GHOST','battle'),'GHOST','English ghost name unchanged')
T.eq(RomText({},'missing','Critical hit!'),'Critical hit!','English battle fallback unchanged')
T.finish()
