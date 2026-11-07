-- Shared Japanese Gen 1 preferences for the launcher and in-game settings.
local Rules = require("src.core.JapaneseRules")
local S = {}
-- 1% step choice lists for the top-screen rows: from..to by step, with
-- named labels kept at the ends and the middle.
local function percents(from,to,step,names)
  local list={}
  for v=from,to,step do
    local name=names and names[v]
    list[#list+1]=name and {v,name[1],name[2]} or {v,v.."%",v.."%"}
  end
  return list
end
S.rows = {
  {id="jpRulesPreset",ja="ルールの まとめ",en="Convenience preset",preset=true},
  {id="jpPartyExp",ja="けいけんちの わけかた",en="Experience sharing",default=false,
    choices={{false,"げんさくどおり","Original"},{true,"てもち ぜんいん","Whole party"}}},
  {id="jpForgetHM",ja="ひでんわざを わすれる",en="Forget HM moves",default=false},
  {id="jpReusableTM",ja="わざマシンを くりかえす",en="Reusable TMs",default=false},
  {id="jpMoveReminder",ja="わざの おもいだし",en="Move reminder",default=false},
  {id="jpFollower",ja="ポケモンの つれあるき",en="Following Pokemon",default=true},
  {id="jpRepelRepeat",ja="スプレーの つづけてしよう",en="Repeat repel prompt",default=true},
  {id="jpSkipIntro",ja="オープニングを スキップ",en="Skip opening movie",default=false},
  {id="jpStartupScreen",ja="アプリの きどうじ",en="App startup",default="home",
    choices={{"home","ホームを ひらく","Show home"},{"title","タイトルへ","Opening / title"},{"continue","つづきから すぐに","Resume directly"}}},
  {id="jpFieldActions",ja="しらべて ひでんわざ",en="Inspect to use field moves",default=true},
  {id="jpAutoSave",ja="オートセーブ",en="Autosave",default=true},
  {id="jpTouchStick",ja="タッチの スティック",en="Touch joystick",default=true},
  {id="jpTouchOptimized",ja="タッチそうさ さいてきか",en="Touch optimized mode",default=false,
    choices={{false,"オフ","Off"},{true,"ボタンなし","No buttons"},{"buttons","A・Bボタン","A/B buttons"}}},
  {id="jpAnalogWalk",ja="3Dの じゆういどう",en="Free movement in 3D",default=false},
  {id="jpAtmosphere",ja="けしきの ふんいき",en="Scenery atmosphere",default="soft",
    choices={{"soft","HD-2D","HD-2D"},{"gentle","ひかえめ","Gentle"},{"off","もとの ひょうじ","Original"}}},
  {id="jpFxDensity",ja="えんしゅつの りょう",en="Effect density",default="normal",
    choices={{"low","すくない","Low"},{"normal","ふつう","Normal"},{"high","おおい","High"}}},
  {id="jpBattleIntro",ja="せんとうの はじまり",en="Battle opening",default="focus",
    choices={{"focus","3D","3D entrance"},{"original","げんさく","Original"}}},
  {id="jpBattleCameraMotion",ja="せんとうカメラの うごき",en="Battle camera motion",default=true},
  -- Top-screen-only display (clip-on pads that cover the lower half).
  {id="jpTopScreen",ja="うえがめんだけ",en="Top screen only",default="off",
    choices={{"off","オフ","Off"},{"square","せいほうけい","Square"},{"gb","ゲームボーイの ひりつ","Game Boy ratio"}}},
  {id="jpTopScreenSize",ja="うえがめんの おおきさ",en="Top screen size",default=100,
    choices=percents(100,50,-1)},
  {id="jpTopScreenY",ja="うえがめんの たての いち",en="Top screen vertical",default=0,
    choices=percents(0,100,1,{[0]={"いちばん うえ","Top"},[50]={"まんなか","Middle"},[100]={"いちばん した","Bottom"}})},
  {id="jpTopScreenX",ja="うえがめんの よこの いち",en="Top screen horizontal",default=50,
    choices=percents(0,100,1,{[0]={"ひだり","Left"},[50]={"まんなか","Center"},[100]={"みぎ","Right"}})},
}
for _,row in ipairs(require('src.core.JapaneseEffects').rows) do S.rows[#S.rows+1]=row end
local switches={{false,"オフ","Off"},{true,"オン","On"}}
local presets={classic={"げんさく","Original"},convenient={"べんり","Convenient"},custom={"こまかく","Custom"}}
local function index(row,options)
  local value=options[row.id]
  if value==nil then value=row.default end
  for i,item in ipairs(row.choices or switches)do if item[1]==value then return i end end
  return 1
end
function S.value(row,options,english)
  if row.preset then return presets[Rules.preset(options)][english and 2 or 1]end
  return (row.choices or switches)[index(row,options)][english and 3 or 2]
end
function S.step(row,options,direction)
  if row.preset then
    local current=Rules.preset(options)
    local nextPreset=current=="classic" and "convenient" or "classic"
    if current=="custom" and (direction or 1)>0 then nextPreset="convenient" end
    return Rules.applyPreset(options,nextPreset)
  end
  local candidates=row.choices or switches
  local nextIndex=(index(row,options)+(direction and direction<0 and -1 or 1)-1)%#candidates+1
  options[row.id]=candidates[nextIndex][1]
  return true
end
return S
