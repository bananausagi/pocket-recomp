-- Color mode persistence and chromatic profile checks. No ROM required.
package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local S = require('tests.harness').suite('jp22 colors')
local P = require('src.render.PaletteFX')
local Palette = require('src.render.Palette')
local Screen = require('src.ui.PaletteScreen')
local Version = require('src.core.GameVersion')
local Json = require('src.link.Json')
local Settings = require('src.import.LauncherSettings')
local function spread(c) return math.max(unpack(c)) - math.min(unpack(c)) end

for _, version in ipairs({'red_jp','red','blue','yellow'}) do
  Version.set(version)
  for _, mode in ipairs(P.MODES) do
    local writes = 0
    local game = { save={options={colors=mode,palette=''}}, stack={states={},pop=function()end},
      writeOptions=function() writes=writes+1 end }
    P.applyOptions(game.save.options)
    local screen = Screen.new(game)
    S.eq(P.mode, mode, version .. ' open preserves live ' .. mode)
    S.eq(game.save.options.colors, mode, 'opening leaves saved mode intact')
    screen:close()
    S.eq(writes, 0, 'open/cancel writes no options')
    screen.set('m:4080c0')
    S.eq(game.save.options.colors, mode, 'custom ramp keeps base mode')
    S.check(not P.usesGbcPack() and not P.usesSpriteObp(), 'custom ramp suppresses conflicting bakes')
    S.same(P.effectiveColors(P.GRAYS),Palette.ramp('m:4080c0'),'custom palette overrides soft/OG profiles exactly')
    screen.set('')
    S.eq(P.mode, mode, 'clear custom restores unchanged base mode')
    screen.setMode('redpp_soft')
    local restored = Json.decode(Json.encode(game.save.options))
    P.applyOptions(restored)
    S.eq(P.mode,'redpp_soft','serialized options restore gentle mode')
    S.check(P.usesGbcPack(),'gentle mode retains true per-tile color')
  end
end

Version.set('red_jp'); P.setCustomRamp(nil); P.setMode('redpp')
local raw = P.gbcPack().palettes.GREENBAR
S.eq(P.pal(nil,'GREENBAR'),raw,'existing vivid mode returns exact original palette')
P.setMode('redpp_soft')
local soft = P.pal(nil,'GREENBAR')
S.check(spread(soft[3]) < spread(raw[3]),'HP green chroma reduced')
S.check(soft[3][2] > soft[3][1] and soft[3][2] > soft[3][3],'HP green stays green')
S.same(P.displayColors(P.GRAYS),P.GRAYS,'white black and neutral text shades unchanged')
S.eq(P.effectiveColors(soft),soft,'shader palette does not soften already transformed colors twice')
local swapped=P.permute(soft,{[0]=3,[1]=1,[2]=2,[3]=0})
S.eq(P.effectiveColors(swapped),swapped,'shade-map permutation retains idempotent colors')
P.setDarkWorld(true)
local dark=P.worldGroupColors({},'OVERWORLD','PALLET_TOWN')
S.same(dark[1][1],P.displayColors(P.worldPack().groupColors.OVERWORLD[1])[3],'dark cave shade maps remain applied')
P.setDarkWorld(false)
local ordinary=P.worldPack().groupColors.OVERWORLD
local muted=P.worldGroupColors({},'OVERWORLD','PALLET_TOWN')
local softened=0
for i,group in ipairs(ordinary) do for j,c in ipairs(group) do
  if spread(c)>0 then S.check(spread(muted[i][j])<spread(c),'world group chroma reduced');softened=softened+1 end
end end
S.check(softened>4,'multiple terrain palette groups actually transformed')
for _,mode in ipairs({'redpp','redpp_soft','ogred'}) do
  local options={colors=mode,palette='m:4080c0'}
  local model=Settings.open({options=options,save=function()return true end},'red_jp')
  local row
  for _,section in ipairs(model.sections) do for _,r in ipairs(section.rows) do if r.id=='colors' then row=r end end end
  S.eq(options.colors,mode,'launcher opening preserves choice')
  S.eq(row.value(),'カスタム','launcher identifies custom override')
  row.step(1)
  S.eq(options.palette,'','launcher explicit mode selection removes custom override')
  S.check(model.save(),'launcher saves selected mode')
  P.applyOptions(options)
  S.eq(P.mode,options.colors,'launcher choice is accepted at runtime')
end
S.finish()
