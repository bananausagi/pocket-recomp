-- Japanese Red's trade metadata, for caches made by the npctrade-only parser.
-- SeafarersWind/pokegreen b4db7323bd972b441156f569388dbeb0922664ef,
-- data/events/trades.asm. Dialogue and art still come from the user's ROM.
-- Kana match the JP codec: its shared HE/RI tiles decode as hiragana.
local Trades = {}
local rows = {
  { give="NIDORINO", get="NIDORINA", dialogset=1, nickname="テりー" },
  { give="ABRA", get="MR_MIME", dialogset=1, nickname="バりバり" },
  { give="BUTTERFREE", get="BEEDRILL", dialogset=3, nickname="ピピん" },
  { give="PONYTA", get="SEEL", dialogset=1, nickname="パウーン" },
  { give="SPEAROW", get="FARFETCHD", dialogset=2, nickname="おしょう" },
  { give="SLOWBRO", get="LICKITUNG", dialogset=2, nickname="なめぞう" },
  { give="POLIWHIRL", get="JYNX", dialogset=2, nickname="まさこ" },
  { give="RAICHU", get="ELECTRODE", dialogset=2, nickname="おマル" },
  { give="VENONAT", get="TANGELA", dialogset=3, nickname="りンダ" },
  { give="NIDORAN_F", get="NIDORAN_M", dialogset=3, nickname="チャッピー" },
}

function Trades.seed(data, version)
  if version ~= "red_jp" or not data.constants
      or data.constants.language ~= "ja" or not data.field then return false end
  -- Data seeds before MOD registries merge. Fresh imports and any existing
  -- custom records are authoritative; only the missing/empty old table is repaired.
  if data.field.trades ~= nil and
      (type(data.field.trades) ~= "table" or next(data.field.trades) ~= nil) then return false end
  local restored = {}
  for i, row in ipairs(rows) do
    restored[i] = {}
    for key, value in pairs(row) do restored[i][key] = value end
  end
  data.field.trades = restored
  return true
end

return Trades
