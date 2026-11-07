-- Choices register beside their text. The renderer supplies the actual final
-- canvas placements; hit boxes never guess a window's scale or anchor.
local H={}
local function mode()return require('src.core.JapaneseTouchMode')end
local function context(o)
  return table.concat({tostring(o.index),tostring(o.subIndex),tostring(o.view),tostring(o.group),tostring(o.swapIndex),tostring(o.submenu),tostring(o.subItems),tostring(o.scroll),
    tostring(o.page),tostring(o.lower),tostring(o.selecting),tostring(o.pending),
    tostring(o.frozen),tostring(o.script),tostring(o.heal),tostring(o.swapAnim),
    tostring(o.items),tostring(o.party),tostring(o.mon and o.mon.moves),tostring(o.stage),tostring(o.phase),tostring(o.moves),tostring(o.capture),
    tostring(o.whiteHold and o.whiteHold>0),tostring(o.closing),
    tostring(o.picDelay and o.picDelay>0),tostring(o.swapFrom),tostring(o.softboiledFrom)},'|')
end
function H.begin(game,capturing)
  H.frame=nil
  if not capturing and mode().enabled(game) then
    local top=game.stack:top()
    H.frame={game=game,top=top,menu=top and top.menu,targets={},actions={}}
    game.jpTouchFrame=nil
  end
end
function H.owns(owner)
  local f=H.frame
  return f and (owner==f.top or (f.top and owner==f.top.menu))
end
function H.add(owner,id,x,y,w,h,apply,ref)
  if not H.owns(owner) then return end
  local f=H.frame
  local x1,y1=love.graphics.transformPoint(x,y)
  local x2,y2=love.graphics.transformPoint(x+w,y+h)
  f.targets[#f.targets+1]={owner=owner,id=id,ref=ref,context=context(owner),apply=apply,
    canvas=love.graphics.getCanvas(),x=x1,y=y1,w=x2-x1,h=y2-y1}
end
function H.row(owner,id,x,y,w,h,index,items,field)
  if owner.capture then return end
  if not H.owns(owner) then return end
  local ref=items[index];field=field or 'index'
  H.add(owner,id,x,y,w,h,function()
    if items[index]~=ref then return end
    if ref and type(ref)=='table' and ref.cancel and owner.swapIndex then owner.swapIndex=nil;return end
    owner[field]=index
    if field=='index' and owner.clampScroll then owner:clampScroll() end
    return 'a'
  end,ref)
