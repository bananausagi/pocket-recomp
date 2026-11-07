-- Invisible, user-placed Back/Menu areas. Coordinates are fractions of the
-- OS safe area, with independent portrait and landscape layouts.
local A={MIN_SIZE=.08,MAX_SIZE=.35}
local ids={'back','menu'}
local function finite(n,fallback,lo,hi)
  if type(n)~='number' or n~=n or math.abs(n)==math.huge then n=fallback end
  return math.max(lo,math.min(hi,n))
end
function A.orientation(w,h)return w>h and 'landscape' or 'portrait'end
function A.normalize(value)
  value=type(value)=='table' and value or {}
  local out={}
  for _,orientation in ipairs({'portrait','landscape'})do
    local source=type(value[orientation])=='table' and value[orientation] or {}
    out[orientation]={}
    for i,id in ipairs(ids)do
      local area=type(source[id])=='table' and source[id] or {}
      out[orientation][id]={x=finite(area.x,i==1 and .16 or .84,0,1),
        y=finite(area.y,.18,0,1),size=finite(area.size,.14,A.MIN_SIZE,A.MAX_SIZE),
        enabled=area.enabled~=false}
    end
  end
  return out
end
function A.rectangles(value,orientation,bounds,includeDisabled)
  local layout=A.normalize(value)[orientation]
  local x,y,w,h=bounds.x,bounds.y,bounds.w,bounds.h
  local out={}
  for _,id in ipairs(ids)do
    local a=layout[id]
    if includeDisabled or a.enabled then
      local size=math.min(w,h,math.max(40,math.min(w,h)*a.size))
      local cx=math.max(size/2,math.min(w-size/2,w*a.x))
      local cy=math.max(size/2,math.min(h-size/2,h*a.y))
      out[#out+1]={id='touch-'..id,name=id,x=x+cx-size/2,y=y+cy-size/2,
        w=size,h=size,enabled=a.enabled}
    end
  end
  return out
end
function A.navigation(value)
  local x,y,w,h=require('src.core.SafeArea').windowRect()
  return A.rectangles(value,A.orientation(w,h),{x=x,y=y,w=w,h=h})
end
function A.move(value,orientation,id,x,y,bounds)
  local a=value[orientation][id]
  a.x=finite((x-bounds.x)/bounds.w,.5,0,1)
  a.y=finite((y-bounds.y)/bounds.h,.5,0,1)
  for _,r in ipairs(A.rectangles(value,orientation,bounds,true))do
    if r.name==id then
      a.x=(r.x+r.w/2-bounds.x)/bounds.w;a.y=(r.y+r.h/2-bounds.y)/bounds.h
    end
  end
end
function A.overlap(value,orientation,bounds)
  local rs=A.rectangles(value,orientation,bounds)
  local a,b=rs[1],rs[2]
  return a and b and a.x<b.x+b.w and b.x<a.x+a.w
    and a.y<b.y+b.h and b.y<a.y+a.h or false
end
function A.key(value)
  local layout=A.normalize(value);local values={}
  for _,orientation in ipairs({'portrait','landscape'})do
    for _,id in ipairs(ids)do
      local a=layout[orientation][id]
      values[#values+1]=table.concat({a.x,a.y,a.size,a.enabled and 1 or 0},',')
    end
  end
  return table.concat(values,';')
end
return A
