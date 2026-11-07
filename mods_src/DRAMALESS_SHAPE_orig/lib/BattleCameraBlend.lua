-- Presentation-only camera handoff. No player position or free-camera input
-- state changes: the next world frame still computes its own destination.
local Blend={}
local returning
local function vector(v,fallback)
  v=v or fallback
  return {v[1],v[2],v[3]}
end
function Blend.copy(pose)
  if not (pose and pose.eye and pose.focus and pose.fov) then return nil end
  return {eye=vector(pose.eye),focus=vector(pose.focus),up=vector(pose.up,{0,1,0}),
    fov=pose.fov,curve=pose.curve or 0,filmX=pose.filmX or 0,filmY=pose.filmY or 0,
    curveX=pose.curveX or pose.focus[1],curveZ=pose.curveZ or pose.focus[3]}
end
local function length(v)return math.sqrt(v[1]^2+v[2]^2+v[3]^2)end
local function unit(v)
  local n=length(v)
  if n<1e-8 then return {0,0,1} end
  return {v[1]/n,v[2]/n,v[3]/n}
end
local function direction(a,b,t)
  a,b=unit(a),unit(b)
  local dot=math.max(-1,math.min(1,a[1]*b[1]+a[2]*b[2]+a[3]*b[3]))
  local theta=math.acos(dot)
  if theta<1e-5 then return a end
  local tangent={b[1]-a[1]*dot,b[2]-a[2]*dot,b[3]-a[3]*dot}
  if length(tangent)<1e-6 then
    tangent=math.abs(a[2])<.9 and {-a[3],0,a[1]} or {0,a[3],-a[2]}
  end
  tangent=unit(tangent)
  local c,s=math.cos(theta*t),math.sin(theta*t)
  return {a[1]*c+tangent[1]*s,a[2]*c+tangent[2]*s,a[3]*c+tangent[3]*s}
end
local function mix(from,to,t,easing)
  if t<=0 then return Blend.copy(from) end
  if t>=1 then return Blend.copy(to) end
  local e=easing and easing(t) or t*t*(3-2*t)
  local a,b=Blend.copy(from),Blend.copy(to)
  local focus={}
  for i=1,3 do focus[i]=a.focus[i]+(b.focus[i]-a.focus[i])*e end
  local av,bv={},{}
  for i=1,3 do av[i]=a.eye[i]-a.focus[i];bv[i]=b.eye[i]-b.focus[i] end
  local ray=direction(av,bv,e)
  local dist=length(av)+(length(bv)-length(av))*e
  local eye={focus[1]+ray[1]*dist,focus[2]+ray[2]*dist,focus[3]+ray[3]*dist}
  local up=direction(a.up,b.up,e)
  local parallel=math.abs(up[1]*ray[1]+up[2]*ray[2]+up[3]*ray[3])
  if parallel>.999 then up=math.abs(ray[2])<.9 and {0,1,0} or {0,0,-1} end
  return {eye=eye,focus=focus,up=up,fov=a.fov+(b.fov-a.fov)*e,
    curve=a.curve+(b.curve-a.curve)*e,
    curveX=a.curveX+(b.curveX-a.curveX)*e,curveZ=a.curveZ+(b.curveZ-a.curveZ)*e,
    filmX=a.filmX+(b.filmX-a.filmX)*e,filmY=a.filmY+(b.filmY-a.filmY)*e}
end
function Blend.mix(from,to,t) return mix(from,to,t) end
function Blend.encounter(from,to,t)
  -- Short lens cue, then a quick orbit which eases gently into the shot.
  -- Both endpoints preserve every projection/curve field exactly.
  if t<=0 then return Blend.copy(from) end
  if t>=1 then return Blend.copy(to) end
  local move=math.max(0,(t-.08)/.92)
  local pose=mix(from,to,move,function(p)return 1-(1-p)^3 end)
  local pulse=t<.28 and math.sin(math.pi*t/.28)^2 or 0
  pose.fov=pose.fov*(1-.055*pulse)
  return pose
end
function Blend.returnFrom(pose,duration)
  local saved=Blend.copy(pose)
  returning=saved and {pose=saved,time=0,duration=duration or .4} or nil
end
function Blend.update(dt)
  if returning then returning.time=returning.time+math.max(0,dt or 0) end
end
function Blend.active()return returning~=nil end
function Blend.applyReturn(target)
  if not returning then return target end
  local t=returning.time/returning.duration
  if t>=1 then returning=nil;return target end
  return Blend.mix(returning.pose,target,t)
end
function Blend.cancel()returning=nil end
return Blend
