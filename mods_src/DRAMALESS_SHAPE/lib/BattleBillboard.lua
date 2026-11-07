-- Dramaless's original native-battle-picture world card.
-- Kept in 2.x because only Stadium model extraction/rendering moved to SBFX;
-- the native Gen 1 card presentation remains Dramaless-owned.

local V = ...
local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")

local Billboard = {
  FULL_W = 16,
  FULL_PIC = 56,
  PULL = 1.5,
}

local quad

function Billboard.mesh()
  if quad ~= nil then return quad or nil end
  local vertices = {
    { -0.5, 0, 0, 0, 1, 1 },
    {  0.5, 0, 0, 1, 1, 1 },
    {  0.5, 1, 0, 1, 0, 1 },
    { -0.5, 1, 0, 0, 0, 1 },
  }
  local indices = {}
  Voxel3D.pushQuad(indices, 0)
  quad = Voxel3D.newMesh(vertices, indices) or false
  return quad or nil
end

function Billboard.yawToward(x, z, eye)
  if not eye then return 0 end
  return math.atan2(eye[1] - x, eye[3] - z)
end

function Billboard.matrix(texture, anchorX, anchorY, x, y, z, mirror, distanceScale,presentation)
  local scale = presentation and presentation.worldPerPixel
    or Billboard.FULL_W / Billboard.FULL_PIC * (distanceScale or 1)
  local width, height = 160 * scale, 144 * scale
  local ox = -((anchorX / 160) - 0.5) * width
  local oy = -((144 - anchorY) / 144) * height
  local card = Mat4.mul(Mat4.translate(ox, oy, 0), Mat4.scale(width, height, 1))
  if mirror then card = Mat4.mul(Mat4.scale(-1, 1, 1), card) end
  if presentation and presentation.faceCamera then
    local camera=Voxel3D.camera
    local view=Mat4.lookAt(Voxel3D.eye,Voxel3D.focus,camera and camera.up or {0,1,0})
    local facing={view[1],view[5],view[9],x,
      view[2],view[6],view[10],y,view[3],view[7],view[11],z,0,0,0,1}
    return Mat4.mul(facing,card)
  end
  local yaw = Billboard.yawToward(x, z, Voxel3D.eye)
  return Mat4.mul(Mat4.mul(Mat4.translate(x, y, z), Mat4.rotateY(yaw)), card)
end

function Billboard.invalidate()
  quad = nil
end

return Billboard
