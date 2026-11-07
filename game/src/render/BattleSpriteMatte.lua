-- Older extracted Gen 1 pictures removed every shade-zero pixel. Restore
-- only transparent regions enclosed by ink, before applying a GB palette.
-- Exterior-connected transparency (including space between limbs) is kept.
local Matte = {}

function Matte.restoreInterior(data)
  local w, h = data:getDimensions()
  local outside, queue, head = {}, {}, 1
  local function push(x, y)
    if x < 0 or x >= w or y < 0 or y >= h then return end
    local key = y * w + x
    if outside[key] then return end
    local _, _, _, a = data:getPixel(x, y)
    if a ~= 0 then return end
    outside[key] = true
    queue[#queue + 1] = key
  end
  for x = 0, w - 1 do push(x, 0); push(x, h - 1) end
  for y = 0, h - 1 do push(0, y); push(w - 1, y) end
  while head <= #queue do
    local key = queue[head]
    head = head + 1
    local x, y = key % w, math.floor(key / w)
    push(x - 1, y); push(x + 1, y); push(x, y - 1); push(x, y + 1)
  end
  local changed = false
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local _, _, _, a = data:getPixel(x, y)
      if a == 0 and not outside[y * w + x] then
        data:setPixel(x, y, 1, 1, 1, 1)
        changed = true
      end
    end
  end
  return changed
end

-- jp.91: back pictures (Pokemon backs, the player's back) run off the bottom
-- edge of their box, so an extractor matte flooded from all four borders ate
-- white body pixels that touch the bottom row and the field showed through the
-- body.  Flood the real outside from the top row and the side columns only;
-- any transparent pixel that flood cannot reach is body and becomes white.
-- cellH > 0 repairs a vertical stack of frames one cell at a time.
-- Front pictures are NOT passed here: the gap between their feet is open only
-- at the bottom and is real background.
function Matte.restoreOpenBottom(data, cellH)
  local w, h = data:getDimensions()
  cellH = (cellH and cellH > 0) and math.min(cellH, h) or h
  local changed = false
  for top = 0, h - 1, cellH do
    local bot = math.min(h, top + cellH) - 1
    local outside, queue, head = {}, {}, 1
    local function push(x, y)
      if x < 0 or x >= w or y < top or y > bot then return end
      local key = y * w + x
      if outside[key] then return end
      local _, _, _, a = data:getPixel(x, y)
      if a ~= 0 then return end
      outside[key] = true
      queue[#queue + 1] = key
    end
    for x = 0, w - 1 do push(x, top) end
    for y = top, bot do push(0, y); push(w - 1, y) end
    while head <= #queue do
      local key = queue[head]
      head = head + 1
      local x, y = key % w, math.floor(key / w)
      push(x - 1, y); push(x + 1, y); push(x, y - 1); push(x, y + 1)
    end
    for y = top, bot do
      for x = 0, w - 1 do
        local _, _, _, a = data:getPixel(x, y)
        if a == 0 and not outside[y * w + x] then
          data:setPixel(x, y, 1, 1, 1, 1)
          changed = true
        end
      end
    end
  end
  return changed
end

return Matte
