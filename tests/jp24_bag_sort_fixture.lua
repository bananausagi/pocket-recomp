-- Authored, ROM-free bag names and machine records.
return function(data,save)
  local rows={
    {'TOWN_MAP','タウンマップ',1,{keyItem=true}},
    {'TM_THUNDER','TM24',3,{machine={kind='TM',number=24,move='FIX_CUT'}}},
    {'POKE_BALL','モンスターボール',42,{ball='POKE_BALL'}},
    {'BICYCLE','じてんしゃ',1,{keyItem=true}},
    {'HM_CUT','HM01',1,{keyItem=true,machine={kind='HM',number=1,move='FIX_CUT'}}},
    {'POTION','キズぐすり',17,{}},
    {'ANTIDOTE','どくけし',9,{}},
    {'TM_MEGA','TM01',2,{machine={kind='TM',number=1,move='FIX_CUT'}}},
    {'X_ATTACK','プラスパワー',4,{}},
    {'MOON_STONE','つきのいし',5,{}},
    {'MOD_Z','オリジナル',123,{}},
    {'MOD_A','あたらしいどうぐ',7,{}},
    {'DUP_A','おなじ',8,{}},
    {'DUP_B','おなじ',9,{}},
  }
  save.inventory,save.bagOrder={},{}
  for i,row in ipairs(rows)do
    local def=row[4];def.id,def.name,def.index=row[1],row[2],i
    data.items[row[1]]=def;save.inventory[row[1]]=row[3]
    save.bagOrder[i]=row[1]
  end
  save.registeredItem='BICYCLE';save.inventory.FIX_BADGE_1=1
  return rows
end