end
function H.action(owner,id,label,key)
  if not H.owns(owner) then return end
  for _,a in ipairs(H.frame.actions)do if a.owner==owner and a.id==id then return end end
  H.frame.actions[#H.frame.actions+1]={owner=owner,id=id,label=label,key=key}
end
function H.back(owner,label)H.action(owner,'back',label or 'もどる','b')end
local function intersection(x,y,w,h,bx,by,bw,bh)
  local right,bottom=math.min(x+w,bx+bw),math.min(y+h,by+bh)
  x,y=math.max(x,bx),math.max(y,by)
  return x,y,math.max(0,right-x),math.max(0,bottom-y)
end
function H.finish(game,renderer)
  local f=H.frame;H.frame=nil
  if not f or f.game~=game then return end
  local m=renderer.jpTouchPlacement
  if not m then return end
  local v=require('src.render.GameViewport').rect or {x=0,y=0}
  for _,t in ipairs(f.targets)do
    local p
    -- A later anchor is also the later visible layer.
    for i=#m.anchors,1,-1 do
      local a=m.anchors[i];local r=a.a
      if t.canvas==(r.canvas or m.canvas) and t.x+t.w>r.x and t.y+t.h>r.y
          and t.x<r.x+r.w and t.y<r.y+r.h then p=a;break end
    end
    if p then
      local a=p.a
      t.x,t.y,t.w,t.h=intersection(p.dx+(t.x-a.x)*p.sx,p.dy+(t.y-a.y)*p.sy,
        t.w*p.sx,t.h*p.sy,p.dx,p.dy,p.dw,p.dh)
    elseif t.canvas==m.canvas then
      t.x,t.y,t.w,t.h=m.x+t.x*m.sx,m.y+t.y*m.sy,t.w*m.sx,t.h*m.sy
    else t.w,t.h=0,0 end
    t.x,t.y,t.w,t.h=intersection(t.x,t.y,t.w,t.h,m.clip.x,m.clip.y,m.clip.w,m.clip.h)
    t.x,t.y=t.x+v.x,t.y+v.y
  end
  local surface=mode().battleSurface(game,f.top)
  if surface then
    for _,a in ipairs(surface.commands or {})do
      f.targets[#f.targets+1]={owner=f.top,id='action-'..a.id,ref=a.key,context=context(f.top),
        x=v.x+surface.x+a.x*surface.sx,y=v.y+surface.y+a.y*surface.sy,
        w=a.w*surface.sx,h=a.h*surface.sy,apply=function()return a.key end}
    end
  end
  f.stamp=mode().stamp(game,0,0)
  game.jpTouchFrame=f
end
function H.frameFor(game)
  local f=game and game.jpTouchFrame
  if f and mode().valid(game,f.stamp) and f.menu==(f.top and f.top.menu) then return f end
end
function H.hit(game,x,y)
  local f=H.frameFor(game)
  if not f then return end
  for i=#f.targets,1,-1 do
    local t=f.targets[i]
    if t.context==context(t.owner) and x>=t.x and y>=t.y and x<t.x+t.w and y<t.y+t.h then return t end
  end
end
function H.current(game,target)
  local f=H.frameFor(game)
  if not f or target.context~=context(target.owner) then return end
  for _,t in ipairs(f.targets)do
    if t.owner==target.owner and t.id==target.id and t.ref==target.ref and t.context==target.context
        and t.x==target.x and t.y==target.y and t.w==target.w and t.h==target.h then return t end
  end
end
function H.queue(game,p)
  if p.target and H.current(game,p.target) then
    p.choiceQueue=game.input.pressQueue;game.jpPendingTouchChoice=p
  end
end
function H.step(game)
  local p=game.jpPendingTouchChoice;game.jpPendingTouchChoice=nil
  if not p or p.choiceQueue~=game.input.pressQueue or not mode().valid(game,p) then return end
  local t=H.current(game,p.target)
  if t then local key=t.apply();if key then mode().key(key)end end
end
-- Commands are part of the native page: content and hit boxes share its
-- renderer transform. No independent screen-edge controls are composited.
local pages={ListMenu=4,PartyMenu=1,PokedexMenu=3,DexEntryMenu=3,
  MoveSelectMenu=1,MoveLearnMenu=1,NamingScreen=3,QuantityBox=4,
  SummaryMenu=2,TrainerCard=1,TownMap=4,SlotMachine=1,
  JapaneseMoveReminderMenu=3,LeaguePC=2,EvolutionState=1,PicBox=1,Diploma=1,
  QuarantineReport=3,PaletteScreen=3}
function H.page(owner)
  local class=owner and getmetatable(owner)
  while type(class)=='table' do
    for name in pairs(pages)do if class==package.loaded['src.ui.'..name] then return pages[name] end end
    local parent=getmetatable(class)
    class=parent and parent.__index
  end
end
function H.menu(owner)
  return owner and getmetatable(owner)==package.loaded['src.ui.Menu']
end
function H.uiSize(game,top,w,h)
  if not mode().enabled(game) or not top or top.floatingPanel then return w,h end
  local owner=H.menu(top.menu) and top.menu or top
  if H.menu(owner) and owner.cancelable then
    h=math.max(h,(owner.ty+owner.th+(owner.maxVisible and #owner.items>owner.maxVisible and 4 or 2))*8)
  elseif H.page(owner) then
    h=math.max(h,144+(owner.isPartyMenu and owner:topInset() or 0)+(owner.touchCancelVisible and owner:touchCancelVisible() and 0 or (H.page(owner)>2 and 40 or 24)))
  end
  return w,h
end
function H.choice(owner,id,label,key,x,y,w,h)
  local Font=require('src.render.Font')
  local f=H.frame
  for _,p in pairs(f and f.game.jpTapPointers or {})do
    if p.target and p.target.owner==owner and p.target.id=='action-'..id and not p.dragged then
      love.graphics.setColor(.83,.85,.83,1);love.graphics.rectangle('fill',x,y,w,h)
    end
  end
  love.graphics.setColor(0,0,0,1)
  Font.draw(label,x+8,y+math.floor((h-8)/2))
  H.add(owner,'action-'..id,x,y,w,h,function()
    if type(key)=='function' then return key() end
    return key
  end,id)
end
function H.drawCommands(owner)
  local f=H.frame
  if not f or not H.owns(owner) or not H.page(owner) then return end
  local actions={}
  for _,a in ipairs(f.actions)do if a.owner==owner then actions[#actions+1]=a end end
  if #actions==0 then return end
  local Font=require('src.render.Font')
  local y=144+(owner.isPartyMenu and owner:topInset() or 0)
  Font.drawBox(0,y/8,20,H.page(owner)>2 and 5 or 3)
  for i=1,math.min(4,#actions) do
    local a=actions[i]
    H.choice(owner,a.id,a.label,a.key,4+((i-1)%2)*76,y+4+math.floor((i-1)/2)*16,76,16)
  end
  love.graphics.setColor(1,1,1,1)
end
function H.listCommands(owner,count,visible)
  if owner.capture and owner.endCapture then
    H.action(owner,'back','もどる',function()owner:endCapture()end);return
  end
  H.back(owner)
  if count>visible then
    H.action(owner,'previous','まえへ',function()
      owner.index=math.max(1,owner.index-visible)
      owner.scroll=math.max(0,owner.index-1)
    end)
    H.action(owner,'next','つぎへ',function()
      owner.index=math.min(count,owner.index+visible)
      owner.scroll=math.max(0,math.min(count-visible,owner.index-1))
    end)
  end
  if owner.touchActions then H.action(owner,'tools','そうさ',function()owner:touchActions()end)
  elseif owner.onSelectKey then H.action(owner,'arrange',(type(owner.touchSelectLabel)=='function' and owner:touchSelectLabel() or owner.touchSelectLabel) or 'いれかえ','select')end
end
return H
