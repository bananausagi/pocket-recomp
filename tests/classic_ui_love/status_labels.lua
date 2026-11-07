-- Runs after the ROM-free Japanese bitmap fixture has loaded the real Font.
return function(data,check,write)
  local Font=require("src.render.Font")
  local Strings=require("src.core.Strings")
  local Status=require("src.battle.Status")
  local g=love.graphics
  Strings.load({constants={language="ja"}})
  local canvas=g.newCanvas(160,144,{dpiscale=1});g.setCanvas(canvas);g.clear(1,1,1,1);g.setColor(0,0,0,1)
  local original=Font.drawCode
  local marks,leafBounds=0,{}
  Font.drawCode=function(code,x,y)
    local composite=data.font.composites[tostring(code)] or data.font.composites[code]
    if not composite then
      leafBounds[#leafBounds+1]={x,y,x+8,y+8}
      if y%16==0 then marks=marks+1 end
    end
    return original(code,x,y)
  end
  for index,id in ipairs({"PSN","PAR","BRN","FRZ","SLP","FNT"})do
    local label=Status.hudLabelFor(nil,id)
    check(Font.width(label)<=24,id.." Japanese label fits original three-tile status column")
    local native=true
    for _,code in ipairs(Font.encode(label))do if code>=Font.TTF_BASE then native=false end end
    check(native,id.." label uses native ROM glyphs and voiced composites")
    -- Narrowest caller is PartyMenu's x=136; enemy HUD x=72 ends at96,
    -- player HUD x=120 ends at144, summary x=128 ends at152.
    Font.draw(label,136,index*16-8)
  end
  Font.drawCode=original
  local contained=true
  for _,b in ipairs(leafBounds)do
    if b[1]<136 or b[2]<0 or b[3]>160 or b[4]>104 then contained=false end
  end
  check(contained,"all Japanese status glyphs and dakuten stay inside party column")
  check(marks>0,"poison and burn preserve separate dakuten glyphs above baseline")
  g.setCanvas();write("japanese-status-labels.png",canvas:newImageData():encode("png"):getString())
  Strings.load({})
end
