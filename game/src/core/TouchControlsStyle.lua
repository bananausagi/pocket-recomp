-- Smooth physical controls. All material lighting is baked offline: runtime
-- only draws filtered textures and antialiased labels in the existing zones.
-- Action buttons and the cross use original generated product-photo assets.
-- Input, user layouts and imported touch skins are owned by TouchControls.
local Style={}
local images,fonts={},{}
local ROOT='assets/touch/hardware/'
local FONT='assets/fonts/noto/NotoSansJP-Regular.ttf'
local function image(name)
  if not images[name]then
    local img=love.graphics.newImage(ROOT..name..'.png',{mipmaps=true})
    img:setFilter('linear','linear');img:setMipmapFilter('linear',0)
    images[name]=img
  end
  return images[name]
end
local function font(size)
  size=math.max(8,math.floor(size+.5))
  if not fonts[size]then
    fonts[size]=love.graphics.newFont(FONT,size,'normal')
    fonts[size]:setFilter('linear','linear')
  end
  return fonts[size]
end
local function draw(name,x,y,w,h,alpha,tint)
  local img=image(name)
  love.graphics.setColor(tint or 1,tint or 1,tint or 1,alpha or 1)
  love.graphics.draw(img,x,y,0,w/img:getWidth(),h/img:getHeight())
end
local function label(text,cx,cy,size,maxWidth,color,alpha)
  local g=love.graphics
  local f=font(size)
  local scale=math.min(1,maxWidth/f:getWidth(text))
  local x=cx-f:getWidth(text)*scale/2
  local y=cy-f:getHeight()*scale/2
  g.setFont(f)
  -- A shallow printed/engraved mark, not a blocky bitmap character.
  g.setColor(0,0,0,.24*alpha)
  g.print(text,x,y+math.max(.4,size*.025),0,scale,scale)
  g.setColor(color[1],color[2],color[3],alpha)
  g.print(text,x,y,0,scale,scale)
end
local LIGHT={.92,.89,.88}
local DARK={.16,.17,.19}
local function button(zone,text,pressed,alpha)
  local small=#text>1
  local w,h=zone.w,small and zone.w*.50 or zone.w
  if small then
    draw('rubber'..(pressed and '-down' or '-up'),zone.cx-w/2,zone.cy-h/2,w,h,alpha)
  else
    local size=w*(pressed and .965 or 1)
    draw('ab-photo',zone.cx-size/2,zone.cy-size/2+(pressed and w*.012 or 0),size,size,alpha,pressed and .88 or 1)
  end
  local offset=h*(pressed and .024 or -.019)
  label(text,zone.cx,zone.cy+offset,zone.w*(small and .21 or .34),w*(small and .74 or .48),LIGHT,alpha)
end
local function dpad(zone,dir,alpha)
  local tilt=zone.w*.012
  local dx=dir=='left' and -tilt or dir=='right' and tilt or 0
  local dy=dir=='up' and -tilt or dir=='down' and tilt or 0
  local w,h=zone.w-(dx~=0 and tilt or 0),zone.w-(dy~=0 and tilt or 0)
  draw('dpad-photo',zone.cx-w/2+dx,zone.cy-h/2+dy,w,h,alpha,dir and .9 or 1)
end
local function stick(zone,value,alpha)
  draw('stick-ring',zone.cx-zone.w/2,zone.cy-zone.w/2,zone.w,zone.w,alpha)
  local w=zone.w*.35
  local x,y=zone.cx+value.x*zone.w/3,zone.cy+value.y*zone.w/3
  draw('knob'..(value.active and '-down' or '-up'),x-w/2,y-w/2,w,w,alpha)
end
function Style.action(x,y,w,h,scale,pressed,text)
  draw('action'..(pressed and '-down' or '-up'),x,y,w,h,1)
  if text then
    label(text,x+w/2,y+h/2+h*(pressed and .024 or -.019),11*scale,w-10*scale,DARK,1)
  end
end
function Style.draw(layout,held,direction,alpha,joystick,hideDpad,hideButtons)
  alpha=alpha or 1
  if not hideDpad then
    if joystick then stick(layout.dpad,joystick,alpha)else dpad(layout.dpad,direction,alpha)end
  end
  if hideButtons==true then return end
  button(layout.a,'A',held.a~=nil,alpha)
  button(layout.b,'B',held.b~=nil,alpha)
  -- jp.59: the A/B touch mode shows START and SELECT as well ('ab' used to
  -- stop after B).
  button(layout.select,'SELECT',held.select~=nil,alpha)
  button(layout.start,'START',held.start~=nil,alpha)
end
return Style
