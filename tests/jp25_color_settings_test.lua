-- Run with luajit tests/jp25_color_settings_test.lua (no graphics required).
package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.harness').suite('Japanese color descriptions')
local GameVersion = require('src.core.GameVersion')
local PaletteFX = require('src.render.PaletteFX')
local C = require('src.ui.JapaneseColorSettings')

local beforeVersion, beforeMode, beforeRamp = GameVersion.get(), PaletteFX.mode, PaletteFX.customRamp
local custom = { {255,240,220}, {190,140,80}, {90,60,30}, {10,10,10} }
PaletteFX.customRamp = custom
local seen = {}
for _, mode in ipairs(PaletteFX.MODES) do
  local ja, en = C.label(mode), C.label(mode, true)
  T.check(ja ~= mode and en ~= mode, mode .. ' has a friendly label in both languages')
  T.check(not seen[ja], mode .. ' has a distinct Japanese label')
  seen[ja] = true
  T.check(C.description(mode):find('\n', 1, true) ~= nil, mode .. ' has a two-line explanation')
  T.check(#C.description(mode, true) > 20, mode .. ' has an English explanation')
end
T.eq(PaletteFX.mode, beforeMode, 'reading all choices does not select a mode')
T.eq(PaletteFX.customRamp, custom, 'reading all choices preserves the custom palette')
T.eq(GameVersion.get(), beforeVersion, 'reading labels preserves the running version')

GameVersion.set('red_jp')
T.eq(C.label('ogred'), 'GBC あか', 'Japanese Red describes the Red hardware palette')
T.check(C.description('ogred'):find('みどり', 1, true), 'Red description identifies green people')
T.eq(C.label('ogred', false, 'blue'), 'GBC あお', 'launcher can describe Blue before starting it')
T.check(C.description('ogred', false, 'blue'):find('ピンク', 1, true), 'Blue description identifies pink people')
T.eq(C.label('ogred', true, 'yellow'), 'GBC Yellow', 'Yellow has its own hardware name')
T.check(C.description('ogred', false, 'yellow'):find('ばしょや ポケモン', 1, true), 'Yellow description explains changing palettes')
T.eq(GameVersion.get(), 'red_jp', 'version override is display-only')
GameVersion.set('blue')
T.eq(C.label('ogred'), 'GBC あお', 'current-version labels do not retain stale Red captions')
T.eq(C.label('future_mode'), 'future_mode', 'unknown extensions keep their identity')

-- Check the descriptions against the real mode branches rather than mock
-- mode lists; these are the semantic distinctions presented by the UI.
PaletteFX.customRamp = nil
PaletteFX.mode = 'redpp'
T.check(PaletteFX.usesGbcPack(), 'full color uses terrain and sprite palettes')
PaletteFX.mode = 'redpp_soft'
T.check(PaletteFX.usesGbcPack(), 'soft full color keeps terrain and sprite palettes')
local chromatic = { {255,240,220}, {200,100,50}, {60,100,30}, {0,0,0} }
local softened = PaletteFX.effectiveColors(chromatic)
T.check(softened[2][1] - softened[2][3] < chromatic[2][1] - chromatic[2][3], 'soft mode reduces color spread')
PaletteFX.mode = 'og'
T.eq(PaletteFX.effectiveColors(chromatic), PaletteFX.GRAYS, 'black and white replaces the palette with gray shades')
PaletteFX.mode = 'classic'
T.eq(PaletteFX.effectiveColors(chromatic), PaletteFX.CLASSIC, 'Game Boy green replaces the palette with green shades')
PaletteFX.mode = 'og_inv'
T.eq(PaletteFX.effectiveColors(chromatic)[1], PaletteFX.GRAYS[4], 'inverted black and white turns the lightest shade black')
PaletteFX.mode = 'gbc_inv'
T.eq(PaletteFX.effectiveColors(chromatic)[1], chromatic[4], 'SGB inversion reverses palette order')
PaletteFX.mode = 'redpp'
PaletteFX.customRamp = custom
T.check(not PaletteFX.usesGbcPack(), 'custom palette takes priority over full color')
T.check(C.customDescription():find('ゆうせん', 1, true), 'custom explanation calls out its priority')
T.check(C.customDescription(true):find('priority', 1, true), 'English custom explanation calls out its priority')
T.eq(PaletteFX.customRamp, custom, 'custom explanation preserves the palette')
T.eq(PaletteFX.mode, 'redpp', 'custom explanation preserves the saved mode')
T.eq(C.label(), C.label('redpp'), 'omitted mode describes the active runtime mode')

-- Exercise the actual home/native picker seams, not just the display helper.
love=require('tests.love_stub')
GameVersion.set('red_jp')
local opts={colors='redpp_soft',palette='',jpLauncherLanguage='ja',jpDialogScale=.75}
local Settings=require('src.import.LauncherSettings')
local home=Settings.open({options=opts},'red_jp')
local homeColor
for _,section in ipairs(home.sections)do for _,row in ipairs(section.rows)do
  if row.id=='colors' then homeColor=row end
end end
local game={data={constants={language='ja'}},save={options=opts},stack={pop=function()end}}
local nativeColor
for _,row in ipairs(require('src.ui.OptionsMenu').new(game).rows)do
  if row.id=='colors' then nativeColor=row end
end
local Screen=require('src.ui.PaletteScreen')
for _,mode in ipairs(PaletteFX.MODES)do
  opts.colors=mode
  local screen=Screen.new(game)
  local modeRow
  for _,row in ipairs(screen.rows)do if row.mode==mode then modeRow=row end end
  T.eq(homeColor.value(),C.label(mode),'home has shared mode label '..mode)
  T.eq(nativeColor.value(game),C.label(mode),'native settings has shared mode label '..mode)
  T.eq(modeRow.label,C.label(mode),'picker has shared mode label '..mode)
  T.eq(homeColor.descriptionFor(),C.description(mode),'home has current-mode explanation '..mode)
  T.eq(nativeColor.descriptionFor(game),C.description(mode),'native has current-mode explanation '..mode)
  T.eq(opts.colors,mode,'opening all surfaces preserves saved mode '..mode)
  T.check(screen.floatingPanel and not screen.isOpaque,'Japanese picker floats over field '..mode)
end
local palette=require('src.render.Palette')
local id=palette.categories()[1].palettes[1].id
opts.colors='redpp_soft';opts.palette=id
local customScreen=Screen.new(game)
T.check(customScreen:isGrid(),'stored custom palette opens its existing grid')
T.eq(opts.palette,id,'opening custom grid preserves custom palette')
T.eq(opts.colors,'redpp_soft','opening custom grid does not silently choose SGB')
customScreen:activate(#customScreen:items()+1)
T.eq(opts.colors,'redpp_soft','choosing custom colors keeps independent mode')
T.eq(opts.palette,id,'choosing current custom swatch keeps exact id')
T.eq(homeColor.descriptionFor(),C.customDescription(),'home explains active custom override')
T.eq(nativeColor.descriptionFor(game),C.customDescription(),'game explains active custom override')
customScreen:back()
T.check(customScreen.floatingPanel and not customScreen.isOpaque,'Back returns from grid to floating mode list')
for i,row in ipairs(customScreen.rows)do if row.mode=='classic' then customScreen.index=i end end
customScreen:activate(#customScreen:items()+1)
T.eq(opts.colors,'classic','explicit mode choice applies selected mode')
T.eq(opts.palette,'','explicit mode choice clears custom override so it is visible')
T.eq(PaletteFX.customRamp,nil,'live custom ramp is cleared with the override')
T.eq(PaletteFX.mode,'classic','picker immediately applies chosen runtime mode')

opts.palette='';opts.colors='redpp_soft'
local controller=Screen.new(game)
T.eq(controller.rows[controller.index].mode,'redpp_soft','picker opens with current built-in mode focused')
local pressed
local pops=0
game.input={wasPressed=function(_,key)return key==pressed end}
game.stack.pop=function()pops=pops+1 end
controller.index=1
for i=1,#controller.rows do
  T.eq(controller.index,i,'Down reaches real palette row '..i)
  pressed='down';controller:update()
end
T.eq(opts.colors,'redpp_soft','controller browsing does not change color mode')
T.eq(opts.palette,'','controller browsing does not introduce an override')
pressed='b';controller:update()
T.eq(pops,1,'B leaves palette picker without exiting the game')

local liveGame=require('src.core.Game')
local oldStack=liveGame.stack
PaletteFX.mode='gbc';PaletteFX.customRamp=custom
local neutral={{255,255,255},{170,170,170},{85,85,85},{0,0,0}}
liveGame.stack={states={{isOverworld=true}}}
T.eq(PaletteFX.effectiveColors(neutral),custom,'field uses saved custom colors before opening mode list')
liveGame.stack.states[2]={screenId='PaletteScreen',floatingPanel=true}
T.check(not PaletteFX.pickerActive(),'floating mode list does not activate opaque preview override')
T.eq(PaletteFX.effectiveColors(neutral),custom,'visible field keeps exact custom colors behind mode list')
liveGame.stack.states[2].floatingPanel=false
T.check(PaletteFX.pickerActive(),'opaque custom grid keeps existing swatch preview behavior')
T.eq(PaletteFX.effectiveColors(neutral),neutral,'custom grid preview is not recolored with selected ramp')
liveGame.stack=oldStack

GameVersion.set(beforeVersion)
PaletteFX.mode, PaletteFX.customRamp = beforeMode, beforeRamp
T.finish()
