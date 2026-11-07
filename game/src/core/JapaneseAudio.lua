-- Repair Japanese Red caches made with the old $4000-based sound-ID
-- calculation. Only metadata changes; the audio stays in the user's
-- imported ROM bank programs. Run before MOD contributions are applied.
local JapaneseAudio = {}

function JapaneseAudio.seed(data, version)
  if version ~= "red_jp" or not data.constants or data.constants.language ~= "ja" then return end
  local audio = data.audio
  if not audio then return end
  local sfx = audio.sfx or {}
  if not sfx.Trainer_Appeared and sfx.Silph_Scope then
    sfx.Trainer_Appeared = sfx.Silph_Scope
  end
  audio.sfxHeaderBases = audio.sfxHeaderBases or {}
  for engine = 1, 3 do
    local key = tostring(engine)
    local noise = audio.noiseHeaders and audio.noiseHeaders[key]
    local first = noise and noise["1"]
    -- SFX_Noise_Instrument01 is the first three-byte descriptor after
    -- SFX_Headers_N's dummy entry, in all three Japanese engine banks.
    if not audio.sfxHeaderBases[key] and first and type(first.address) == "number" then
      audio.sfxHeaderBases[key] = { bank = first.bank, address = first.address - 3 }
    end
  end
  local base = audio.sfxHeaderBases["2"]
  if not base then return end
  local byId = {}
  for name, def in pairs(sfx) do
    if type(def) == "table" and def.engine == 2 and def.bank == base.bank
        and type(def.address) == "number" then
      local offset = def.address - base.address
      if offset >= 0 and offset % 3 == 0 and offset / 3 <= 255 then
        if not byId[offset / 3] or name == "Trainer_Appeared" then byId[offset / 3] = name end
      end
    end
  end
  for _, move in pairs(data.moves or {}) do
    local anim = type(move) == "table" and move.anim
    local id = anim and type(anim.sound) == "string" and anim.sound:match("^SFX_(%x%x)$")
    if id and not sfx[anim.sound] then
      local name = byId[tonumber(id, 16)]
      if name then anim.sound = name end
    end
  end
end

return JapaneseAudio
