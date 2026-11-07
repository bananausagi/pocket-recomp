local TouchTargets=require('src.ui.JapaneseTouchTargets')
-- Generic bordered list menu with the blinking ▶ cursor.
-- items: { { label=..., onSelect=function }, ... }
-- Pops itself on B (unless cancelable=false or opts.keepOnCancel); also on
-- START only when opts.startCloses is set -- pokered's wMenuWatchedKeys mask
-- varies per menu and only the start menu's adds PAD_START.

local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")

local Menu = {}
Menu.__index = Menu

function Menu.new(game, items, opts)
  local self = setmetatable({}, Menu)
  opts = opts or {}
  self.game = game
  self.items = items
  self.index = 1
  self.tx = opts.tx or 10
  self.ty = opts.ty or 0
  self.tw = opts.tw or 10
  -- grow the box to the widest label so longer (e.g. localized) labels don't
  -- overflow the frame; nudge tx left to keep the box on-screen (20 tiles).
  do
    local widest = 0
    for _, it in ipairs(items) do
      if it.label then
        local n = #Font.split(it.label)
        if n > widest then widest = n end
      end
    end
    local needed = widest + 3
    if needed > self.tw then self.tw = needed end
    if self.tx + self.tw > 20 then self.tx = math.max(0, 20 - self.tw) end
  end
  self.rowStep = opts.rowStep or 2
  -- home/window.asm:56-83
  self.noWrap = opts.noWrap or false
  -- engine/movie/oak_speech/oak_speech2.asm:162 (DisplayIntroNameTextBox)
  self.title = opts.title
  self.itemY = opts.itemY
  -- maxVisible: cap the box to this many rows and scroll the rest instead
  -- of growing past it (e.g. the start menu, whose row count varies with
  -- save state and mod hooks); nil/unset keeps every caller's old
  -- behavior of sizing the box to fit all items.
  self.maxVisible = opts.maxVisible
  self.scroll = 0
  local visible = (self.maxVisible and math.min(self.maxVisible, #items))
    or #items
  self.th = opts.th or (visible * self.rowStep + 2)
  self.autoHeight = opts.th == nil
  self.cancelable = opts.cancelable ~= false
  -- Whether START closes the menu.  In pokered a menu responds only to the
  -- keys in its wMenuWatchedKeys mask; the common PAD_A | PAD_B (and the
  -- list menu's PAD_A | PAD_B | PAD_SELECT) masks leave START unwatched, so
  -- only menus whose real mask includes PAD_START -- the start menu
  -- (engine/menus/draw_start_menu.asm) -- opt in here.
  self.startCloses = opts.startCloses or false
  -- screen-edge anchor for this menu (see Menu:draw); nil keeps it in the
  -- classic centred letterbox
  self.anchor = opts.anchor
  self.onCancel = opts.onCancel
  -- engine/events/cinnabar_lab.asm:70-73
  self.keepOnCancel = opts.keepOnCancel or false
  -- BIT_NO_MENU_BUTTON_SOUND (wMiscFlags): the PC session runs its
  -- menus silent (home/window.asm HandleMenuInput_)
  self.noSound = opts.noSound or false
  self:clampScroll()
  return self
end

-- keeps self.index inside the visible [scroll+1, scroll+maxVisible] window;
-- callers that move self.index directly (e.g. restoring a saved cursor
-- position) should call this afterwards to scroll it into view
function Menu:clampScroll()
  if not (self.maxVisible and #self.items > self.maxVisible) then
    self.scroll = 0
    return
  end
  if self.index - self.scroll > self.maxVisible then
    self.scroll = self.index - self.maxVisible
  elseif self.index - self.scroll < 1 then
    self.scroll = self.index - 1
  end
end

function Menu:update(dt)
  local input = self.game.input
  -- engine/events/cinnabar_lab.asm:29
  if self.frozen then return end
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1
      or (self.noWrap and 1 or #self.items)
  elseif input:wasPressed("down") then
    self.index = self.index < #self.items and self.index + 1
      or (self.noWrap and #self.items or 1)
  elseif input:wasPressed("a") then
    -- HandleMenuInput_ (home/window.asm): SFX_PRESS_AB on every A press
    if not self.noSound then
      require("src.core.Sound").play(self.game.data, "Press_AB")
    end
    local item = self.items[self.index]
    -- keepOpen entries run without closing the menu (e.g. the
    -- Pokédex CRY option keeps the side menu up)
    if not item.keepOpen then self.game.stack:pop() end
    if item.onSelect then item.onSelect() end
  elseif self.cancelable and (input:wasPressed("b")
      or (self.startCloses and input:wasPressed("start"))) then
    -- HandleMenuInput_ returns for any watched key, but only replays
    -- SFX_PRESS_AB for the PAD_A | PAD_B branch -- so B beeps and START
    -- (when watched, e.g. the start menu) closes silently.
    if input:wasPressed("b") and not self.noSound then
      require("src.core.Sound").play(self.game.data, "Press_AB")
    end
    if not self.keepOnCancel then self.game.stack:pop() end
    if self.onCancel then self.onCancel() end
  end
  self:clampScroll()
end

function Menu:draw()
  local touchBack=TouchTargets.owns(self) and self.cancelable and not self.frozen
  -- jp.58: the touch rows (まえ／つぎ, もどる) sit under the choices. A capped
  -- menu that already fills the 18-tile canvas (the START menu) pushed them
  -- and its bottom border off screen, so it shows fewer rows per page instead.
  if touchBack and self.maxVisible and self.autoHeight then
    local canvasRows=math.floor(require("src.render.Renderer").HEIGHT/8)-self.ty
    local pages=#self.items>self.maxVisible
    local fit=math.floor((canvasRows-2-(pages and 4 or 2))/self.rowStep)
    if not pages and fit<#self.items then
      fit=math.floor((canvasRows-2-4)/self.rowStep)
    end
    if fit>=1 and fit<self.maxVisible then
      self.maxVisible=fit;self.th=fit*self.rowStep+2;self:clampScroll()
    end
  end
  local touchPages=touchBack and self.maxVisible and #self.items>self.maxVisible
  local touchHeight=touchBack and (touchPages and 4 or 2) or 0
  -- opts.anchor opts a menu out of the centred letterbox and onto a screen
  -- edge (the START menu asks for "topright").  Only menus that ask for it
  -- move; every other menu is placed exactly as before.
  local r = self.anchor and self.game and self.game.renderer
  if r and r.setUIAnchor then
    r:setUIAnchor(self.tx * 8, self.ty * 8,
                  self.tw * 8, (self.th+touchHeight) * 8, self.anchor)
  end
  Font.drawBox(self.tx, self.ty, self.tw, self.th+touchHeight)
  if touchBack then
    local x,y,w=(self.tx+1)*8,(self.ty+self.th)*8-4,(self.tw-2)*8
    if touchPages then
      TouchTargets.choice(self,'previous','まえ',function()self.index=math.max(1,self.index-self.maxVisible);self:clampScroll()end,x,y,w/2,16)
      TouchTargets.choice(self,'next','つぎ',function()self.index=math.min(#self.items,self.index+self.maxVisible);self:clampScroll()end,x+w/2,y,w/2,16)
      y=y+16
    end
    TouchTargets.choice(self,"back","もどる","b",x,y,w,16)
  end
  -- PlaceString at hlcoord 3,0 writes over the border row it was just
  -- drawn on (oak_speech2.asm:162-170)
  if self.title then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", (self.tx + 3) * 8, self.ty * 8,
      #Font.split(self.title) * 8, 8)
  end
  love.graphics.setColor(0, 0, 0, 1)
  if self.title then
    Font.draw(self.title, (self.tx + 3) * 8, self.ty * 8)
  end
  local visible = (self.maxVisible and math.min(self.maxVisible, #self.items))
    or #self.items
  -- Row Y: pokered's boxed menus anchor the choices to the BOTTOM interior
  -- row and let any slack fall as a blank row under the top edge --
  -- draw_start_menu.asm (TextBoxBorder 10,0, then hlcoord 12,2 /
  -- wTopMenuItemY 2), players_pc.asm and bills_pc.asm all do the same.  The
  -- bottom border is ty + th - 1, so the last choice sits on ty + th - 2 and
  -- row r counts back up from there.  Anchoring from the top instead only
  -- agrees when th is exactly visible * rowStep + 2, which is Menu.new's
  -- default but NOT what a caller sizing its own box passes: BagMenu's
  -- USE/TOSS is th = 5 for two choices (#284, matching text_boxes.asm's
  -- USE_TOSS_MENU_TEMPLATE rows 10..14), and a top anchor pushed TOSS onto
  -- the bottom border (#564, #572).
  local function rowY(row)
    if self.itemY then
      return (self.ty + self.itemY + (row - 1) * self.rowStep) * 8
    end
    return (self.ty + self.th - 2 - (visible - row) * self.rowStep) * 8
  end
  for row = 1, visible do
    local item = self.items[self.scroll + row]
    if not item then break end
    Font.draw(item.label, (self.tx + 2) * 8, rowY(row))
    if not self.frozen then
      TouchTargets.row(self,'row-'..(self.scroll+row),(self.tx+1)*8,rowY(row)-4,
        (self.tw-2)*8,self.rowStep*8,self.scroll+row,self.items)
    end
  end
  -- hollowIndex: home/window.asm:198
  Font.drawCode(self.hollowIndex == self.index
                and Theme.cursorHollow or Theme.cursor,
    (self.tx + 1) * 8, rowY(self.index - self.scroll))
  -- moreArrow ($EE): the same "more below" glyph OptionRows/ManagerState
  -- use, sat on the bottom border like TextBox's page-advance cursor.  It
  -- has to be the border row, not ty + th - 2: that is the last interior
  -- row, which the last choice now occupies, and Menu.new widens the box to
  -- widest + 3 so tx + tw - 2 is exactly that label's final glyph (#564).
  -- jp.58: with the touch page row (つぎ) under the choices the arrow would
  -- sit on that row's label instead of a border, so it is left out there.
  if self.maxVisible and self.scroll + self.maxVisible < #self.items and not touchPages then
    Font.drawCode(Theme.moreArrow, (self.tx + self.tw - 2) * 8,
      (self.ty + self.th - 1) * 8)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Menu
