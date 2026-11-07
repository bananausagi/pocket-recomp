-- Present bundled option-schema leaves in the shared settings categories.
-- The real MOD owns each value and receives its existing change event.
local M={}
function M.append(game,rows)
  local C=require('src.ui.JapaneseSettingsCatalog')
  local Runtime=require('src.mods.Runtime')
  local loader=game and game.mods
  if not (loader and loader.optionSchemas) then return rows end
  local seen,mapped={},{}
  for _,row in ipairs(rows)do seen[C.canonical(row.id) or row]=true end
  local ids={};for id in pairs(C.bundled)do ids[#ids+1]=id end;table.sort(ids)
  for _,id in ipairs(ids)do
    local present,complete={},true
    for _,definition in ipairs(loader.optionSchemas[id] or {})do
      local key=definition.key
      if C.bundled[id][key] and (definition.type=='toggle' or definition.type=='choice') then
        local name=id..'.'..key
        present[key]=true
        if not seen[name] then
          local function value(g)
            local bucket=g.mods and g.mods.modOptions and g.mods.modOptions[id]
            local v=bucket and bucket[key]
            if v==nil then
              bucket=g.save and g.save.options and g.save.options.modOptions
              v=bucket and bucket[id] and bucket[id][key]
            end
            if v==nil then v=definition.default end
            return v
          end
          local choices=definition.choices or {}
          local function index(g)
            for i,c in ipairs(choices)do if c[2]==value(g)then return i end end
            return 1
          end
          rows[#rows+1]={id=name,label=definition.label or key,
            value=function(g)
              if Runtime.safeMode then return 'へんこう できません' end
              if definition.type=='toggle' then return value(g) and 'オン' or 'オフ' end
              return choices[index(g)] and choices[index(g)][1] or ''
            end,
            step=function(g,dir)
              if Runtime.safeMode or not (g.save and g.save.options) then return false end
              local v
              if definition.type=='toggle' then v=not value(g)
              elseif #choices>0 then v=choices[(index(g)+(dir and dir<0 and -1 or 1)-1)%#choices+1][2]
              else return false end
              local opt=g.save.options
              opt.modOptions=opt.modOptions or {};opt.modOptions[id]=opt.modOptions[id] or {}
              opt.modOptions[id][key]=v
              loader.modOptions=loader.modOptions or {};loader.modOptions[id]=loader.modOptions[id] or {}
              loader.modOptions[id][key]=v
              if g.writeOptions then g:writeOptions() end
              if loader.events then loader.events:emit('mod.options_changed',{mod=id,key=key,value=v}) end
              return true
            end}
          seen[name]=true
        end
      else complete=false end
    end
    for key in pairs(C.bundled[id])do if not present[key]then complete=false end end
    mapped[id]=complete
  end
  -- These openers contain the very same leaves; keep the fallback opener
  -- when its schema is unavailable. Unrelated extensions remain untouched.
  local openers={shiny_pokemon_open='SHINY_POKEMON',controller_rumble_open='CONTROLLER_RUMBLE',
    ['ACCESS_PC_ANYWHERE:open']='ACCESS_PC_ANYWHERE'}
  for i=#rows,1,-1 do if mapped[openers[rows[i].id]] then table.remove(rows,i) end end
  return rows
end
return M
