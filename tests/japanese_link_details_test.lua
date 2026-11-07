-- ROM-free presentation-boundary tests. Wire/session errors remain English IDs;
-- only their player-visible rendering and compatibility notices are localized.
package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local T = require('tests.harness').suite('Japanese link details')
local Strings = require('src.core.Strings')
local Display = require('src.link.DisplayText')
local Handshake = require('src.link.Handshake')
local Json = require('src.link.Json')
local Protocol = require('src.link.Protocol')
local Session = require('src.link.Session')
local LinkState = require('src.link.LinkState')
local LinkBattle = require('src.link.LinkBattle')
local LinkItems = require('src.link.LinkItems')
local ItemEffects = require('src.inventory.ItemEffects')
local Link = require('tests.modkit.link')
local Font = require('src.render.Font')
local TextBox = require('src.render.TextBox')
local data = require('tests.fixture_data').load()

Strings.load(nil)
T.eq(Display.reason('send failed: timeout'), 'send failed: timeout', 'English diagnostic unchanged')
T.eq(Display.reason('unknown POKéMON'), 'unknown POKéMON', 'English raw reason unchanged')
T.eq(table.concat(Display.wrap('ABCDEFGHIJKLMNOPQRSTUV', 19)), 'ABCDEFGHIJKLMNOPQRSTUV', 'hard wrap never drops twentieth character')
T.eq(Display.clip('がぎぐげご', 3), 'がぎぐ', 'headless UTF-8 clipping is safe')
local english = Handshake.describe({generation=1}, {generation=2}, 'refused', 'battle')
T.eq(table.concat(english, '|'), "The other game is|from a different|generation.|These two games|can't link.", 'English compatibility notice unchanged')
T.eq(Display.species({data=data}, 'FIXMON_A'), 'FIXMON_A', 'English diagnostic species ID unchanged')

data.constants.language = 'ja'; data.text = {}
data.pokemon.FIXMON_A.name = 'フシギダネ'
data.pokemon.FIXMON_B.name = 'ヒトカゲ'
local f = assert(io.open('tools/rom_manifest_red_jp.json', 'r'))
local manifest = assert(Json.decode(f:read('*a'))); f:close()
data.font.charmap = manifest.fontCharmap; data.font.composites = manifest.fontComposites
data.font.language = 'ja'
Font.load(data); Strings.load(data)

