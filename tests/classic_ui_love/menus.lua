-- Real native Font geometry for the JP menu labels and changing numeric fields.
return function(data,check,write)
  local Font=require('src.render.Font')
  local Strings=require('src.core.Strings')
  local Json=require('src.link.Json')
  local g=love.graphics
  local d={font=data.font,constants={language='ja',dexSize=1},text={},field={},
    pokemon={FIX={id='FIX',dex=1,name='ピカチュウ'}},
    moves={A={name='でんきショック'},B={name='かみなりパンチ'},C={name='どくどく'},D={name='なきごえ'}},items={}}
  local game={data=d,save={version='red_jp',player={name='レッド'},money=999999,coins=10,pokedex={seen={FIX=true},owned={FIX=true}},currentBox=8,party={},boxes={}},input={wasPressed=function()return false end}}
  for i=1,8 do game.save.boxes[i]={}end
  game.stack={states={},push=function(self,s)self.states[#self.states+1]=s end,pop=function(self)return table.remove(self.states)end,top=function(self)return self.states[#self.states]end}
  Strings.load(d)
  local charset={}
  for _,entry in ipairs(data.font.charmap)do charset[entry.seq]=true end
  for cp=32,126 do charset[string.char(cp)]=true end -- the licensed Latin 8x8 atlas
  local catalog=require('src.core.JapaneseStringsMenus')
  for key,value in pairs(catalog)do
    local rendered=value:gsub('%b{}','レッド'):gsub('%%[%-+ #0%d%.]*[cdiouxXeEfgGqs]','9')
    local native=true
    for glyph in rendered:gmatch('[%z\1-\127\194-\244][\128-\191]*')do
      if glyph~='\n' and glyph~='\v' and glyph~='\f' and not charset[glyph] then native=false end
    end
    check(native,'menu catalog uses native bitmap glyphs: '..key:gsub('\n',' / '))
  end
  local manifest=Json.decode(love.filesystem.read('tools/rom_manifest_red_jp.json'))
  local names={}
  for _,loc in pairs(manifest.field.townMap.locations)do names[loc.name]=true end
  for name in pairs(names)do
    local label=Strings(name)
    check(label~=name and Font.width(label)<=144,'town map metadata is translated within banner width: '..name)
  end
  local canvas=g.newCanvas(160,144,{dpiscale=1})
  local function capture(name,draw)
    g.setCanvas(canvas);g.clear(1,1,1,1)
    local texts,original={},Font.draw
    Font.draw=function(s,x,y)texts[#texts+1]={s=s,x=x,y=y,w=Font.width(s)};return original(s,x,y)end
    local ok,err=pcall(draw);Font.draw=original;assert(ok,err)
    g.setCanvas();write(name..'.png',canvas:newImageData():encode('png'):getString())
    return texts
  end
  local function find(texts,needle)for _,r in ipairs(texts)do if r.s==needle then return r end end end
  local shop=require('src.ui.ShopMenu').new(game,{})
  local texts=capture('jp10-shop-money',function()shop:draw()end)
  local money=find(texts,'999999えん')
  check(money and money.x>=88 and money.x+money.w<=152,'six-digit money and kana unit fit expanded shop frame')
  local qty=require('src.ui.QuantityBox').new(game,{max=99,start=99,unitPrice=9999})
  texts=capture('jp10-shop-quantity',function()qty:draw()end)
  local amount=find(texts,'989901えん');local count=find(texts,'×99')
  check(amount and count and count.x+count.w<=amount.x and amount.x+amount.w<=152,'maximum quantity price never overlaps count or frame')
  local pc=require('src.ui.BoxMenu').new(game)
  pc.items[4].onSelect();local ask=game.stack:top()
  -- Real TextBox stores the YES/NO callback in choice (not a synthetic opts).
  local choose=ask.choice or (ask.opts and ask.opts.choice)
  if not choose then
    for _,value in pairs(ask)do if type(value)=='table' and type(value.choice)=='function' then choose=value.choice;break end end
  end
  assert(choose,'box change confirmation exposes choice');choose(true)
  local list=game.stack:top()
  texts=capture('jp10-box-selection',function()list:draw()end)
  local rows={};for _,r in ipairs(texts)do if r.s:match('^ボックス%s*%d+$')then rows[#rows+1]=r end end
  local valid=#rows==5
  for i,r in ipairs(rows)do if r.y~=16+(i-1)*16 or r.x+r.w>144 then valid=false end end
  check(valid and list.index==8 and list.scroll==3,'box labels preserve dakuten spacing, all eight boxes remain reachable')
  local dex=require('src.ui.PokedexMenu').new(game)
  texts=capture('jp10-dex-counters',function()dex:draw()end)
  local seen,owned=find(texts,'みつけた'),find(texts,'つかまえた')
  check(seen and owned and seen.x>=120 and owned.x>=120 and seen.x+seen.w<=160 and owned.x+owned.w<=160,'dex counters fit sidebar without shortened font')
  local picker=require('src.ui.MoveSelectMenu').new(game,{moves={{id='A'},{id='B'},{id='C'},{id='D'}}},Strings('Restore PP of\nwhich technique?'))
  texts=capture('jp10-pp-selection',function()picker:draw()end)
  local i=0;valid=true
  for _,r in ipairs(texts)do if r.x==48 then i=i+1;if r.y~=32+(i-1)*16 or r.x+r.w>152 then valid=false end end end
  check(valid and i==4,'PP move selection uses four complete native glyph rows')
  local slot=require('src.ui.SlotMachine').new(game)
  texts=capture('jp10-slot-prompt',function()slot:drawBottom()end)
  local prompt=find(texts,'なんまい かけますか？')
  check(prompt and prompt.x+prompt.w<=112,'slot bet prompt fits before multiplier menu')
  Strings.load({})
end
