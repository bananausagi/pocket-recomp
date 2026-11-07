-- Retire the jp.37 trial once, without restoring an entire stale options file.
-- Saves, slots, independent effects and user-edited MOD files belong to the user.
local M={OLD='VOXEL_ASCENDANT',NEW='DRAMALESS_SHAPE'}
function M.needed(opts)
  if opts.jpAscendantRetired38 then return false end
  if opts.jpVoxelAscendant37 or (opts.mods or {})[M.OLD]==true then return true end
  for _,bucket in pairs(opts.modsByVersion or {})do
    if bucket[M.OLD]==true then return true end
  end
  for _,p in ipairs(opts.modProfiles or {})do
    if (p.enabled or {})[M.OLD]==true then return true end
    for _,bucket in pairs(p.enabledByVersion or {})do
      if bucket[M.OLD]==true then return true end
    end
  end
  return false
end
local function select(shared,buckets,restoreJP)
  if shared[M.OLD]==true then shared[M.NEW]=true end
  shared[M.OLD]=false
  for _,bucket in pairs(buckets)do
    if bucket[M.OLD]==true then bucket[M.NEW]=true end
    bucket[M.OLD]=false
  end
  if restoreJP then
    buckets.red_jp=buckets.red_jp or {}
    buckets.red_jp[M.OLD],buckets.red_jp[M.NEW]=false,true
  end
end
local function fieldPreferences(options)
  local previous=options[M.OLD]
  if type(previous)~='table' then return end
  local current=options[M.NEW] or {};options[M.NEW]=current
  -- Keep the two useful field preferences, including explicit OFF. The old
  -- battle/camera/device-profile options have no meaning in this renderer.
  if current.clouds==nil and previous.clouds~=nil then
    current.clouds=previous.clouds~='off' and previous.clouds~=false
  end
  if current.weather==nil then
    for _,value in ipairs({'clear','auto','rain','snow','fog','storm'})do
      if previous.weather==value then current.weather=value end
    end
  end
end
function M.apply(opts,defaults)
  if opts.jpAscendantRetired38 then return false end
  local trial=opts.jpVoxelAscendant37==true
  local before=trial and opts.jpRendererBefore37
  opts.mods,opts.modsByVersion=opts.mods or {},opts.modsByVersion or {}
  select(opts.mods,opts.modsByVersion,trial)
  opts.modOptions=opts.modOptions or {};fieldPreferences(opts.modOptions)
  for _,p in ipairs(opts.modProfiles or {})do
    p.enabled,p.enabledByVersion=p.enabled or {},p.enabledByVersion or {}
    select(p.enabled,p.enabledByVersion,trial)
    if p.options then fieldPreferences(p.options)end
  end
  if type(before)=='table' then
    -- Only fields the trial's renderer could force. Shared blur, 3D OFF,
    -- analog input and FX toggles keep the user's current choices.
    for _,key in ipairs({'battleBg','battleLayout','tilt','gbcfx'})do
      opts[key]=before[key]
      if opts[key]==nil then opts[key]=defaults and defaults[key]end
    end
  end
  opts.jpAscendantRetired38=true
  return true
end
return M