local function signature(s)
  local out = {}
  for spec in s:gmatch('%%[-+ #0]*%d*%.?%d*([cdiouxXeEfgGqs%%])') do
    if spec ~= '%' then out[#out + 1] = spec end
  end
  return table.concat(out, ',')
end
for key, value in pairs(require('src.core.JapaneseStringsLinkDetails')) do
  local source = key:match('^[^|]+|(.+)$') or key
  T.eq(signature(value), signature(source), 'format types and order: '..key)
  local args = {}; for s in signature(source):gmatch('[^,]+') do args[#args+1] = s == 's' and 'あいて' or 123 end
  local expanded = string.format(value, unpack(args))
  local fits = true
  for _, page in ipairs(TextBox.paginate(expanded, 18)) do
    for _, line in ipairs(page) do if Font.width(line) > 144 then fits=false end end
  end
  T.check(fits, 'ROM glyph pagination fits: '..key)
end

T.eq(Display.reason('unknown POKéMON'), 'しらない ポケモン', 'known reason translated')
T.eq(Display.reason('vendor diagnostic: UNKNOWN_ERR_27'), 'vendor diagnostic: UNKNOWN_ERR_27', 'unknown transport details preserved verbatim')
T.eq(Display.reason('send failed: timeout'), 'おくれませんでした: じかんぎれ', 'send failure nested OS reason')
T.eq(Display.reason("can't open UDP port 8765 (connection refused)"), 'UDPポート 8765を\nひらけません (せつぞくを ことわられました)', 'UDP port and nested reason preserved')
T.eq(Display.reason('bad address 1.2.3.4:8765'), 'アドレスが ちがいます\n1.2.3.4:8765', 'address value unchanged')
T.eq(Display.reason(Strings("can't reach relay %s:%d\n(%s)",'relay.example',8765,'timeout')),
  Strings("can't reach relay %s:%d\n(%s)",'relay.example',8765,'じかんぎれ'), 'already-formatted Net error translates nested reason at UI boundary')
T.eq(Display.reason(Strings("Couldn't join:\n%s", 'CUSTOM_27')), Strings("Couldn't join:\n%s", 'CUSTOM_27'), 'arbitrary relay reason retained')
T.eq(Display.reason(Strings('no answer from\n%s','the host')), Strings('no answer from\n%s','あいて'), 'default host label translated')
T.eq(Display.component('actives'), 'せんとうの じょうたい', 'desync component display')
T.eq(Display.component('CUSTOM'), 'CUSTOM', 'MOD component preserved')
T.eq(Display.species({data=data}, 'FIXMON_A'), 'フシギダネ', 'known Japanese species label')
T.eq(Display.species({data=data}, 'MOD_MON'), 'MOD_MON', 'unknown species ID retained')
data.pokemon.FIXMON_A.name = 'MODの なまえ'
T.eq(Display.species({data=data}, 'FIXMON_A'), 'MODの なまえ', 'merged MOD species label authoritative')
data.pokemon.FIXMON_A.name = 'フシギダネ'
T.eq(table.concat(Display.wrap('がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽ', 19)), 'がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽ', 'voiced kana survives hard wrap')
T.eq(Font.width(Display.clip('がぎぐげご',3)),24,'composed kana clipping counts drawn glyphs')

local base = {generation=1,protocol=Handshake.PROTOCOL,engineVersion='0.2.0',ruleset='gen1_faithful',mods={}}
local function copy(t) local r={} for k,v in pairs(t)do r[k]=v end return r end
local cases = {
  {'refused','battle',{generation=2}},
  {'refused','trade',{generation=1}},
  {'refused','battle',{generation=1,protocol=999}},
  {'ruleset_skew','battle',{ruleset='CUSTOM',name='ながいなまえのあいて'}},
  {'ruleset_skew','trade',{ruleset='CUSTOM'}},
  {'engine_skew','battle',{engineVersion='0.999.12345678901234567890',name='あいて'}},
  {'engine_skew','trade',{engineVersion='0.999.0'}},
  {'subset','battle',{mods={ {id='test',version='v1'}, {id='next',version='v2'}, {id='more',version='v3'}, {id='last',version='v4'} }}},
  {'subset','trade',{mods={}}},
}
for _, c in ipairs(cases) do
  local peer = copy(base); for k,v in pairs(c[3])do peer[k]=v end
  if c[1]=='refused' and c[3].protocol==nil then peer.protocol=nil end
  local before = Json.encode(peer)
  local lines = Handshake.describe(base,peer,c[1],c[2])
  T.check(#lines>0,'notice has content: '..c[1]..'/'..c[2])
  T.eq(Json.encode(peer),before,'notice never alters peer hello: '..c[1]..'/'..c[2])
  for _,line in ipairs(lines)do T.check(Font.width(line)<=152,'notice line fits 19 ROM glyphs: '..line) end
end
local lines = Handshake.describe(base, {generation=1,protocol=2,mods={}}, 'subset','trade')
T.check(table.concat(lines):find('こうかん できます',1,true)~=nil,'subset notice includes Japanese allowed action')

local input = require('src.core.Input'); input:init()
local function newGame() return Link.fakeGame(data, {'FIXMON_A','FIXMON_B'}, {name='レッド'}) end
local function transport(detail)
  return { paired=true, error=detail, update=function()end,poll=function()return{}end,
    send=function(self,msg)self.sent=msg;return true end,close=function(self)self.closed=true end }
end
local game = newGame()
local raw = transport('send failed: timeout')
local session = Session.new(raw,{role='host',kind='link'})
local state = LinkState.new(game);state.net=session;state.stage='hosting'
game.stack:push(state);state:update(1/60)
T.eq(raw.error,'send failed: timeout','transport diagnostic not translated in state')
T.eq(session.error,'send failed: timeout','session diagnostic not translated in state')
local reason,detail=session:getFailure()
T.eq(reason,'transport_error','machine failure reason preserved')
T.eq(detail,'send failed: timeout','machine failure detail preserved')
local textbox = game.stack:top()
T.check(textbox and textbox.isTextBox,'terminal failure creates actual TextBox')
local shown = table.concat(textbox.pages[1],'\n')
T.check(shown:find('おくれませんでした',1,true)~=nil,'actual LinkState error is Japanese')

game=newGame();state=LinkState.new(game);state.net=Session.new(transport(),{role='host',kind='link'})
state.stage='trade';state.trade={stage='cancelled',error='no shared moves'}
game.stack:push(state);state:updateTrade(input)
T.eq(state.trade.error,'no shared moves','trade raw reason preserved')
local all={};for _,p in ipairs(game.stack:top().pages)do all[#all+1]=table.concat(p)end
T.check(table.concat(all):find('つかえる わざが ありません',1,true)~=nil,'actual cancelled trade detail localized')

game=newGame();state=LinkState.new(game);state.net=Session.new(transport(),{role='host',kind='link'})
state.stage='notice';state.verdict='subset';state.noticeLines={};state.noticeExits=true
for i=1,13 do state.noticeLines[i]='つうしん '..i end
state.noticePage=1;game.stack:push(state)
local originalDraw=Font.draw; local drawn={}
Font.draw=function(text,x,y)drawn[#drawn+1]={text=text,x=x,y=y};return Font.width(text)end
local visited={}
for page=1,3 do
  drawn={};state:draw()
  for _,r in ipairs(drawn)do
    local n=r.text:match('^つうしん (%d+)$')
    if n then visited[tonumber(n)]=true;T.check(r.y>=24 and r.y<=88 and (r.y-24)%16==0,'notice rows reserve voiced marks')end
  end
  input.pressed={right=true};state:update(1/60)
end
T.eq(state.noticePage,3,'page navigation clamps at last page')
for i=1,13 do T.check(visited[i],'notice page exposes line '..i)end
input.pressed={left=true};state:update(1/60);T.eq(state.noticePage,2,'left navigates previous page')
input.pressed={b=true};state:update(1/60);T.eq(state.net._transport.sent.type,'bye','B still sends machine bye')
T.eq(game.stack:top(),nil,'B still exits notice')
Font.draw=originalDraw;input.pressed={}

game=newGame();local packed=Protocol.packParty(game.save.party)
local invalid=Protocol.packMon(game.save.party[2]);invalid.moves={ {id='MISSING'} }
local mon,why=Protocol.unpackMon(data,invalid,{strict=true})
T.eq(mon,nil,'strict invalid move rejected')
T.eq(why,'no shared moves','Protocol rejection remains raw English ID')
local battle,err=LinkBattle.newHost(game,transport(),{myParty=packed,theirParty={invalid},strict=true,verdict='full',theirName='あいて'})
T.eq(battle,nil,'actual LinkBattle rejects unshared moves')
T.check(err:find('ヒトカゲ',1,true)~=nil and err:find('つかえる わざが ありません',1,true)~=nil,'battle rejection displays species and reason in Japanese')

data.items.X_ATTACK={id='X_ATTACK',name='プラスパワー'}
data.items.POTION={id='POTION',name='キズぐすり'}
local battler={mon=game.save.party[1],name='フシギダネ',stages={attack=0}}
local enemy={mon=game.save.party[2],name='ヒトカゲ',stages={}}
local runtime={data=data,game=game,kind='link'}
local side={battler=battler,party=game.save.party,opponent=enemy,opponentParty={enemy.mon},name='あいて'}
local effects,result=LinkItems.apply(runtime,{item='X_ATTACK'},side)
T.eq(result,'consumed','Japanese peer item still consumed')
T.eq(battler.stages.attack,1,'Japanese peer item still raises attack exactly once')
T.eq(#effects,2,'Japanese use-line and effect printed once each')
T.check(effects[1]~=effects[2],'Japanese use-line is not duplicated')
data.text._ItemUseText001='MOD {PLAYER} {RAM:wNameBuffer}'
effects=LinkItems.apply(runtime,{item='X_ATTACK'},side)
T.eq(effects[1],'MOD あいて プラスパワー','ROM/MOD use-line preserved')
T.eq(#effects,2,'ROM/MOD use-line not duplicated')
data.text._ItemUseText001=nil
battler.mon.hp=1
effects,result=LinkItems.apply(runtime,{item='POTION',index=1},side)
T.eq(result,'consumed','medicine still consumed')
T.check(battler.mon.hp>1,'medicine still heals')
T.eq(#effects,2,'medicine gets use-line plus effect')

data.strings={ ['link.reason|timeout']='MODの エラー', ["Couldn't join:\n%s"]='%s' }
Strings.load(data)
T.eq(Display.reason('timeout'),'MODの エラー','MOD reason override remains authoritative')
T.eq(Display.reason('unknown custom detail'),'unknown custom detail','identity format MOD cannot cause recursive translation')
Strings.load(nil)
T.eq(Display.reason('timeout'),'timeout','catalog unload restores English')
T.finish()
