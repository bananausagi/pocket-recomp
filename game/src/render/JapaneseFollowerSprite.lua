-- The party-list icon's native pixels. Full-color worlds use
-- the species palette over its original 2bpp shades, before OBJ registers
-- collapse them to the party menu's monochrome ramp. No picture is resized.
local Assets = require('src.render.Assets')
local PaletteFX = require('src.render.PaletteFX')
local PokemonIcon = require('src.ui.PokemonIcon')

local Follower = {}
Follower.__index = Follower
local entries, clock, epoch = {}, 0, 0
local failures,failureOrder={},{}
local MAX_ENTRIES, MAX_COLORS = 8, 4
local NATIVE_DIRECTIONS={MON=true,FAIRY=true,BIRD=true,WATER=true,PIKACHU=true}

local function posesFor(icon)
  local poses={PokemonIcon.pose(icon,false),PokemonIcon.pose(icon,true)}
  -- These classes explicitly reuse the imported six-frame overworld sheet.
  -- A pokemon.icon replacement owns its own layout: never interpret an
  -- arbitrary tall replacement image as the original walking sheet.
  local directions=NATIVE_DIRECTIONS[icon.name] and icon.path==icon.sourcePath
    and icon.width==16 and icon.height>=96
  if directions then
    for _,frame in ipairs({1,4,2,5}) do
      poses[#poses+1]={frame=frame,mirrorHalf=false,dy=0,width=16,height=16}
    end
  end
  return poses,directions and true or false
end

local function dispose(object)
  if object and object.release then pcall(object.release, object) end
end
local function releaseEntry(entry)
  dispose(entry.raw); dispose(entry.pixels); dispose(entry.colorPixels)
  for _, image in pairs(entry.colors) do dispose(image) end
end
local function clear()
  for _, entry in pairs(entries) do releaseEntry(entry) end
  entries, clock, epoch = {}, 0, epoch + 1
  failures,failureOrder={},{}
end
Assets.register({invalidate=clear, release=clear})
Follower.invalidate = clear

local function readImage(image)
  local g = love.graphics
  local oldCanvas = g.getCanvas()
  local canvas = g.newCanvas(image:getWidth(), image:getHeight(), {dpiscale=1})
  g.push('all'); g.setCanvas(canvas); g.clear(0,0,0,0)
  g.setShader(); g.setScissor(); g.origin(); g.setColor(1,1,1,1)
  g.setBlendMode('replace'); g.draw(image); g.setCanvas()
  local pixels = canvas:newImageData()
  g.pop(); g.setCanvas(oldCanvas); dispose(canvas)
  return pixels
end

local function makeImage(pixels)
  local image = love.graphics.newImage(pixels)
  image:setFilter('nearest','nearest')
  return image
end

-- Compose the menu's mirrored OAM halves once, rather than each render pass.
-- Native OBJ index zero is transparent in the field.  Determine that mask
-- BEFORE OBP maps index one to white, so a white body is never punched out.
local function build(icon, poses)
  local w, h = poses[1].width, poses[1].height
  if w < 1 or h < 1 or w > 128 or h > 128
      or icon.width > 512 or icon.height > 512 then return nil end
  for _,pose in ipairs(poses) do
    if pose.width ~= w or pose.height ~= h then return nil end
  end
  local source = readImage(icon.image)
  local mask = icon.baked and Assets.imageData(icon.path) or nil
  local out = love.image.newImageData(w,h*#poses)
  local colorOut = love.image.newImageData(w,h*#poses)
  local mw,mh = mask and mask:getWidth(), mask and mask:getHeight()
  for phase=0,#poses-1 do
    local pose=poses[phase+1]
    local sy0=pose.frame*16
    if sy0+h > icon.height then sy0=0 end
    for y=0,h-1 do for x=0,w-1 do
      local sx=pose.mirrorHalf and (x < 8 and x or 15-x) or x
      local sy=sy0+y
      if sx >= 0 and sx < icon.width and sy < icon.height then
        local r,g,b,a=source:getPixel(sx,sy)
        local cr,cg,cb=r,g,b
        if mask and sx < mw and sy < mh then
          local shade,_,_,alpha=mask:getPixel(sx,sy)
          if alpha == 0 or shade > .83 then a=0 end
          -- Keep both original visible tones for the species palette. The
          -- ordinary monochrome copy still follows the native OBP mapping.
          cr,cg,cb=shade,shade,shade
        end
        out:setPixel(x,phase*h+y,r,g,b,a)
        colorOut:setPixel(x,phase*h+y,cr,cg,cb,a)
      end
    end end
  end
  dispose(source); dispose(mask)
  return {pixels=out,colorPixels=colorOut,raw=makeImage(out),width=w,height=h,
    offsets={poses[1].dy or 0,poses[2].dy or 0},colors={},colorOrder={}}
end

local function signature(icon,poses)
  local parts={tostring(icon.image),Assets.resolve(icon.path),tostring(icon.name),
    tostring(icon.baked),tostring(icon.trueColor)}
  for _,p in ipairs(poses) do
    parts[#parts+1]=table.concat({p.frame,p.width,p.height,p.dy or 0,
      p.mirrorHalf and 1 or 0},':')
  end
  return table.concat(parts,'|')
end

local function prepare(self)
  if self.released then return nil end
  -- false deliberately requests ordinary gray OBP even in OG RED. Flat /
  -- tilt still run their own map shader; 3D supplies its map colors below.
  local icon=PokemonIcon.resolve(self.game,self.mon,false)
  if not icon then return nil end
  local poses,directions=posesFor(icon)
  local key=signature(icon,poses)
  if failures[key] then return nil end
  local entry=entries[key]
  clock=clock+1
  if not entry then
    local ok,value=pcall(build,icon,poses)
    if not (ok and value) then
      failures[key]=true;failureOrder[#failureOrder+1]=key
      if #failureOrder>16 then failures[table.remove(failureOrder,1)]=nil end
      return nil
    end
    entry=value;entries[key]=entry
    local count,oldestKey,oldest=0,nil,math.huge
    for k,e in pairs(entries) do
      count=count+1
      if k~=key and (e.used or 0)<oldest then oldestKey,oldest=k,e.used or 0 end
    end
    if count>MAX_ENTRIES then releaseEntry(entries[oldestKey]);entries[oldestKey]=nil end
  end
  entry.used=clock
  if self.key~=key or self.sourceEpoch~=epoch then
    if self.frames then for _,quad in pairs(self.frames) do dispose(quad) end end
    self.key,self.sourceEpoch=key,epoch
    self.frameWidth,self.frameHeight=entry.width,entry.height
    self.anchorX,self.anchorY=entry.width/2,entry.height
    self.frames={}
    self.frameCount=#poses
    for phase=0,#poses-1 do self.frames[phase]=love.graphics.newQuad(0,phase*entry.height,
      entry.width,entry.height,entry.width,entry.height*#poses) end
    local d=self.def
    d.image=Assets.resolve(icon.path)
    d.frameWidth,d.frameHeight=entry.width,entry.height
    d.imageWidth,d.imageHeight=entry.width,entry.height*#poses
    d.frames,d.jpFollowerDirections=#poses,directions
    d.anchorX,d.anchorY=self.anchorX,self.anchorY
  end
  self.icon,self.entry,self.image=icon,entry,entry.raw
  return entry
end

local function palette(colors)
  if PaletteFX.usesSpriteObp() then
    local og=PaletteFX.ogObjNormal()
    colors={og[2],og[3],og[3],og[4]}
  end
  return PaletteFX.effectiveColors(colors or PaletteFX.GRAYS) or PaletteFX.GRAYS
end

local function colored(entry,colors,nativeShades)
  local parts={nativeShades and 'native' or 'obj'}
  for _,c in ipairs(colors) do for i=1,3 do parts[#parts+1]=tostring(c[i]) end end
  local key=table.concat(parts,':')
  if not entry.colors[key] then
    local pixels=(nativeShades and entry.colorPixels or entry.pixels):clone()
    pixels:mapPixel(function(_,_,r,g,b,a)
      if a==0 then return r,g,b,a end
      local shade=r*.2126+g*.7152+b*.0722
      local c=colors[shade>.83 and 1 or shade>.5 and 2 or shade>.17 and 3 or 4]
      return c[1]/255,c[2]/255,c[3]/255,a
    end)
    entry.colors[key]=makeImage(pixels);dispose(pixels)
    entry.colorOrder[#entry.colorOrder+1]=key
    if #entry.colorOrder>MAX_COLORS then
      local drop=table.remove(entry.colorOrder,1)
      dispose(entry.colors[drop]);entry.colors[drop]=nil
    end
  end
  return entry.colors[key]
end

local function fullColorImage(self,entry)
  -- A supplied colored icon owns its colors; applying the species ramp to
  -- it would overwrite an icon MOD, including any per-individual skin.
  if self.icon.trueColor then return entry.raw end
  local colors=PaletteFX.monPal(self.game.data,self.mon.species) or PaletteFX.GRAYS
  colors=PaletteFX.effectiveColors(colors) or PaletteFX.GRAYS
  colors=PaletteFX.darkObp(colors,'jp-follower-icon')
  colors=PaletteFX.fadeObp(colors,'jp-follower-icon')
  return colored(entry,colors,true)
end

function Follower.new(data,mon)
  if not (data and mon and data.pokemon and data.pokemon[mon.species]) then return nil end
  local self=setmetatable({game={data=data},mon=mon,frameCount=2,
    def={frames=2,walker=true,trueColor=true,jpFollower=true,jpFollowerIcon=true}},Follower)
  if not prepare(self) then self:release();return nil end
  return self
end

function Follower:resolveImage(colors)
  local entry=prepare(self)
  if not entry then return nil end
  if PaletteFX.honorsTrueColor() then return fullColorImage(self,entry) end
  return colored(entry,palette(colors))
end

function Follower:selectFrame(facing,walkPhase)
  local offset,mirror=0,false
  if self.def.jpFollowerDirections then
    if facing=='up' then offset=2
    elseif facing=='left' or facing=='right' then offset=4;mirror=facing=='right' end
  end
  return offset+(walkPhase==1 and 1 or 0),mirror
end
function Follower:poseOffset(walkPhase)
  local entry=prepare(self)
  return entry and entry.offsets[walkPhase==1 and 2 or 1] or 0
end
function Follower:getFrameGeometry(frame)
  prepare(self)
  frame=math.max(0,math.min(self.frameCount-1,math.floor(tonumber(frame) or 0)))
  return {frame=frame,x=0,y=frame*self.frameHeight,width=self.frameWidth,
    height=self.frameHeight,anchorX=self.anchorX,anchorY=self.anchorY,quad=self.frames[frame]}
end
function Follower:getPoseGeometry(facing,walkPhase,stepFlip)
  prepare(self)
  local frame,mirror=self:selectFrame(facing,walkPhase)
  local out=self:getFrameGeometry(frame)
  out.facing,out.walkPhase,out.stepFlip,out.mirror=facing,walkPhase,stepFlip,mirror
  return out
end
function Follower:getScreenOrigin(px,py,camX,camY)
  return math.floor(px-camX)+8-self.anchorX,math.floor(py-camY)+12-self.anchorY
end
function Follower:draw(px,py,camX,camY,facing,walkPhase)
  local entry=prepare(self)
  if not entry then return end
  local frame,mirror=self:selectFrame(facing,walkPhase)
  local x,y=self:getScreenOrigin(px,py,camX,camY)
  local fullColor=PaletteFX.honorsTrueColor()
  local image=fullColor and fullColorImage(self,entry) or entry.raw
  if fullColor then
    PaletteFX.markTrueColor(x,y,self.frameWidth,self.frameHeight)
  end
  if mirror then love.graphics.draw(image,self.frames[frame],x+self.frameWidth,y,0,-1,1)
  else love.graphics.draw(image,self.frames[frame],x,y) end
end
function Follower:release()
  if self.frames then for _,quad in pairs(self.frames) do dispose(quad) end end
  self.frames,self.entry,self.image,self.released=nil,nil,nil,true
end

return Follower
