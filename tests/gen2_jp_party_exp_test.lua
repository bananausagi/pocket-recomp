-- jp.74 けいけんちの わけかた (options.jpPartyExp) for Gold / Silver / Crystal.
--
--   luajit tests/gen2_jp_party_exp_test.lua
--
-- ROM-free.  Off (default): the vanilla split.  On: every participant earns
-- a full solo award, every other conscious non-egg party member half of one,
-- EXP.SHARE adds no second pass, a fainted bench mon gets nothing.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 jp party exp")
local eq = S.eq

local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

local DATA = {
  pokemon = {
    growthRates = { GROWTH_SLOW = { numerator = 5, denominator = 4,
      squared = 0, linear = 0, constant = 0 } },
    MACHOP = { id = "MACHOP", index = 66, name = "MACHOP",
      baseStats = { hp = 70, attack = 80, defense = 50, speed = 35,
        specialAttack = 35, specialDefense = 35 },
      types = { "NORMAL", "NORMAL" }, catchRate = 180, baseExp = 75,
      growthRate = "GROWTH_SLOW", genderRatio = 63,
      levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {} },
    PIDGEY = { id = "PIDGEY", index = 16, name = "PIDGEY",
      baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
        specialAttack = 35, specialDefense = 35 },
      types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 55,
      growthRate = "GROWTH_SLOW", genderRatio = 127,
      levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {} },
  },
  moves = { TACKLE = { id = "TACKLE", name = "TACKLE", power = 35,
    type = "NORMAL", accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" } },
  type_chart = { types = { NORMAL = { id = "NORMAL", index = 0,
    category = "physical" } }, matchups = {} },
  items = { EXP_SHARE = { id = "EXP_SHARE", name = "EXP.SHARE",
    heldEffect = "HELD_NONE", heldParameter = 0 } },
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)
local PLAYER_ID = 31337

local function award(on, spec)
  local party, participants = {}, {}
  for index, row in ipairs(spec) do
    local mon = Mon.new(DATA, "MACHOP", 20, { dvs = perfect })
    mon.otId = PLAYER_ID
    mon.item = row.item
    if row.hp then mon.hp = row.hp end
    if row.egg then mon.isEgg = true end
    party[index] = mon
    if row.participant then participants[index] = true end
  end
  local wild = Mon.new(DATA, "PIDGEY", 14, { dvs = perfect })
  local battle = Battle.new({ data = DATA, party = party, wild = wild,
    save = { player = { id = PLAYER_ID, badges = {} } },
    random = function(n) return (n or 1) > 1 and 1 or 0 end,
    jpPartyExp = on })
  battle.participants = participants
  local before = {}
  for i, mon in ipairs(party) do before[i] = mon.experience end
  battle:awardExperience(wild)
  local gained = {}
  for i, mon in ipairs(party) do gained[i] = mon.experience - before[i] end
  return gained
end

-- floor(55 * 14 / 7) = 110 for a solo award.  The half pass halves the base
-- exp up front like the cart's EXP.SHARE pass: floor(27 * 14 / 7) = 54.
local SOLO, HALF = 110, 54

do -- off: vanilla, two participants split, the bench gets nothing
  local g = award(false, { { participant = true }, { participant = true }, {} })
  eq(g[1], 55, "off: two participants split the award")
  eq(g[2], 55, "off: second participant")
  eq(g[3], 0, "off: bench member earns nothing")
end

do -- on: participants full each, bench half, fainted and egg nothing
  local g = award(true, { { participant = true }, { participant = true }, {},
    { hp = 0 }, { egg = true } })
  eq(g[1], SOLO, "on: participant 1 earns a full solo award")
  eq(g[2], SOLO, "on: participant 2 earns a full solo award")
  eq(g[3], HALF, "on: conscious bench member earns half")
  eq(g[4], 0, "on: fainted bench member earns nothing")
  eq(g[5], 0, "on: egg earns nothing")
end

do -- on: EXP.SHARE does not add a second pass
  local g = award(true, { { participant = true }, { item = "EXP_SHARE" } })
  eq(g[1], SOLO, "on: participant with a holder in party still full")
  eq(g[2], HALF, "on: EXP.SHARE holder on the bench gets just the half")
end

S.finish()
