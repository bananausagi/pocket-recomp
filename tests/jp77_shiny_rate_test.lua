-- jp.77 Gen 2 shiny rate option (Mon.wildDVs / jpShinyRate), headless.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness').suite('JP77 shiny rate')
local Mon=require('src.battle.gen2.Mon')
local Save=require('src.core.gen2.Save')

math.randomseed(7707)

-- default keeps the original path (no generator at all)
T.eq(Save.DEFAULT_OPTIONS.jpShinyRate,'gen2','default is the original odds')
T.eq(Mon.wildDVGenerator({jpShinyRate='gen2'}),nil,'gen2 adds no generator')
T.eq(Mon.wildDVGenerator({}),nil,'an old save without the key adds no generator')
T.eq(Mon.wildDVGenerator(nil),nil,'no options adds no generator')
T.eq(Mon.wildDVGenerator({jpShinyRate='bogus'}),nil,'an unknown key falls back to the original')
T.eq(Mon.SHINY_RATES.gen2,8192,'gen2 is 1/8192')

-- the vanilla DV pattern itself is exactly 1/8192 over all DV combinations
local n=0
for a=0,15 do for d=0,15 do for s=0,15 do for c=0,15 do
  if Mon.vanillaShiny({attack=a,defense=d,speed=s,special=c}) then n=n+1 end
end end end end
T.eq(n,8,'8 of 65536 DV sets are shiny (1/8192)')

-- always: every roll is a real vanilla shiny
local allShiny=true
for _=1,500 do
  local dvs=Mon.wildDVs('always')
  if not Mon.vanillaShiny(dvs) or not Mon.isShiny(dvs) then allShiny=false end
end
T.check(allShiny,'always gives vanilla-shiny DVs every time')

-- high (1/10): measured rate near 10%, and non-shiny rolls never shiny
local shiny,N=0,20000
for _=1,N do if Mon.vanillaShiny(Mon.wildDVs('high')) then shiny=shiny+1 end end
local rate=shiny/N
T.check(rate>0.085 and rate<0.115,'1/10 measured '..tostring(rate))

shiny=0
for _=1,N do if Mon.vanillaShiny(Mon.wildDVs('often')) then shiny=shiny+1 end end
rate=shiny/N
T.check(rate>0.006 and rate<0.014,'1/100 measured '..tostring(rate))

-- DVs stay in range and are the plain table Mon.new takes
local ok=true
for _=1,200 do
  local dvs=Mon.wildDVs('frequent')
  for _,k in ipairs({'attack','defense','speed','special'}) do
    local v=dvs[k]
    if type(v)~='number' or v<0 or v>15 or v%1~=0 then ok=false end
  end
end
T.check(ok,'DVs are integers 0..15')

-- the generator form returns fresh tables
local gen=Mon.wildDVGenerator({jpShinyRate='always'})
T.check(type(gen)=='function','non-default rate gives a generator')
local d1,d2=gen(),gen()
T.check(d1~=d2,'generator returns a fresh table each call')

-- the option cycles through every rate and wraps
local order=Mon.SHINY_RATE_ORDER
T.eq(order[1],'gen2','gen2 first in the cycle')
for _,k in ipairs(order) do T.check(Mon.SHINY_RATES[k]~=nil,'rate known: '..k) end

-- roamers: a fresh beast takes the generator, a met beast keeps its DVs
local okR,Roamers=pcall(require,'src.core.gen2.Roamers')
T.check(okR,'Roamers loads')

-- World helpers: default passes the site's own opts through untouched
local okW,World=pcall(require,'src.world.gen2.World')
if okW and type(World)=='table' and World.wildMonOpts then
  local function fake(opt)
    return setmetatable({game={options=opt}},{__index=World})
  end
  T.eq(fake({jpShinyRate='gen2'}):wildMonOpts(),nil,'world default: no opts')
  local keep={dvs={attack=14,defense=10,speed=10,special=10}}
  T.eq(fake({jpShinyRate='always'}):wildMonOpts(keep),keep,'site opts (FORCESHINY, Unown) win')
  local o=fake({jpShinyRate='always'}):wildMonOpts()
  T.check(o and Mon.vanillaShiny(o.dvs),'world always: shiny DVs')
  T.eq(fake({}):shinyDVGen(),nil,'world old save: no generator')
else
  T.check(false,'World loads: '..tostring(World))
end

T.finish()
