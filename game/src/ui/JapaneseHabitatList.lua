local Habitats = require("src.world.JapaneseHabitats")
local Layout = require("src.ui.GameUILayout")
local Classic = require("src.ui.ClassicUI")
local Repeat = require("src.ui.MenuRepeat")
local Menu = {floatingPanel=true, systemMenuPause=true, isOpaque=false, screenId="JapaneseHabitatList"}
Menu.__index = Menu
local METHODS = {{"all","すべて"},{"land","りく"},{"water","みず"},{"fish","つり"}}

function Menu.new(game)
  local self=setmetatable({game=game,index=1,scroll=0,method=1,areaMode=false,
    hold=Repeat.new()},Menu)
  self.areas,self.areaIndex=Habitats.areas(game)
  self:refresh()
  return self
end

function Menu:refresh()
  local area=self.areas[self.areaIndex]
  self.entries,self.counts=Habitats.entries(self.game,area and area.maps or {},METHODS[self.method][1])
  self.index,self.scroll=1,0
end

function Menu:layout()
  local m=Layout.panelMetrics(self.game,{minHeight=160})
  local width=m.width
  local summary=("みた%d/%d  つかまえた%d/%d"):format(self.counts.seen,self.counts.total,
    self.counts.owned,self.counts.total)
  local splitCounts=not self.areaMode and Classic.width(summary)>width-32
  local body=splitCounts and 80 or 64
  local footer,rowHeight=56,16
  local rows=math.max(1,math.floor((m.height-body-footer)/rowHeight))
  local items=self.areaMode and self.areas or self.entries
  local height=math.ceil((body+math.max(3,math.min(rows,#items))*rowHeight+footer)/8)*8
  height=math.min(m.height,height)
  rows=math.max(1,math.floor((height-body-footer)/rowHeight))
  local index=self.areaMode and self.areaIndex or self.index
  self.scroll=math.max(0,math.min(self.scroll,math.max(0,#items-rows)))
  if index<=self.scroll then self.scroll=index-1 end
  if index>self.scroll+rows then self.scroll=index-rows end
  local view=Layout.overlay(self.game,{width=width,height=height,scale=m.scale,
    margin=m.margin,rect=m.rect,anchor="center"})
  local l={width=width,height=height,body=body,rows=rows,rowHeight=rowHeight,footer=height-footer,
    summary=summary,splitCounts=splitCounts,
    view=view,items=items,index=index,first=self.scroll+1,last=math.min(#items,self.scroll+rows)}
  self.geometry=l
  return l
end

function Menu:commands(l)
  local function page(delta)
    local n=#l.items
    if n==0 then return end
    local index=math.max(1,math.min(n,l.index+delta*l.rows))
    if self.areaMode then self.areaIndex=index else self.index=index end
  end
  return {
    {id='back',label='もどる',run=function()
      if self.areaMode then self.areaMode=false;self:refresh() else self:close()end
    end},
    {id='areas',label=self.areaMode and 'このエリア' or 'エリアをえらぶ',run=function()
      self.areaMode=not self.areaMode;self.scroll=0;if not self.areaMode then self:refresh()end
    end},
    {id='previous',label='まえのページ',run=function()page(-1)end},
    {id='next',label='つぎのページ',run=function()page(1)end},
    {id='filter',label=self.areaMode and 'えらぶ' or ('しぼる '..METHODS[self.method][2]),run=function()
      if self.areaMode then self.areaMode=false else self.method=self.method%#METHODS+1 end
      self:refresh()
    end},
    {id='area-next',label='つぎのエリア',run=function()
      if #self.areas>0 then self.areaIndex=self.areaIndex%#self.areas+1;self:refresh()end
    end},
  }
end
function Menu:hit(x,y)
  local l=self:layout()
  local lx,ly,inside=Classic.hit(l.view,x,y)
  if not inside then return end
  if ly>=l.body-4 and ly<l.body+(l.last-l.first+1)*l.rowHeight-4 then
    local at=l.first+math.floor((ly-l.body+4)/l.rowHeight)
    if l.items[at] then return 'row-'..at,function()
      if self.areaMode then self.areaIndex=at;self.areaMode=false;self:refresh()
      else self.index=at end
    end end
  end
  local col=lx<l.width/2 and 0 or 1
  local row=math.floor((ly-l.footer)/16)
  if lx>=8 and lx<l.width-8 and row>=0 and row<3 then
    local a=self:commands(l)[row*2+col+1]
    return a.id,a.run
  end
end
function Menu:onWindowPointer(phase,id,x,y)
  if phase=='cancelled' then self.pointer=nil;return end
  if phase=='pressed' then
    if self.pointer then return end
    local hit=self:hit(x,y)
    if hit then
      local l=self:layout()
      self.pointer={id=id,hit=hit,x=x,y=y,view=l.view,method=self.method,
        areaMode=self.areaMode,areaIndex=self.areaIndex,index=self.index,scroll=self.scroll,
        revision=self.game.stack.pointerRevision}
    end
    return
  end
  local p=self.pointer;if not p or p.id~=id then return end
  if math.abs(x-p.x)>12 or math.abs(y-p.y)>12 then p.dragged=true end
  if phase~='released' then return end
  self.pointer=nil
  local l=self:layout();local hit,run=self:hit(x,y)
  if p.dragged or p.hit~=hit or p.method~=self.method or p.areaMode~=self.areaMode
      or p.areaIndex~=self.areaIndex or p.index~=self.index or p.scroll~=self.scroll
      or p.revision~=self.game.stack.pointerRevision then return end
  for _,k in ipairs({'x','y','sx','sy','width','height'})do if p.view[k]~=l.view[k] then return end end
  if run then run()end
end
function Menu:onWindowWheel(dy)
  local l=self:layout();local n=#l.items;if n==0 then return end
  local at=math.max(1,math.min(n,l.index+(dy>0 and -1 or 1)*l.rows))
  if self.areaMode then self.areaIndex=at else self.index=at end
end

function Menu:close()
  if self.game.stack:top()==self then self.game.stack:pop() end
end

function Menu:update()
  if not Habitats.enabled(self.game) then self:close();return end
  local input=self.game.input
  local l=self:layout()
  if input:wasPressed("b") then
    if self.areaMode then self.areaMode=false;self:refresh() else self:close() end
    return
  elseif input:wasPressed("select") then
    self.areaMode=not self.areaMode;self.scroll=0
    if not self.areaMode then self:refresh() end
    return
  elseif input:wasPressed("a") then
    if self.areaMode then self.areaMode=false
    else self.method=self.method%#METHODS+1 end
    self:refresh();return
  end
  local dir=Repeat.direction(self.hold,input)
  if dir=="left" or dir=="right" then
    if #self.areas>0 then self.areaIndex=(self.areaIndex-1+(dir=="left" and -1 or 1))%#self.areas+1 end
    self:refresh()
  elseif dir=="up" or dir=="down" then
    local count=#l.items
    if count>0 then
      local nextIndex=(l.index-1+(dir=="up" and -1 or 1))%count+1
      if self.areaMode then self.areaIndex=nextIndex else self.index=nextIndex end
    end
  end
end

-- The native pass remains transparent. Game.draw calls the floating pass
-- after world composition, just like the existing settings/MOD panels.
function Menu:draw() end

function Menu:drawWindowOverlay()
  local l=self:layout()
  local area=self.areas[self.areaIndex]
  Classic.backdrop(l.view)
  Classic.begin(self.game,{layout=l.view})
  Classic.box(0,0,l.width/8,l.height/8)
  local function text(s,x,y,w) Classic.text(s,x,y,{width=w or l.width-x-16}) end
  local position=("%d/%d"):format(#l.items>0 and l.index or 0,#l.items)
  local positionWidth=Classic.width(position)
  text("せいそくちリスト",16,16,l.width-positionWidth-48)
  text(position,l.width-positionWidth-16,16,positionWidth)
  text(self.areaMode and "いった エリアを えらぶ" or (area and area.name or "きろくが ありません"),16,32)
  if self.areaMode then
    text("いった ばしょだけ ひょうじ",16,48)
  elseif not l.splitCounts then
    text(l.summary,16,48)
  else
    text(("みた %d/%d"):format(self.counts.seen,self.counts.total),16,48)
    text(("つかまえた %d/%d"):format(self.counts.owned,self.counts.total),16,64)
  end
  for at=l.first,l.last do
    local row=l.items[at]
    local y=l.body+(at-l.first)*l.rowHeight
    if at==l.index then Classic.cursor(8,y) end
    if self.areaMode then
      text(row.name,24,y,l.width-40)
    else
      local label=row.owned and "つかまえた" or row.seen and "みた" or "まだ"
      local statusWidth=48
      text(row.name,24,y,l.width-48-statusWidth)
      text(label,l.width-statusWidth-8,y,statusWidth)
    end
  end
  if #l.items==0 then text("ここには きろくが ありません",16,l.body+12) end
  local footer=l.footer
  love.graphics.setColor(0,0,0,1)
  love.graphics.rectangle("fill",16,footer-4,l.width-32,1)
  for i,a in ipairs(self:commands(l))do
    local x=8+((i-1)%2)*(l.width-16)/2
    local y=footer+math.floor((i-1)/2)*16
    if self.pointer and self.pointer.hit==a.id and not self.pointer.dragged then Classic.cursor(x,y+4)end
    text(a.label,x+8,y+4,(l.width-16)/2-12)
  end
  Classic.finish()
end

return Menu
