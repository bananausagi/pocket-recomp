-- Explain the existing merged evolution rules; never duplicate or override
-- the 151 MOD's content, force an evolution, or change a saved OFF choice.
local G={}
local trades={KADABRA='ALAKAZAM',HAUNTER='GENGAR',GRAVELER='GOLEM',MACHOKE='MACHAMP'}
function G.text(game,mon)
  local data=game and game.data
  if not (data and data.constants and data.constants.language=='ja'
    and mon and trades[mon.species]) then return nil end
  local def=data.pokemon and data.pokemon[mon.species]
  if not def then return nil end
  for _,e in ipairs(def.evolutions or {})do
    local to=data.pokemon[e.species]
    if e.species==trades[mon.species] and to then
      if e.method=='LEVEL' and type(e.level)=='number' then
        return (def.name or mon.species)..'は\nレベル'..e.level..'いじょうで\nレベルが あがると\f'..
          (to.name or e.species)..'に\nしんかします。\nつうしんは いりません。\f'..
          'ふしぎなアメでも OK。\nとめたときは つぎの\nレベルアップで もういちど。'
      elseif e.method=='TRADE' then
        return (to.name or e.species)..'への\nしんかには\nつうしんこうかんが ひつよう。\f'..
          'ひとりで しんかさせるには\nMODの「151ひき ぜんぶ」を\nONにして よみなおしてね。'
      end
    end
  end
end
function G.addEntry(menu,items,mon)
  if menu.battle or not G.text(menu.game,mon) then return end
  for _,e in ipairs(items)do
    if e.id=='jpEvolutionGuide' or e.action=='evolve' or e.label=='しんか' then return end
  end
  local at=#items+1
  for i,e in ipairs(items)do if e.action=='cancel' then at=i;break end end
  table.insert(items,at,{id='jpEvolutionGuide',label='しんか',onSelect=function(selected,game)
    local text=G.text(game,selected)
    if text then game.stack:push(require('src.render.TextBox').new(game,text))end
  end})
end
return G
