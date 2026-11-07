-- Full-window editor hosted by the existing paused touch-editor route.
-- Markers are visible only here. The preview maps the whole safe game screen,
-- so its toolbar never prevents placement at an edge or beneath a toolbar.
local E={}
local A=require('src.core.JapaneseTouchAreas')
local Save=require('src.core.SaveData')
local Safe=require('src.core.SafeArea')
local UiFont=require('src.render.UiFont')
local Pad=require('src.ui.PadCursor')
local function inside(r,x,y)return r and x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h end
local function color(r,g,b,a)love.graphics.setColor(r,g,b,a or 1)end
local function copy(v)if type(v)~='table'then return v end local o={}for k,x in pairs(v)do o[k]=copy(x)end return o end
function E.load(options)
  options=options or {}
  E.onClose=options.onClose;E.version=options.version;E.closed=false
  local _,_,w,h=Safe.windowRect()
  E.orientation=A.orientation(w,h);E.selected='back';E.drag=nil;E.pointer=nil
  E.data=A.normalize(Save.loadOptions().jpTouchAreas);E.message=nil
  E.font=UiFont.attach(love.graphics.newFont(16),16)
  E.title=UiFont.attach(love.graphics.newFont(21),21)
  E.sizeKey=nil;Pad.reset()
end
function E.unload()
  E.drag=nil;E.pointer=nil;E.onClose=nil;E.closed=true;Pad.reset()
end
local function bounds(orientation,w,h)
  if A.orientation(w,h)~=orientation then w,h=h,w end
  return {x=0,y=0,w=w,h=h}
