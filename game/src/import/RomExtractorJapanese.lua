-- Japanese Red import layout. All game strings and artwork come from the
-- supplied, hash-verified ROM; this module contains only format rules.
local Japanese = {}

function Japanese.attach(extractor)
  extractor.jpDexTexts = {}
  local baseRaw2bpp = extractor.raw2bpp
  extractor.raw2bpp = function(self, label, width, height, path, opts)
    if label ~= "NintendoCopyrightLogoGraphics" and label ~= "GameFreakLogoGraphics" then
      return baseRaw2bpp(self, label, width, height, path, opts)
    end
    local ImageWriter = require("src.import.ImageWriter")
    local symbol = self:symbol(label)
    local atlas = ImageWriter.decode2bpp(self.rom:bytes(symbol.bank, symbol.address, 25 * 16), 200, 8)
    local image = ImageWriter.blank(width, height, 1, 1, 1, 1)
    local indices = label == "NintendoCopyrightLogoGraphics"
      and { 0, 1, 2, 3, 13, 14, 15, 16, 17, 18 }
      or { 4, 5, 6, 7, 8, 9, 10, 11, 12 }
    local left = math.floor((width - #indices * 8) / 2)
    for i, tile in ipairs(indices) do
      ImageWriter.blit(image, atlas, left + (i - 1) * 8, 0, tile * 8, 0, 8, 8)
    end
    self:save(image, path)
    return image
  end
  extractor.decodeTextCommands = function(self, symbol, substitutions)
    local address, pending, out = symbol.address, 1, {}
    local limit = symbol.address + assert(self.manifest.text.lengths[symbol.name],
      "missing Japanese text boundary: " .. symbol.name)
    local function byte()
      assert(address < limit, symbol.name .. ": truncated text command")
      local value = self.rom:byte(symbol.bank, address)
      address = address + 1
      return value
    end
    local function finish(marker)
      assert(pending > #substitutions, symbol.name .. ": unused text substitutions")
      if marker and #out > 0 then out[#out + 1] = marker end
      return table.concat(out)
    end
    while address < limit do
      local command = byte()
      if command == 0x50 then return finish("{DONE}")
      elseif command == 0 then
        while true do
          local value = byte()
          if value == 0x50 then break end
          if value == 0x57 or value == 0x58 or value == 0x5F then
            return finish(value == 0x58 and "{PROMPT}" or "{DONE}")
          end
          out[#out + 1] = self:textGlyph(value)
        end
      elseif command == 1 or command == 2 or command == 9 then
        local expected = substitutions[pending]
        assert(expected and expected[1] == command,
          symbol.name .. ": missing or mismatched text substitution")
        out[#out + 1] = expected[2]
        pending = pending + 1
        byte(); byte()
        if command ~= 1 then byte() end
      elseif command == 8 then
        -- Inline Japanese text returns to machine code here. The native
        -- script runner implements those effects, so never decode code.
        assert(#out > 0, symbol.name .. ": points to executable script, not text")
        return finish()
      elseif command == 3 then byte(); byte()
      elseif command == 4 then byte(); byte(); byte(); byte()
      elseif command == 7 then out[#out + 1] = "\v"
      elseif command == 12 then out[#out + 1] = string.rep("…", byte())
      elseif command == 5 or command == 6 or command == 10 or command == 11
          or (command >= 13 and command <= 22) then
        -- Presentation-only commands; dialogue waits and sound playback
        -- are owned by the native script rather than ROM CPU execution.
      else
        error(("%s: unsupported Japanese text command $%02X"):format(symbol.name, command))
      end
    end
    return finish()
  end
  local baseFont = extractor.extractFont
  extractor.extractFont = function(self)
    local font = baseFont(self)
    font.composites = self.manifest.fontComposites
    font.language = "ja"
    local tiles = {}
    for _, entry in ipairs(font.charmap) do tiles[#tiles + 1] = entry.seq end
    font.ttf = { size = 15, tiles = tiles }
    self:write("font", font)
    return font
  end

  extractor.dexEntry = function(self, index, species)
    local tableSymbol = self:symbol("PokedexEntryPointers")
    local address = self.rom:word(tableSymbol.bank, tableSymbol.address + (index - 1) * 2)
    local kind, length = self.rom:readString(tableSymbol.bank, address,
      self.manifest.charmap, 0x50, 32)
    address = address + length
    local heightDm = self.rom:byte(tableSymbol.bank, address)
    local weightHg = self.rom:word(tableSymbol.bank, address + 1)
    local text = self.rom:readString(tableSymbol.bank, address + 3,
      self.manifest.charmap, 0x50, 1024)
    local label = self.manifest.dexEntryLabels[species] or ("_JapaneseDex_" .. species)
    self.jpDexTexts[label] = text
    local inches = math.floor(heightDm / 0.254 + 0.5)
    return { kind = kind, heightM = heightDm / 10, weightKg = weightHg / 10,
      heightFt = math.floor(inches / 12), heightIn = inches % 12,
      weight = weightHg * 2.2046226218, text = label, metric = true }
  end

  local baseField = extractor.extractField
  extractor.extractField = function(self)
    local result = baseField(self)
    local presets = {}
    for key, label in pairs({ player = "DefaultNamesPlayerList", rival = "DefaultNamesRivalList" }) do
      local symbol = self:symbol(label)
      local address = symbol.address
      presets[key] = {}
      for i = 0, 3 do
        local name, length = self.rom:readString(symbol.bank, address,
          self.manifest.charmap, 0x50, 32)
        address = address + length
        if i == 0 then presets.customOption = name
        else presets[key][i] = name end
      end
    end
    result.presetNames = presets
    self:write("field", result)
    return result
  end

  local baseTypes = extractor.extractTypeChart
  extractor.extractTypeChart = function(self)
    local result = baseTypes(self)
    result.typeNames = {}
    for _, label in ipairs(self.manifest.typeNameLabels) do
      local id = label:match("%.(.+)$"):upper()
      if id == "PSYCHIC" then id = "PSYCHIC_TYPE" end
      local symbol = self:symbol(label)
      result.typeNames[id] = self.rom:readString(symbol.bank, symbol.address,
        self.manifest.charmap, 0x50, 16)
    end
    self:write("type_chart", result)
    return result
  end

  local baseText = extractor.extractText
  extractor.extractText = function(self)
    local result = baseText(self)
    for label, value in pairs(self.jpDexTexts) do result.texts[label] = value end
    require("src.core.JapaneseText").normalize(result.texts)
    -- These US split fragments are already included in the preceding
    -- Japanese receive-item message, before its terminating command.
    for _, label in ipairs({ "_CopycatsHouse2FCopycatTM31Explanation1Text",
      "_ViridianGymGiovanniTM27ExplanationText",
      "_WardensHouseWardenTeethPoppedInHisTeethText" }) do
      result.texts[label] = ""
    end
    self:write("text", result.texts)
    return result
  end
end

return Japanese
