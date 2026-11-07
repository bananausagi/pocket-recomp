-- Keep the historical option coefficient: .75 (formerly Compact) is now
-- Normal. Labels are a UI view, never a save-data migration.
local Scale={BASE=0.75,MIN=0.375,MAX=1.5,CHOICES={
  {.375,"とてもちいさい","Very small"},
  {.5,"ちいさい","Small"},
  {.75,"ふつう","Normal"},
  {1,"おおきい","Large"},
  {1.5,"とてもおおきい","Very large"},
}}

function Scale.normalize(value)
  value=tonumber(value)
  if not value or value~=value or math.abs(value)==math.huge then return Scale.BASE end
  return math.max(Scale.MIN,math.min(Scale.MAX,value))
end

function Scale.label(value,english)
  local normalized=Scale.normalize(value)
  local nearest,distance=Scale.CHOICES[1],math.huge
  for _,entry in ipairs(Scale.CHOICES)do
    local gap=math.abs(entry[1]-normalized)
    if gap<distance then nearest,distance=entry,gap end
  end
  return nearest[english and 3 or 2]
end

function Scale.step(value,direction)
  local current=Scale.normalize(value)
  -- Custom imports retain their precise value until the first change, then
  -- take the next offered size in that direction. Endpoints do not wrap.
  if (tonumber(direction) or 1)<0 then
    for i=#Scale.CHOICES,1,-1 do if Scale.CHOICES[i][1]<current-1e-8 then return Scale.CHOICES[i][1] end end
    return Scale.MIN
  end
  for _,entry in ipairs(Scale.CHOICES)do if entry[1]>current+1e-8 then return entry[1] end end
  return Scale.MAX
end

function Scale.windowPixels(base,value)
  base=math.max(0.01,tonumber(base) or 1)
  if base<1 then return base end
  local factor=Scale.normalize(value)
  -- Preserve original full-picture/fractional surfaces passed as factor 1.
  -- Japanese windows supply an integer base and are fit-clamped by Layout.
  if factor==1 then return base end
  return math.max(1,math.floor(base*factor+0.5))
end

function Scale.panelPixels(shortEdge,value)
  -- Exactly the previous .75 baseline, applied before relative scaling so
  -- Normal never changes the established physical glyph size on a device.
  local baseline=math.max(1,math.floor(shortEdge/272+0.5))
  return math.max(1,math.floor(baseline*Scale.normalize(value)/Scale.BASE+0.5))
end

return Scale