end
function E.layout()
  local x,y,w,h=Safe.windowRect()
  local key=table.concat({x,y,w,h,E.orientation},',')
  if E.sizeKey and E.sizeKey~=key then E.drag=nil;E.pointer=nil end
  E.sizeKey=key
  local pad=math.max(8,math.min(16,w*.025));local gap=6
  local row=math.max(30,math.min(44,h*.06))
  local hits={};local left=x+pad;local width=w-2*pad
  local function button(id,label,bx,by,bw)hits[#hits+1]={id=id,label=label,x=bx,y=by,w=bw,h=row}end
  local yy=y+30
  local half=(width-gap)/2
  button('portrait','たてがめん',left,yy,half);button('landscape','よこがめん',left+half+gap,yy,half)
  yy=yy+row+gap
  button('back','もどる',left,yy,half);button('menu','メニュー',left+half+gap,yy,half)
  yy=yy+row+gap
  local quarter=(width-3*gap)/4
  button('smaller','−',left,yy,quarter);button('larger','＋',left+quarter+gap,yy,quarter)
  button('toggle',E.data[E.orientation][E.selected].enabled and 'オン' or 'オフ',left+2*(quarter+gap),yy,quarter)
  button('reset','もとに',left+3*(quarter+gap),yy,quarter)
  local footer=y+h-pad-row
  button('cancel','やめる',left,footer,half);button('save','ほぞん',left+half+gap,footer,half)
  local top=yy+row+38;local available=math.max(20,footer-top-46)
  local logical=bounds(E.orientation,w,h)
  local scale=math.min(width/logical.w,available/logical.h)
  local preview={x=x+(w-logical.w*scale)/2,y=top+(available-logical.h*scale)/2,
    w=logical.w*scale,h=logical.h*scale,scale=scale,logical=logical}
  return {x=x,y=y,w=w,h=h,hits=hits,preview=preview,footer=footer,row=row}
end
function E.close(save)
  if E.closed then return end
  if save then
    local _,_,w,h=Safe.windowRect()
    for _,orientation in ipairs({'portrait','landscape'})do
      if A.overlap(E.data,orientation,bounds(orientation,w,h))then
        E.message=(orientation=='portrait' and 'たて' or 'よこ')..'がめんの エリアが かさなっています'
        return false
      end
    end
    local options=Save.loadOptions();options.jpTouchAreas=copy(E.data)
    local ok,result=pcall(Save.saveOptions,options)
    if not ok or not result then E.message='ほぞんできませんでした。もういちど おしてね';return false end
  end
  local cb=E.onClose;E.unload();if cb then cb()end
  return true
end
function E.activate(id)
  E.message=nil;E.drag=nil
  if id=='portrait' or id=='landscape'then E.orientation=id
  elseif id=='back' or id=='menu'then E.selected=id
  elseif id=='save'then return E.close(true)
  elseif id=='cancel'then return E.close(false)
  elseif id=='reset'then E.data[E.orientation]=A.normalize()[E.orientation]
  else
    local area=E.data[E.orientation][E.selected]
    if id=='toggle'then area.enabled=not area.enabled
    elseif id=='smaller' or id=='larger'then
      area.size=math.max(A.MIN_SIZE,math.min(A.MAX_SIZE,area.size+(id=='smaller' and -.02 or .02)))
    end
  end
end
local function place(x,y)
  local p=E.layout().preview
  local d=E.drag
  if d then
    A.move(E.data,E.orientation,E.selected,(x-p.x)/p.scale-d.offX,
      (y-p.y)/p.scale-d.offY,p.logical)
  end
end
function E.touchpressed(id,x,y)
  if E.closed then return end
  local l=E.layout();if E.pointer then return end
  if id~='pad'then Pad.yieldToPointer()end
  for _,r in ipairs(l.hits)do if inside(r,x,y)then E.pointer={id=id,button=r.id,x=x,y=y};return end end
  local p=l.preview;if not inside(p,x,y)then return end
  local lx,ly=(x-p.x)/p.scale,(y-p.y)/p.scale
  local dx,dy=0,0
  for _,r in ipairs(A.rectangles(E.data,E.orientation,p.logical,true))do
    if inside(r,lx,ly)then
      E.selected=r.name;dx=lx-r.x-r.w/2;dy=ly-r.y-r.h/2;break
    end
  end
  E.pointer={id=id};E.drag={id=id,offX=dx,offY=dy};E.message=nil;place(x,y)
end
function E.touchmoved(id,x,y)
  E.layout()
  if E.pointer and E.pointer.id==id then
    if E.drag then place(x,y)
    elseif (x-E.pointer.x)^2+(y-E.pointer.y)^2>144 then E.pointer.moved=true end
  end
end
function E.touchreleased(id,x,y)
  E.layout()
  local p=E.pointer;if not p or p.id~=id then return end
  if E.drag then place(x,y)end
  E.pointer=nil;E.drag=nil
  if p.button and not p.moved then
    for _,r in ipairs(E.layout().hits)do
      if r.id==p.button and inside(r,x,y)then E.activate(r.id);break end
    end
  end
end
function E.update(dt)
  E.layout();Pad.update(dt or 0)
  if E.drag and E.drag.id=='pad'then local x,y=Pad.pointer();place(x,y)end
end
function E.draw()
  local g=love.graphics;local l=E.layout();local p=l.preview
  g.push('all');g.origin();g.setScissor();g.setShader()
  g.clear(.025,.04,.065,1);color(.95,.96,1);g.setFont(E.title)
  g.printf('タッチエリアの はいち',l.x,l.y+3,l.w,'center')
  g.setFont(E.font)
  for _,r in ipairs(l.hits)do
    local selected=r.id==E.orientation or r.id==E.selected
    color(selected and .16 or .09,selected and .30 or .14,selected and .36 or .20)
    g.rectangle('fill',r.x,r.y,r.w,r.h,5,5);color(.94,.97,1)
    g.printf(r.label,r.x,r.y+(r.h-E.font:getHeight())/2,r.w,'center')
  end
  local area=E.data[E.orientation][E.selected]
  color(.72,.80,.88)
  g.printf('おおきさ '..math.floor(area.size*100+.5)..'%　タップ・ドラッグで いどう',l.x+6,p.y-29,l.w-12,'center')
  color(.065,.105,.14);g.rectangle('fill',p.x,p.y,p.w,p.h)
  color(.30,.40,.48);g.setLineWidth(1);g.rectangle('line',p.x,p.y,p.w,p.h)
  g.line(p.x+p.w/2,p.y,p.x+p.w/2,p.y+p.h);g.line(p.x,p.y+p.h/2,p.x+p.w,p.y+p.h/2)
  local conflict=A.overlap(E.data,E.orientation,p.logical)
  for _,r in ipairs(A.rectangles(E.data,E.orientation,p.logical,true))do
    local x,y,w,h=p.x+r.x*p.scale,p.y+r.y*p.scale,r.w*p.scale,r.h*p.scale
    color(conflict and .85 or .18,conflict and .2 or .7,.42,r.enabled and .42 or .12)
    g.rectangle('fill',x,y,w,h);g.setLineWidth(r.name==E.selected and 3 or 1)
    color(.85,.96,.9,r.enabled and 1 or .45);g.rectangle('line',x,y,w,h)
    local label=r.name=='back' and 'もどる' or 'メニュー'
    local tw,th=E.font:getWidth(label),E.font:getHeight()
    if w<tw+6 then
      -- Small phone previews still need readable labels. Keep the marker
      -- at its true size and place its full-size label beside it.
      local tx=math.max(p.x+2,math.min(p.x+p.w-tw-2,x+w/2-tw/2))
      local ty=y+h+3;if ty+th>p.y+p.h then ty=y-th-3 end
      g.print(label,tx,ty)
    else g.print(label,x+w/2-tw/2,y+h/2-th/2)end
  end
  color(.75,.83,.9)
  g.printf(E.message or 'わくは へんしゅうちゅうだけ ひょうじします',l.x+6,l.footer-39,l.w-12,'center')
  Pad.draw();g.pop()
end
function E.mousepressed(x,y,b)if b==1 then E.touchpressed('mouse',x,y)end end
function E.mousemoved(x,y)if E.pointer and E.pointer.id=='mouse'then E.touchmoved('mouse',x,y)end end
function E.mousereleased(x,y,b)if b==1 then E.touchreleased('mouse',x,y)end end
function E.keypressed(key)
  if key=='escape' or key=='acback'then E.close(false)
  elseif key=='return'then E.close(true)
  elseif key=='tab'then E.activate(E.selected=='back' and 'menu' or 'back')
  elseif key=='-' then E.activate('smaller')elseif key=='='or key=='+'then E.activate('larger')
  elseif key=='up' or key=='down' or key=='left' or key=='right'then
    local p=E.layout().preview;local a=E.data[E.orientation][E.selected]
    A.move(E.data,E.orientation,E.selected,a.x*p.logical.w+(key=='left' and -5 or key=='right' and 5 or 0),
      a.y*p.logical.h+(key=='up' and -5 or key=='down' and 5 or 0),p.logical)
  end
end
function E.gamepadpressed(j,button)
  local action=Pad.gamepadpressed(j,button)
  if action=='b'then E.close(false)elseif action=='a'then
    local x,y=Pad.pointer();E.touchpressed('pad',x,y)
  elseif action=='tab_prev'then E.activate('smaller')elseif action=='tab_next'then E.activate('larger')end
end
function E.gamepadreleased(j,button)
  Pad.gamepadreleased(j,button)
  if button=='a'then local x,y=Pad.pointer();E.touchreleased('pad',x,y)end
end
function E.gamepadaxis(j,axis,value)Pad.gamepadaxis(j,axis,value)end
function E.focus()E.pointer=nil;E.drag=nil;Pad.reset()end
E.touchcancelled=E.focus
E.visible=E.focus
return E
