-- The four-box options viewport, extracted from OptionsMenu so the mod
-- manager's per-mod options auto-UI renders schemas in the same idiom.
-- Rows are descriptors:
--   { id, label, value = fn(game) -> string,
--     step = fn(game, dir) -> changed, activate = fn(game) }
-- step handles Left/Right/A cyclers; activate is the A-press action for
-- rows that open something instead (MODS, CANCEL stays the caller's).

local Font = require("src.render.Font")
local Marquee = require("src.ui.Marquee")
local Theme = require("src.ui.Theme")
local Strings = require("src.core.Strings")

local OptionRows = {}

OptionRows.VISIBLE = 4 -- option boxes on screen at once (4 tiles each)

function OptionRows.visibleRows()
  return Font.lineHeight() > 8 and 3 or OptionRows.VISIBLE
end

-- Font.drawBox(0, y, 20, 4) spends column 19 on the frame, so a line drawn
-- to the 160px screen edge prints over its own border.
local CONTENT_RIGHT = 152
local function fits(x) return math.floor((CONTENT_RIGHT - x) / 8) end

-- keep the cursor's box inside the viewport; the fixed bottom row shows
-- the tail of the list
function OptionRows.clampScroll(index, scroll, total, bottomRow)
  local visible = OptionRows.visibleRows()
  if bottomRow and index >= bottomRow then
    return math.max(0, total - visible)
  elseif index <= scroll then
    return index - 1
  elseif index > scroll + visible then
    return index - visible
  end
  return scroll
end

-- one bordered box per row, label line + value line, with the fixed
-- bottom line below (BACK in the options menu, the manager's footer)
function OptionRows.draw(game, rows, index, scroll, bottomLabel, bottomRow)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  local japanese = Font.lineHeight() > 8
  local visible = OptionRows.visibleRows()
  if japanese then Font.drawBox(0, 0, 20, 18) end
  for slot = 1, visible do
    local i = scroll + slot
    local row = rows[i]
    if not row then break end
    if not japanese then Font.drawBox(0, (slot - 1) * 4, 20, 4) end
    love.graphics.setColor(0, 0, 0, 1)
    local label = Strings(row.label or "")
    local value = Strings(row.value and row.value(game) or "")
    if i == index then
      local key = tostring(row.id or row.label) .. "\0" .. tostring(value)
      label = Marquee.scroll(label, fits(16), key)
      value = Marquee.scroll(value, fits(24), key)
    else
      label = Marquee.clip(label, fits(16))
      value = Marquee.clip(value, fits(24))
    end
    local labelY = japanese and (16 + (slot - 1) * 40) or ((slot - 1) * 4 + 1) * 8
    Font.draw(label, 16, labelY)
    Font.draw(value, 24, labelY + (japanese and 16 or 8))
    if i == index then
      Font.drawCode(Theme.cursor, 8, labelY)
    end
  end
  if scroll + visible < #rows then
    Font.drawCode(Theme.moreArrow, 144, japanese and 120 or 128)
  end
  if bottomLabel then
    love.graphics.setColor(0, 0, 0, 1)
    local y = japanese and 128 or 136
    Font.draw(Strings(bottomLabel), 16, y)
    if bottomRow and index == bottomRow then
      Font.drawCode(Theme.cursor, 8, y)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return OptionRows
