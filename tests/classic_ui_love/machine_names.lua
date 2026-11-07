-- Pixel-grid checks use the real Font with the independently drawn JP fixture.
return function(data,check,write)
  local Font=require('src.render.Font')
  local Names=require('src.inventory.ItemNames')
  local Strings=require('src.core.Strings')
  local g=love.graphics
  local d={font=data.font,constants={language='ja'},items={
    TM={name='TM50',machine={kind='TM',number=50,move='SUBSTITUTE'}},
    HM={name='HM05',machine={kind='HM',number=5,move='FLASH'}}},
    pokemon={FIX={name='ピカチュウ'}},moves={
      A={name='でんきショック'},B={name='かみなりパンチ'},C={name='どくどく'},D={name='なきごえ'}}}
  Strings.load(d)
  local c=g.newCanvas(160,144,{dpiscale=1});g.setCanvas(c);g.clear(1,1,1,1)
  local labels={Names.get(d,'TM'),Names.get(d,'HM')}
  for i,label in ipairs(labels)do
    check(Font.width(label)==(i==1 and 56 or 64),'TM/HM name uses seven/eight native tiles')
    local native=true
    for _,code in ipairs(Font.encode(label))do if code>=Font.TTF_BASE then native=false end end
    check(native,'TM/HM kana and dakuten need no fallback font')
    check(48+Font.width(label)<=152,'TM/HM name fits bag and shop interior')
  end
  local list=setmetatable({items={{label=labels[1],count=99},{label=labels[2]}},scroll=0,rows=4,index=1,
    arrowBlink=0,cursorBlank=0},{__index=require('src.ui.ListMenu')})
  list:drawItemBox()
  g.setCanvas();write('japanese-machine-bag.png',c:newImageData():encode('png'):getString())
  g.setCanvas(c);g.clear(1,1,1,1)
  local Learn=require('src.ui.MoveLearnMenu')
  local menu=Learn.new({data=d},{species='FIX',moves={{id='A'},{id='B'},{id='C'},{id='D'}}},'A')
  menu.selecting=true
  local original=Font.draw
  local positions={}
  Font.draw=function(text,x,y)
    if x==48 then positions[#positions+1]={text=text,x=x,y=y}end
    return original(text,x,y)
  end
  menu:draw();Font.draw=original
  local contained=#positions==4
  for i,p in ipairs(positions)do
    if p.y~=32+(i-1)*16 or p.x+Font.width(p.text)>152 or p.y-8<24 or p.y+8>88 then contained=false end
  end
  check(contained,'Japanese move selection keeps all names and upper dakuten in separate rows')
  g.setCanvas();write('japanese-machine-learn.png',c:newImageData():encode('png'):getString())
  d.constants.language='en';positions={};Font.draw=function(text,x,y)if x==48 then positions[#positions+1]=y end end
  menu:draw();Font.draw=original
  check(table.concat(positions,',')=='64,72,80,88','English move-selection row spacing is unchanged')
  Strings.load({})
end
