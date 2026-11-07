-- PC storage: 12 boxes of 20, like the original (wBoxDataStart / Bill's
-- PC, engine/pokemon/bills_pc.asm).  Older saves with a single `box`
-- list are migrated into box 1.

local Boxes = {}

Boxes.COUNT = 12
Boxes.CAPACITY = 20

function Boxes.count(save)
  return save and save.version == "red_jp" and 8 or Boxes.COUNT
end

function Boxes.capacity(save)
  return save and save.version == "red_jp" and 30 or Boxes.CAPACITY
end

function Boxes.ensure(save)
  if not save.boxes then
    save.boxes = {}
    for i = 1, Boxes.count(save) do save.boxes[i] = {} end
    save.currentBox = 1
    if save.box then -- migrate pre-12-box saves
      for _, mon in ipairs(save.box) do
        table.insert(save.boxes[1], mon)
      end
      save.box = nil
    end
  end
  save.currentBox = math.max(1, math.min(Boxes.count(save), save.currentBox or 1))
  return save.boxes
end

function Boxes.active(save)
  return Boxes.ensure(save)[save.currentBox]
end

-- Deposit into the current box; overflows into the next box with room
-- (divergence: the original refuses the catch when the box is full --
-- docs/known-differences.md).  Returns the box number used, or nil.
function Boxes.deposit(save, mon)
  local boxes = Boxes.ensure(save)
  for off = 0, Boxes.count(save) - 1 do
    local i = ((save.currentBox - 1 + off) % Boxes.count(save)) + 1
    if #boxes[i] < Boxes.capacity(save) then
      table.insert(boxes[i], mon)
      return i
    end
  end
  return nil
end

return Boxes
