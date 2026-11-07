-- SPDX-License-Identifier: GPL-3.0-only
-- Shared 160x144 UI with genuine 8x8 bitmap glyphs and integer physical pixels.
-- Loaded games use their real Font module. The launcher reads only its own
-- version-qualified font PNGs; it never mounts a ROM or changes Font state.
local UI = { WIDTH=160, HEIGHT=144, CELL=8, LINE=16 }
local Font = require("src.render.Font")
local Json = require("src.link.Json")
local SafeArea = require("src.core.SafeArea")
local ClassicPalette = require("src.ui.ClassicPalette")
local frames, canvases, canvasSizes, cached = {}, {}, {}, {}
local bitmap, bitmapMap, bitmapQuads, latin, latinQuads
local function chars(text)
  local list={}
  for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do list[#list+1]=ch end
  return list
end
local function metrics()
  local g=love.graphics
  local w,h=g.getDimensions()
  local pw,ph=w,h
  if g.getPixelDimensions then pw,ph=g.getPixelDimensions() end
  return w,h,pw/math.max(1,w),ph/math.max(1,h)
end
function UI.layout(rect)
  local x,y,w,h
  if rect then x,y,w,h=rect.x or rect[1],rect.y or rect[2],rect.w or rect.width or rect[3],rect.h or rect.height or rect[4]
  else x,y,w,h=SafeArea.windowRect() end
  x,y,w,h=x or 0,y or 0,w or 160,h or 144
  local _,_,dx,dy=metrics()
  local scale=math.max(1,math.floor(math.min(w*dx/160,h*dy/144)))
  local sx,sy=scale/dx,scale/dy
  local ox=math.floor(x*dx+(w*dx-160*scale)/2)/dx
  local oy=math.floor(y*dy+(h*dy-144*scale)/2)/dy
  return {x=ox,y=oy,w=160*sx,h=144*sy,scale=scale,sx=sx,sy=sy,dpiX=dx,dpiY=dy,
    width=160,height=144,rect={x=x,y=y,w=w,h=h}}
end
function UI.hit(layout,x,y)
  layout=layout or UI.layout()
  local lx,ly=(x-layout.x)/layout.sx,(y-layout.y)/layout.sy
  return lx,ly,lx>=0 and ly>=0 and lx<(layout.width or 160) and ly<(layout.height or 144)
end
local function loadBitmap()
  if bitmap then return end
  bitmap=love.graphics.newImage("assets/fonts/misaki/misaki8x8.png")
  bitmap:setFilter("nearest","nearest")
  bitmapMap=assert(Json.decode(love.filesystem.read("assets/fonts/misaki/glyphs.json")))
  bitmapQuads={}
end
local function bitmapCode(ch)
  loadBitmap()
  local index=bitmapMap[ch] or bitmapMap["□"] or bitmapMap["?"]
  local quad=bitmapQuads[index]
  if not quad then
    local w,h=bitmap:getDimensions()
    quad=love.graphics.newQuad(index%128*8,math.floor(index/128)*8,8,8,w,h)
    bitmapQuads[index]=quad
  end
  return quad
end
local function bitmapGlyph(ch,x,y,sx,sy)
  local quad=bitmapCode(ch)
  love.graphics.draw(bitmap,quad,x,y,0,sx or 1,sy or sx or 1)
end
local function makePage(bytes,base,name)
  if type(bytes)~="string" then return end
  local ok,img=pcall(love.graphics.newImage,love.filesystem.newFileData(bytes,name))
  if not ok then return end
  local w,h=img:getDimensions()
  if w~=128 or h%8~=0 then img:release();return end
  img:setFilter("nearest","nearest")
  local page={image=img,base=base,quads={}}
  for i=0,w/8*h/8-1 do
    page.quads[i]=love.graphics.newQuad(i%16*8,math.floor(i/16)*8,8,8,w,h)
  end
  return page
end
function UI.invalidateCache(version)
  local function drop(entry)
    for _,p in ipairs(entry and entry.pages or {})do if p.image.release then p.image:release()end end
  end
  if version then drop(cached[version]);cached[version]=nil
  else for _,v in pairs(cached)do drop(v)end;cached={} end
end
local function cachedFont(version)
  if version~="red_jp" then return end
  local fs=require("src.import.CacheFs")
  local prefix=require("src.core.GameVersion").cachePrefix(version)
  local marker=fs.readAt(prefix.."rom-cache.complete")
  if not marker then UI.invalidateCache(version);return end
  if cached[version] and cached[version].marker==marker then return cached[version] end
  UI.invalidateCache(version)
  local main=makePage(fs.readAt(prefix.."assets/generated/fonts/font.png"),0x80,"jp-font.png")
  local extra=makePage(fs.readAt(prefix.."assets/generated/fonts/font_extra.png"),0x60,"jp-font-extra.png")
  if not (main and extra)then
    if main then main.image:release()end;if extra then extra.image:release()end;return
  end
  local manifest=assert(Json.decode(love.filesystem.read("tools/rom_manifest_red_jp.json")))
  local entry={marker=marker,pages={main,extra},map={},composites=manifest.fontComposites}
  for _,v in ipairs(manifest.fontCharmap)do entry.map[v.seq]=v.code end
  cached[version]=entry
  return entry
end
function UI.begin(game,opts)
  opts=opts or {}
  local g=love.graphics
  local layout=opts.layout or UI.layout(opts.rect)
  local mode="bitmap"
  local cache
  if opts.useROM~=false then
    if game and game.data and game.data.font then mode="game"
    elseif opts.version then cache=cachedFont(opts.version);if cache then mode="cache" end end
  end
  local depth=#frames+1
  local width,height=math.max(8,math.floor(layout.width or 160)),math.max(8,math.floor(layout.height or 144))
  local size=canvasSizes[depth]
  if not canvases[depth] or not size or size[1]~=width or size[2]~=height then
    if canvases[depth] and canvases[depth].release then canvases[depth]:release() end
    canvases[depth]=g.newCanvas(width,height,{dpiscale=1});canvases[depth]:setFilter("nearest","nearest")
    canvasSizes[depth]={width,height}
  end
  local frame={layout=layout,mode=mode,cache=cache,canvas=canvases[depth],previous=g.getCanvas(),
    colors=ClassicPalette.colors(game)}
  frames[depth]=frame
  g.push("all");g.origin();g.setShader();g.setScissor();g.setCanvas(frame.canvas)
  g.setBlendMode("alpha")
  local paper=opts.paper or {1,1,1,1}
  g.clear(paper[1],paper[2],paper[3],paper[4] or 1);g.setColor(0,0,0,1)
  layout.font=mode
  return layout
end
-- Draw in window coordinates before a transparent panel canvas is composed.
-- The paused game remains visible outside the frame, including its controls.
function UI.backdrop(layout,box,dim)
  local g=love.graphics
  box=box or {x=0,y=0,w=layout.width or 160,h=layout.height or 144}
  local x,y=layout.x+box.x*layout.sx,layout.y+box.y*layout.sy
  local w,h=box.w*layout.sx,box.h*layout.sy
  g.push("all");g.origin();g.setShader();g.setScissor()
  if dim and dim>0 then
    local ww,wh=g.getDimensions()
    g.setColor(0,0,0,dim);g.rectangle("fill",0,0,ww,wh)
  end
  g.setColor(0,0,0,0.22)
  g.rectangle("fill",x+2*layout.sx,y+3*layout.sy,w,h)
  g.pop()
end
function UI.finish()
  local frame=assert(table.remove(frames),"ClassicUI.finish without begin")
  local g,r=love.graphics,frame.layout
  g.setCanvas(frame.previous);g.origin();g.setShader();g.setScissor()
  g.setColor(1,1,1,1);g.setBlendMode("alpha","premultiplied")
  g.setShader(ClassicPalette.shader(frame.colors))
  g.draw(frame.canvas,r.x,r.y,0,r.sx,r.sy)
  g.pop()
  return r
end
function UI.width(text) return #chars(text)*8 end
function UI.clip(text,width)
  local values=chars(text);local n=math.max(0,math.floor((width or 160)/8))
  if #values<=n then return tostring(text or "") end
  if n<2 then return table.concat(values,"",1,n) end
  return table.concat(values,"",1,n-2)..".."
end
function UI.wrap(text,width)
  local limit=math.max(1,math.floor((width or 160)/8));local lines,line={},{}
  for _,ch in ipairs(chars(text))do
    if ch=="\n" then lines[#lines+1]=table.concat(line);line={}
    else
      if #line==limit then lines[#lines+1]=table.concat(line);line={} end
      line[#line+1]=ch
    end
  end
  lines[#lines+1]=table.concat(line)
  return lines
end
UI.bitmapWrap=UI.wrap
local function cacheCode(cache,code,x,y)
  local c=cache.composites[tostring(code)] or cache.composites[code]
  if c then cacheCode(cache,c.base,x,y);cacheCode(cache,c.mark,x,y+(c.dy or -8));return true end
  for _,page in ipairs(cache.pages)do
    local quad=page.quads[code-page.base]
    if quad then love.graphics.draw(page.image,quad,x,y);return true end
  end
end
local function latinGlyph(ch,x,y)
  local code=ch:byte()
  if #ch~=1 or code<32 or code>126 then return false end
  if not latin then
    latin=love.graphics.newImage("assets/fonts/latin8x8/latin.png");latin:setFilter("nearest","nearest");latinQuads={}
  end
  if not latinQuads[code]then
    local w,h=latin:getDimensions();latinQuads[code]=love.graphics.newQuad(code%16*8,math.floor(code/16)*8,8,8,w,h)
  end
  love.graphics.draw(latin,latinQuads[code],x,y);return true
end
function UI.text(text,x,y,opts)
  opts=opts or {};text=tostring(text or "")
  if opts.width and opts.clip~=false then text=UI.clip(text,opts.width) end
  local width=UI.width(text)
  if opts.align=="center"then x=x+math.floor(((opts.width or width)-width)/2)
  elseif opts.align=="right"then x=x+(opts.width or width)-width end
  x,y=math.floor(x),math.floor(y)
  local color=opts.color or {0,0,0,1}
  love.graphics.setColor(color[1],color[2],color[3],color[4] or 1)
  local frame=frames[#frames]
  local mode=frame and frame.mode or "bitmap"
  local pen=x
  for _,ch in ipairs(chars(text))do
    local drawn=false
    if mode=="game"then
      local span=Font.split(ch)[1]
      if span and span.code and span.code<Font.TTF_BASE then Font.drawCode(span.code,pen,y);drawn=true end
    elseif mode=="cache"then
      local code=frame.cache.map[ch]
      if code then drawn=cacheCode(frame.cache,code,pen,y) end
      if not drawn then drawn=latinGlyph(ch,pen,y) end
    end
    if not drawn then bitmapGlyph(ch,pen,y) end
    pen=pen+8
  end
  return width
end
function UI.box(tx,ty,tw,th,fill)
  local frame=frames[#frames]
  if frame and frame.mode=="game" then
    local rgb=fill and {fill[1]*255,fill[2]*255,fill[3]*255}
    return Font.drawBox(tx,ty,tw,th,rgb)
  end
  local g=love.graphics;local x,y,w,h=tx*8,ty*8,tw*8,th*8
  local paper=fill or {1,1,1,1}
  g.setColor(paper[1],paper[2],paper[3],paper[4] or 1);g.rectangle("fill",x,y,w,h)
  g.setColor(0,0,0,1)
  if frame and frame.mode=="cache" then
    local c=frame.cache
    cacheCode(c,0x79,x,y);cacheCode(c,0x7b,x+w-8,y)
    cacheCode(c,0x7d,x,y+h-8);cacheCode(c,0x7e,x+w-8,y+h-8)
    for i=1,tw-2 do cacheCode(c,0x7a,x+i*8,y);cacheCode(c,0x7a,x+i*8,y+h-8)end
    for i=1,th-2 do cacheCode(c,0x7c,x,y+i*8);cacheCode(c,0x7c,x+w-8,y+i*8)end
  else
    -- Original 1-pixel double rule; no copied launcher artwork.
    for _,inset in ipairs({1,3})do
      g.rectangle("fill",x+inset,y+inset,w-inset*2,1)
      g.rectangle("fill",x+inset,y+h-inset-1,w-inset*2,1)
      g.rectangle("fill",x+inset,y+inset,1,h-inset*2)
      g.rectangle("fill",x+w-inset-1,y+inset,1,h-inset*2)
    end
  end
end
function UI.cursor(x,y)
  local frame=frames[#frames]
  love.graphics.setColor(0,0,0,1)
  if frame and frame.mode=="game"then return Font.drawCode(require("src.ui.Theme").cursor,x,y)end
  if frame and frame.mode=="cache" and cacheCode(frame.cache,0xed,x,y)then return end
  for row=0,6 do love.graphics.rectangle("fill",x,y+row,4-math.abs(row-3),1)end
end
-- Window-space footer/button text. The scale is in physical screen pixels;
-- divide available LOVE-unit width by sx when passing it to bitmapWrap.
function UI.bitmapScale(scale)
  local _,_,dx,dy=metrics();scale=math.max(1,math.floor(scale or 1))
  return scale/dx,scale/dy
end
function UI.bitmapText(text,x,y,scale,color)
  local sx,sy=UI.bitmapScale(scale)
  local _,_,dx,dy=metrics();x,y=math.floor(x*dx)/dx,math.floor(y*dy)/dy
  color=color or {0,0,0,1};love.graphics.setColor(color[1],color[2],color[3],color[4] or 1)
  local pen=x
  for _,ch in ipairs(chars(text))do bitmapGlyph(ch,pen,y,sx,sy);pen=pen+8*sx end
  return pen-x
end
return UI
