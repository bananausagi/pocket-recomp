local TouchTargets=require("src.ui.JapaneseTouchTargets")
local Font=require("src.render.Font")
local Reminder=require("src.pokemon.JapaneseMoveReminder")
local TextBox=require("src.render.TextBox")
local Menu={isOpaque=true,centerInPlayfield=true}
Menu.__index=Menu

function Menu.new(game,mon)
  return setmetatable({game=game,mon=mon,index=1,scroll=0,phase="learn"},Menu)
end

function Menu:refresh()
  self.moves=Reminder.candidates(self.game,self.mon)
  self.index=math.max(1,math.min(self.index,#self.moves))
  self.scroll=math.max(0,math.min(self.scroll,math.max(0,#self.moves-5)))
end

function Menu:enter()self:refresh()end

function Menu:message(text)
  self.game.stack:push(TextBox.new(self.game,text))
end

function Menu:confirm(slot)
  local game,mon,id=self.game,self.mon,self.newMove
  local expected=Reminder.snapshot(mon,slot)
  local ok,reason=Reminder.validate(game,mon,id,slot,expected)
  if not ok then
    self:message(reason=="hm" and "ひでんわざは\nわすれられません！" or "いまは おもいだせません。")
    return
  end
  local move=game.data.moves[id]
  local text=move.name.."を\nおもいだしますか？"
  if expected.move then
    text=(game.data.moves[expected.id].name).."を わすれて\n"..move.name.."に しますか？"
  end
  game.stack:push(TextBox.new(game,text,nil,{defaultNo=true,choice=function(yes)
    if not yes then return end
    local applied,why=Reminder.apply(game,mon,id,slot,expected)
    if not applied then
      self:message(why=="hm" and "ひでんわざは\nわすれられません！" or "ようすが かわったので\nもういちど えらんでください。")
      self:refresh();return
    end
    self.phase,self.index,self.scroll="learn",1,0;self:refresh()
    require("src.core.Sound").play(game.data,"Get_Item1")
    self:message(move.name.."を\nおもいだした！")
  end}))
end

function Menu:update()
  if not Reminder.available(self.game,self.mon) then
    if self.game.stack:top()==self then self.game.stack:pop() end
    return
  end
  local input=self.game.input
  local replacing=self.phase=="replace"
  local count=replacing and #self.mon.moves or #self.moves
  if input:wasPressed("b") then
    if replacing then self.phase,self.index,self.scroll="learn",self.learnIndex or 1,0
    else self.game.stack:pop() end
    return
  end
  if count==0 then return end
  if input:wasPressed("up") then self.index=(self.index-2)%count+1
  elseif input:wasPressed("down") then self.index=self.index%count+1
  elseif input:wasPressed("a") then
    if replacing then self:confirm(self.index)
    else
      self.newMove=self.moves[self.index]
      if #self.mon.moves<4 then self:confirm(#self.mon.moves+1)
      else self.learnIndex=self.index;self.phase,self.index,self.scroll="replace",1,0 end
    end
  end
  if self.index<=self.scroll then self.scroll=self.index-1 end
  if self.index>self.scroll+5 then self.scroll=self.index-5 end
end

function Menu:draw()
  local count=self.phase=="replace" and #self.mon.moves or #self.moves
  TouchTargets.listCommands(self,count,5)
  local g=love.graphics
  g.setColor(1,1,1,1);Font.drawBox(0,0,20,18)
  g.setColor(0,0,0,1)
  local replacing=self.phase=="replace"
  Font.draw(replacing and "わすれる わざ" or "おもいだす わざ",8,16)
  local count=replacing and #self.mon.moves or #self.moves
  if count==0 then
    Font.draw("おもいだせる わざは",8,56)
    Font.draw("ありません。",8,72)
  end
  for row=1,5 do
    local at=self.scroll+row
    local id=replacing and self.mon.moves[at] and self.mon.moves[at].id or self.moves[at]
    if at<=count and id then
      TouchTargets.row(self,"reminder-"..at,16,20+row*16,136,16,at,replacing and self.mon.moves or self.moves)
      local name=self.game.data.moves[id].name
      local spans=Font.split(name);local fit=Font.spansFitting(spans,128)
      Font.draw(fit>0 and name:sub(1,spans[fit].to) or "",24,24+row*16)
      if at==self.index then Font.drawCode(0xED,8,24+row*16) end
    end
  end
  if count>0 then Font.draw(("%d/%d"):format(self.index,count),112,16) end
  Font.draw(TouchTargets.owns(self) and "わざを えらんでください" or "A けってい  B もどる",8,128)
  g.setColor(1,1,1,1)
end

return Menu
