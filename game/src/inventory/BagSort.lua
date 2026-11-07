-- Reorder existing bag slots only. Quantities, registered tools, PC items,
-- capacity and item-use behavior remain owned by their original systems.
local Bag=require('src.inventory.Bag')
local Names=require('src.inventory.ItemNames')
local Effects=require('src.inventory.ItemEffects')
local Sort={}

-- Fold hiragana/katakana, small kana and voiced variants to a common base
-- for Japanese names. The secondary spelling orders equal readings without
-- requiring the platform's locale or an Android-only Unicode dependency.
local kana={}
local groups={
  'あぁアァ','いぃイィ','うぅウゥゔヴ','えぇエェ','おぉオォ',
  'かがカガヵ','きぎキギ','くぐクグ','けげケゲヶ','こごコゴ',
  'さざサザ','しじシジ','すずスズ','せぜセゼ','そぞソゾ',
  'ただタダ','ちぢチヂ','つっづツッヅ','てでテデ','とどトド',
  'なナ','にニ','ぬヌ','ねネ','のノ',
  'はばぱハバパ','ひびぴヒビピ','ふぶぷフブプ','へべぺヘベペ','ほぼぽホボポ',
  'まマ','みミ','むム','めメ','もモ','やゃヤャ','ゆゅユュ','よょヨョ',
  'らラ','りリ','るル','れレ','ろロ','わゎワヮ','ゐヰ','ゑヱ','をヲ','んン',
}
local UTF8='[%z\1-\127\194-\244][\128-\191]*'
for rank,chars in ipairs(groups)do
  for ch in chars:gmatch(UTF8)do kana[ch]=('%03d'):format(rank)end
end
local function nameKey(name)
  local key={}
  for ch in tostring(name):gmatch(UTF8)do
    key[#key+1]=kana[ch] or ('z'..ch:lower())
  end
  return table.concat(key,'/')
end
Sort.nameKey=nameKey

local PP={ETHER=true,MAX_ETHER=true,ELIXER=true,MAX_ELIXER=true}
local BATTLE={X_ATTACK=true,X_DEFEND=true,X_SPEED=true,X_SPECIAL=true,
  X_ACCURACY=true,DIRE_HIT=true,GUARD_SPEC=true,POKE_DOLL=true}
local GROWTH={HP_UP=true,PROTEIN=true,IRON=true,CARBOS=true,CALCIUM=true,
  RARE_CANDY=true,PP_UP=true}
local function category(id,def)
  if def.machine or tostring(id):match('^[TH]M_') then return 5 end
  if def.keyItem or def.pocket=='KEY_ITEM' then return 6 end
  if Effects.isBall(id) or def.ball or def.pocket=='BALL' then return 2 end
  if Effects.isBattleMedicine(id) or PP[id] or def.pocket=='MEDICINE' then return 1 end
  if BATTLE[id] then return 3 end
  if GROWTH[id] or Effects.isStone(id) then return 4 end
  return 7
end

function Sort.apply(save,data,mode)
  if mode~='category' and mode~='name' then return false end
  if not(save and type(save.inventory)=='table')then return false end
  local previous={}
  for i,id in ipairs(save.bagOrder or {})do if not previous[id]then previous[id]=i end end
  local order=Bag.order(save,data)
  local rows={}
  for _,id in ipairs(order)do
    if not Bag.isBadge(id)then
      local def=data and data.items and data.items[id] or {}
      local name=tostring(Names.get(data,id))
      local machine=def.machine or {}
      rows[#rows+1]={id=id,group=category(id,def),name=nameKey(name),spelling=name,
        machine=machine.kind=='HM' and 1 or 0,number=tonumber(machine.number) or math.huge,
        position=previous[id] or math.huge}
    end
  end
  table.sort(rows,function(a,b)
    if mode=='category' then
      if a.group~=b.group then return a.group<b.group end
      if a.group==5 then
        if a.machine~=b.machine then return a.machine<b.machine end
        if a.number~=b.number then return a.number<b.number end
      end
    end
    if a.name~=b.name then return a.name<b.name end
    if a.spelling~=b.spelling then return a.spelling<b.spelling end
    if a.position~=b.position then return a.position<b.position end
    return tostring(a.id)<tostring(b.id)
  end)
  -- Keep the table identity used by existing menus and MODs.
  for i=#order,1,-1 do order[i]=nil end
  for i,row in ipairs(rows)do order[i]=row.id end
  return true
end

return Sort
