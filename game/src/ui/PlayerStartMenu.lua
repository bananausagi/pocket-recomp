-- SPDX-License-Identifier: GPL-3.0-only
-- Original fork start menu. Uses the player's loaded text font, no title art.
local Font = require("src.render.Font")
local Menu = require("src.ui.Menu")
local Strings = require("src.core.Strings")
local SaveData = require("src.core.SaveData")
local Runtime = require("src.mods.Runtime")
local Start = { isOpaque = true, isPlayerStartMenu = true, screenId = "TitleState",
  centerInPlayfield = true }
Start.__index = Start

-- This page owns its palette; inheriting the title's separate logo/sprite
-- regions colored arbitrary menu rows and left a black band through text.
function Start:sgbPalettes(game)
  local P=require("src.render.PaletteFX")
  return {P.whole(P.pal(game.data,"GREENBAR") or P.GRAYS)}
end

function Start.new(game, callbacks)
  local self = setmetatable({ game = game, callbacks = callbacks or {} }, Start)
  self:mainMenu()
  return self
end

function Start:home()
  if self.callbacks.onExit then return self.callbacks.onExit() end
  if self.game.returnToLauncher then return self.game.returnToLauncher() end
end

function Start:back()
  if self.callbacks.onBack then return self.callbacks.onBack() end
  return self:home()
end

function Start:startNew()
  if self.callbacks.onNewGame then
    local accepted,err=self.callbacks.onNewGame()
    if accepted==false then
      self:mainMenu()
      self.notice=err or "レポートを よういできません"
    end
  end
end

function Start:mainMenu()
  local game, items = self.game, {}
  local ok, saved, recovered = pcall(SaveData.load)
  self.hasSave = ok and type(saved) == "table"
  -- Reuse this existing read for presentation-only precaching. The warmup
  -- never loads/adopts a save, promotes a backup, or fires save/world hooks.
  self.presentationWarmup = self.hasSave and saved.player and {
    map=saved.player.map,lastOutdoor=saved.lastOutdoor and saved.lastOutdoor.id,
  } or nil
  -- Probing a backup can promote it to the main save. Preserve that recovery
  -- reason until Continue, whose fresh load then sees a healthy main file.
  self.recovered = self.recovered or (self.hasSave and recovered or nil)
  if self.hasSave then
    items[#items + 1] = { label = Strings("CONTINUE"), keepOpen = true,
      onSelect = function()
        if self.callbacks.onContinue then
          local accepted = self.callbacks.onContinue(self.recovered)
          if accepted == false then self.notice = "レポートを よめませんでした" end
        end
      end }
  end
  items[#items + 1] = { label = Strings("NEW GAME"), keepOpen = true,
    onSelect = function()
      if self.hasSave then self:confirmNew()
      else self:startNew() end
    end }
  items[#items + 1] = { label = "せってい", keepOpen = true,
    onSelect = function()
      if game.openSessionMenu then game:openSessionMenu("settings")
      else require("src.ui.Screens").push(game, "OptionsMenu") end
    end }
  items[#items + 1] = { label = "ホームに もどる", keepOpen = true,
    onSelect = function() self:home() end }
  local hooked = Runtime.call("ui.title_menu.items", function(_, rows) return rows end, game, items)
  if type(hooked) == "table" and #hooked > 0 then items = hooked end
  self.confirming, self.notice = false, nil
  self.menu = Menu.new(game, items, { tx = 1, ty = 4, tw = 18, th = 10,
    maxVisible = 4, keepOnCancel = true, onCancel = function() self:back() end })
end

function Start:confirmNew()
  self.confirming = true
  self.menu = Menu.new(self.game, {
    { label = "もどる", keepOpen = true, onSelect = function() self:mainMenu() end },
    { label = "はじめから あそぶ", keepOpen = true, onSelect = function()
      self:startNew()
    end },
  }, { tx = 1, ty = 9, tw = 18, th = 6, keepOnCancel = true,
    onCancel = function() self:mainMenu() end })
end

function Start:update(dt) self.menu:update(dt) end

function Start:draw()
  local g = love.graphics
  g.setColor(1, 1, 1, 1); g.rectangle("fill", 0, 0, 160, 144)
  g.setColor(0, 0, 0, 1)
  Font.draw(require("src.core.Version").appName, 20, 12)
  if self.confirming then
    Font.draw("まえの レポートは のこして", 8, 32)
    Font.draw("あたらしい ぼうけんを", 8, 48)
    Font.draw("はじめますか？", 8, 64)
  end
  self.menu:draw()
  g.setColor(0, 0, 0, 1)
  local hint=require('src.core.JapaneseTouchMode').configured(self.game)
    and "タップで けってい" or "A:けってい  B:もどる"
  Font.draw(self.notice or hint, 8, 128)
  g.setColor(1, 1, 1, 1)
end

return Start
