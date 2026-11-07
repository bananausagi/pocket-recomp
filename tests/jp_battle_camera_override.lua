-- Optional comparison input for the authored real-GL fixture. This is never
-- called by the game. It replaces only numeric encounter rig coefficients.
return function(V)
  local path=os.getenv('JP_QA_CAMERA_RIG')
  if not path or path=='' then return end
  local f=assert(io.open(path,'rb'))
  local rigs=assert(require('src.link.Json').decode(f:read('*a')));f:close()
  local Cam=V.require('BattleCam')
  for _,name in ipairs({'encounter_normal','encounter','encounter_wider','encounter_compact'})do
    local source=assert(rigs[name],name)
    local rig={}
    for _,key in ipairs({'side','back','height','lookX','lookY','frameH'})do
      local n=source[key];assert(type(n)=='number' and n==n and math.abs(n)<math.huge,key)
      rig[key]=n
    end
    Cam.RIGS[name]=rig
  end
end
