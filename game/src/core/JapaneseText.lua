-- English scripts call two labels where Japanese Red stores one text stream.
-- Split only these verified aliases, at the line/page boundary immediately
-- after the stream's sound command. No dialogue bytes or translated strings
-- are bundled. See docs/japanese-dialogue.md for provenance and limitations.
local JapaneseText = {}

JapaneseText.segments = {
  -- CardKeySuccessText: sound_get_item_1
  { "_CardKeySuccessText1",
    "_CardKeySuccessText2", "\n", 1 },
  -- CeladonGymReceivedTM21Text: sound_get_item_1
  { "_CeladonGymReceivedTM21Text",
    "_TM21ExplanationText", "\f", 1 },
  -- CeladonMartRoofLittleGirlReceivedTM13Text: sound_get_item_1
  { "_CeladonMartRoofLittleGirlReceivedTM13Text",
    "_CeladonMartRoofLittleGirlTM13ExplanationText", "\f", 1 },
  -- CeladonMartRoofLittleGirlReceivedTM48Text: sound_get_item_1
  { "_CeladonMartRoofLittleGirlReceivedTM48Text",
    "_CeladonMartRoofLittleGirlTM48ExplanationText", "\f", 1 },
  -- CeladonMartRoofLittleGirlReceivedTM49Text: sound_get_item_1
  { "_CeladonMartRoofLittleGirlReceivedTM49Text",
    "_CeladonMartRoofLittleGirlTM49ExplanationText", "\f", 1 },
  -- CeruleanCityRocketText.ReceivedTM28Text: sound_get_item_1
  { "_CeruleanCityRocketReceivedTM28Text",
    "_CeruleanCityRocketIBetterGetMovingText", "\f", 1 },
  -- CinnabarGymBlaineReceivedTM38Text: sound_get_item_1
  { "_CinnabarGymBlaineReceivedTM38Text",
    "_CinnabarGymBlaineTM38ExplanationText", "\f", 1 },
  -- FuchsiaGymKogaReceivedTM06Text: sound_get_key_item
  { "_FuchsiaGymKogaReceivedTM06Text",
    "_FuchsiaGymKogaTM06ExplanationText", "\f", 1 },
  -- MrFujisHouseMrFujiText.ReceivedPokeFluteText: sound_get_key_item
  { "_MrFujisHouseMrFujiReceivedPokeFluteText",
    "_MrFujisHouseMrFujiPokeFluteExplanationText", "\f", 1 },
  -- OakSpeechText2: sound_cry_nidorina
  { "_OakSpeechText2A",
    "_OakSpeechText2B", "\f", 2 },
  -- OaksLabOak1Text.GivePokeballsText: sound_get_key_item
  { "_OaksLabOak1ReceivedPokeballsText",
    "_OaksLabGivePokeballsExplanationText", "\f", 3 },
  -- OaksLabOak1Text.DeliverParcelText: sound_get_key_item
  { "_OaksLabOak1DeliverParcelText",
    "_OaksLabOak1ParcelThanksText", "\f", 6 },
  -- PewterGymBrockReceivedBoulderBadgeText: sound_level_up
  { "_PewterGymBrockReceivedBoulderBadgeText",
    "_PewterGymBrockBoulderBadgeInfoText", "\f", 3 },
  -- PewterGymReceivedTM34Text: sound_get_item_1
  { "_PewterGymReceivedTM34Text",
    "_TM34ExplanationText", "\f", 1 },
  -- PokemonFanClubChairmanText.BikeVoucherText: sound_get_key_item
  { "_PokemonFanClubReceivedBikeVoucherText",
    "_PokemonFanClubExplainBikeVoucherText", "\f", 1 },
  -- Route12SuperRodHouseFishingGuruText.ReceivedSuperRodText: sound_get_item_1
  { "_Route12SuperRodHouseFishingGuruReceivedSuperRodText",
    "_Route12SuperRodHouseFishingGuruFishingWayOfLifeText", "\f", 3 },
  -- Route24CooltrainerM1Text.YouBeatOurContestText: sound_get_item_1
  { "_Route24CooltrainerM1YouBeatOurContestText",
    "_Route24CooltrainerM1YouJustEarnedAPrizeText", "\f", 1 },
  -- SafariZoneGateSafariZoneWorker1WouldYouLikeToJoinText.MakePaymentText: sound_get_item_1
  { "_SafariZoneGateSafariZoneWorker1ThatllBe500PleaseText",
    "_SafariZoneGateSafariZoneWorker1CallYouOnThePAText", "\f", 3 },
  -- SaffronGateGuardGiveDrinkText: sound_get_key_item
  { "_SaffronGateGuardImParchedText",
    "_SaffronGateGuardYouCanGoOnThroughText", "\f", 1 },
  -- SaffronGymSabrinaReceivedTM46Text: sound_get_item_1
  { "_SaffronGymSabrinaReceivedTM46Text",
    "_TM46ExplanationText", "\f", 1 },
  -- VermilionGymLTSurgeReceivedTM24Text: sound_get_key_item
  { "_VermilionGymLTSurgeReceivedTM24Text",
    "_TM24ExplanationText", "\f", 1 },
  -- VermilionOldRodHouseFishingGuruText.TakeThisText: sound_get_item_1
  { "_VermilionOldRodHouseFishingGuruTakeThisText",
    "_VermilionOldRodHouseFishingGuruFishingIsAWayOfLifeText", "\f", 3 },
}

function JapaneseText.normalize(texts)
  if type(texts) ~= "table" then return 0 end
  local changed = 0
  for _, rule in ipairs(JapaneseText.segments) do
    local first, second, delimiter, ordinal = unpack(rule)
    local full = texts[first]
    -- Imported caches from older builds contain the exact same full stream
    -- under both labels. Distinct translations/custom datasets stay intact.
    if type(full) == "string" and full ~= "" and full == texts[second] then
      local at, from
      from = 1
      for _ = 1, ordinal do
        at = full:find(delimiter, from, true)
        if not at then break end
        from = at + #delimiter
      end
      if at and at > 1 and at < #full then
        -- Preserve the boundary on the second fragment: callers may join
        -- them with a sound pause, or display each fragment in its own box.
        -- The first fragment gets its own terminator; the final fragment
        -- keeps the original DONE/PROMPT marker and all RAM/NUM tokens.
        texts[first] = full:sub(1, at - 1) .. "{DONE}"
        texts[second] = full:sub(at)
        changed = changed + 1
      end
    end
  end
  return changed
end

function JapaneseText.seed(data, version)
  if version ~= "red_jp" or not data.constants
      or data.constants.language ~= "ja" then return 0 end
  return JapaneseText.normalize(data.text)
end

return JapaneseText
