-- SPDX-License-Identifier: GPL-3.0-only
-- Conservative bounds for the voxel vertex shader. Geometry keeps its exact
-- detail; only chunks entirely outside a clip plane can be skipped.
local Frustum = {}
local abs, min, max = math.abs, math.min, math.max
local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
local function matrix(m)
  if type(m) ~= "table" then return false end
  for i = 1, 16 do if not finite(m[i]) then return false end end
  return true
end

-- Build clip planes once per mesh draw, not once per chunk. Mat4 and shader
-- uniforms are row-major. GL's [-w,w] depth range is also conservative for
-- the shadow map's narrower [0,w] convention on newer graphics backends.
function Frustum.prepare(vp, model, cx, cz, k, padding)
  if not matrix(vp) then return nil end
  if model and (not matrix(model) or model[13] ~= 0 or model[14] ~= 0
      or model[15] ~= 0 or model[16] ~= 1) then return nil end
  cx, cz, k = cx or 0, cz or 0, k or 0
  padding = padding or 0
  if not (finite(cx) and finite(cz) and finite(k) and finite(padding)) then return nil end
  local planes = {}
  for row = 0, 8, 4 do
    for _, sign in ipairs({ 1, -1 }) do
      local at = #planes
      for col = 1, 4 do planes[at + col] = vp[12 + col] + sign * vp[row + col] end
    end
  end
  return { planes=planes, model=model, cx=cx, cz=cz, k=max(0,k),padding=abs(padding) }
end

function Frustum.test(bounds, context)
  -- Missing/unknown metadata or transforms draw in full, never disappear.
  if not context or type(bounds) ~= "table" then return true end
  for i = 1, 6 do if not finite(bounds[i]) then return true end end
  local x0,y0,z0,x1,y1,z1 = unpack(bounds,1,6)
  if x0>x1 or y0>y1 or z0>z1 then return true end
  local m = context.model
  if m then
    -- The center/extents form is the exact affine AABB of all eight corners,
    -- including negative scales and rotated/translated connected maps.
    local x,y,z = (x0+x1)*0.5,(y0+y1)*0.5,(z0+z1)*0.5
    local ex,ey,ez = (x1-x0)*0.5,(y1-y0)*0.5,(z1-z0)*0.5
    local wx,wy,wz = m[1]*x+m[2]*y+m[3]*z+m[4],
      m[5]*x+m[6]*y+m[7]*z+m[8],m[9]*x+m[10]*y+m[11]*z+m[12]
    local ax,ay,az = abs(m[1])*ex+abs(m[2])*ey+abs(m[3])*ez,
      abs(m[5])*ex+abs(m[6])*ey+abs(m[7])*ez,
      abs(m[9])*ex+abs(m[10])*ey+abs(m[11])*ez
    x0,y0,z0,x1,y1,z1 = wx-ax,wy-ay,wz-az,wx+ax,wy+ay,wz+az
  end
  if context.k > 0 then
    -- Curve follows the world transform in the GPU shader. Its closest
    -- point can be INSIDE a chunk, so testing bent corners alone is unsafe.
    -- Bound every possible quadratic drop before testing the clip planes.
    local dx0,dx1 = x0-context.cx,x1-context.cx
    local dz0,dz1 = z0-context.cz,z1-context.cz
    local nearX = dx0<=0 and dx1>=0 and 0 or min(abs(dx0),abs(dx1))
    local nearZ = dz0<=0 and dz1>=0 and 0 or min(abs(dz0),abs(dz1))
    local farX,farZ = max(abs(dx0),abs(dx1)),max(abs(dz0),abs(dz1))
    y0 = y0-context.k*(farX*farX+farZ*farZ)
    y1 = y1-context.k*(nearX*nearX+nearZ*nearZ)
  end
  -- Foliage's shader pulls each vertex toward the eye after bending. Its
  -- displacement in any axis cannot exceed pull, so expanded world bounds
  -- safely cover near/far clipping too; merely ignoring clip Z would not.
  local padding=context.padding or 0
  if padding>0 then
    x0,y0,z0,x1,y1,z1=x0-padding,y0-padding,z0-padding,x1+padding,y1+padding,z1+padding
  end
  if not (finite(x0) and finite(y0) and finite(z0)
      and finite(x1) and finite(y1) and finite(z1)) then return true end
  local p = context.planes
  for at = 1, 24, 4 do
    local a,b,c,d = p[at],p[at+1],p[at+2],p[at+3]
    local x,y,z = a>=0 and x1 or x0,b>=0 and y1 or y0,c>=0 and z1 or z0
    -- Float32 shader rounding at a plane must not cause one-pixel pop-in.
    local slack = 0.00001*(1+abs(a*x)+abs(b*y)+abs(c*z)+abs(d))
    if a*x+b*y+c*z+d < -slack then return false end
  end
  return true
end

function Frustum.visible(bounds, vp, model, cx, cz, k,padding)
  return Frustum.test(bounds, Frustum.prepare(vp,model,cx,cz,k,padding))
end

return Frustum
