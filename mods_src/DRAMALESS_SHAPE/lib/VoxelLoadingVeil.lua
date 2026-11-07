-- Retain the last drawable world while an area mesh is queued. The scene
-- returns before touching its GPU targets when terrain is absent, so borrowing
-- the final surface needs neither a full-screen copy per frame nor black art.
-- Canvas lifetime belongs to the renderer; this module never releases it.
local Veil={}
local previous
function Veil.remember(canvas,w,h)
  if canvas then previous={canvas=canvas,w=w,h=h} end
end
function Veil.get(w,h)
  if not previous or previous.w~=w or previous.h~=h then return nil end
  local ok,cw,ch=pcall(previous.canvas.getDimensions,previous.canvas)
  if ok and cw==w and ch==h then return previous.canvas end
  previous=nil
end
function Veil.invalidate() previous=nil end
return Veil
