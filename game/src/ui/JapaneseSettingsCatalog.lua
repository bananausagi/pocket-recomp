-- Display-only organization. Persisted keys, row callbacks and MOD descriptors
-- stay with their existing owners; unknown extension rows remain discoverable.
local C={}
C.groups={
  {id="startup",ja="きどう・ホーム",en="Startup and home",description="きどうする がめん・オープニング",help="Choose home, opening/title or direct Continue at app startup."},
  {id="display",ja="がめん",en="Screen",description="もじの おおきさ・むき・ひょうじの はやさ",help="Text size, orientation and display performance."},
  {id="world",ja="3Dと きょうつうこうか",en="3D and shared effects",description="そとの けしき・かくど・かげ・ぼかし",help="Shared field and battle visuals, colours and effect density."},
  {id="battleEffects",ja="バトルの えんしゅつ",en="Battle effects",description="わざの ひかり・きゅうしょ・まちうごき",help="Independent battle effects. Reduce motion or battle animations OFF pauses them."},
  {id="fieldEffects",ja="フィールドの えんしゅつ",en="Field effects",description="くさ・あしあと・みず・こもれび",help="Independent field effects. Reduce motion pauses them."},
  {id="movement",ja="いどう・してん",en="Movement and camera",description="あるきかた・3Dの みかた",help="Walking mode and camera view."},
  {id="controls",ja="ボタン・キー",en="Buttons and keys",description="わりあて・コントローラーの しんどう",help="Physical button bindings and controller vibration."},
  {id="touch",ja="タッチそうさ",en="Touch controls",description="ボタンの ひょうじ・はいち・スティック",help="Touch buttons, layout and stick appearance."},
  {id="audio",ja="おと",en="Sound",description="おんがくと こうかおんの おおきさ",help="Music and sound-effect volume."},
  {id="game",ja="ゲームの ルール",en="Gameplay",description="はやさ・かいわ・べんりな きのう",help="Game speed, dialogue and battle rules."},
  {id="data",ja="データ",en="Data",description="オートセーブ・せっていの よみこみ",help="Autosave, settings import/export and date/time formats."},
  {id="mods",ja="MODの せってい",en="MOD settings",description="MODの かんり・ついかきのう・リセット",help="MOD management, extension settings and resets."},
}
local owners={}
local function own(group,keys)for key in keys:gmatch("%S+")do owners[key]=group end end
for _,row in ipairs(require('src.core.JapaneseEffects').rows) do owners[row.id]=row.group end
own("startup","jpStartupScreen jpSkipIntro jpLauncherLanguage")
own("display","jpDialogScale jpDotMatrix uiLayout uiLetterbox videoMode orientation faithfulRes screenPos fpsCap vsync logicClock performance jpTopScreen jpTopScreenSize jpTopScreenY jpTopScreenX")
own("world","tilt zoom voidFill jpAtmosphere jpFxDensity colors color palette shaderfx shaderfx2 reduceMotion")
own("battleEffects","jpBattleIntro jpBattleCameraMotion jpBattleSpacing animations battleScene battleLayout battleFit battleHud battleBg")
own("fieldEffects","jpFollower DRAMALESS_SHAPE.sceneryFade")
own("movement","jpAnalogWalk pipeline:voxel pipeline.voxel")
own("controls","controls resetBindings")
own("touch","jpTouchOptimized jpTouchStick touchControls enabled haptics hotbar editTouchAreas editTouchControls openSkinStudio")
own("audio","musicVol sfxVol pikaVol musicFilter")
own("game","jpRulesPreset jpPartyExp jpForgetHM jpReusableTM jpMoveReminder jpRepelRepeat jpFieldActions textSpeed battleStyle ruleset speed speedOverworld speedBattle speedMenu")
own("data","jpAutoSave dateFormat timeFormat jpSettingsFiles importSettings exportSettings")
own("mods","mods")
-- One canonical ID handles launcher dots and in-game colons without
-- changing the option's real persistence key or callback.
function C.canonical(id)
  return type(id)=='string' and id:gsub(':','.') or id
end
function C.visible(id)
  if id~='videoMode' then return true end
  local os=love and love.system and love.system.getOS and love.system.getOS()
  return os~='Android' and os~='iOS'
end
function C.filter(rows)
  local out={};for _,row in ipairs(rows)do if C.visible(row.id)then out[#out+1]=row end end
  return out
end
C.bundled={running_shoes={speed='game',bike='game',surf='game',burn='game',safe='game',fx='fieldEffects'},
  SHINY_POKEMON={enabled='game',shiny_rate='game',recolor='world',sparkles='world',debug_ow='data'},
  CONTROLLER_RUMBLE={enabled='controls',intensity='controls',battle_fx='controls',ambient='controls',story='controls',menus='controls'},
  ACCESS_PC_ANYWHERE={overworld_only='game'}}
function C.group(id)
  if owners[id]then return owners[id]end
  if type(id)=='string'then
    local mod,key=C.canonical(id):match('^([^.]+)%.(.+)$')
    if C.bundled[mod] and C.bundled[mod][key] then return C.bundled[mod][key] end
    if id=='controller_rumble_open' then return 'controls' end
    if id=='shiny_pokemon_open' then return 'game' end
    if mod=='pipeline' then return 'world' end
    if mod=='DRAMALESS_SHAPE' or mod=='VOXEL_ASCENDANT' then
      if key=='battleBack' or key=='voxel_2d_battles' then return 'battleEffects' end
      if key=='weather' or key=='weatherStrength' or key=='weatherLightning' or key=='sceneryFade' then return 'fieldEffects' end
      if key=='INVERT_LOOK_Y' then return 'movement' end
      if key:lower():find('log',1,true)then return 'data'end
      if key=='reset' then return 'mods' end
      return 'world'
    end
  end
  return 'mods'
end
local order={
  startup='jpStartupScreen jpSkipIntro jpLauncherLanguage',
  display='jpDialogScale jpDotMatrix orientation screenPos jpTopScreen jpTopScreenSize jpTopScreenY jpTopScreenX uiLayout faithfulRes uiLetterbox videoMode performance fpsCap vsync logicClock',
  world='pipeline.voxel DRAMALESS_SHAPE.borderDepth voidFill DRAMALESS_SHAPE.buildingHeight jpAtmosphere jpFxDensity reduceMotion colors color palette pipeline.tiltshift DRAMALESS_SHAPE.daytime DRAMALESS_SHAPE.shadowQuality DRAMALESS_SHAPE.water DRAMALESS_SHAPE.terrainHeights DRAMALESS_SHAPE.curve DRAMALESS_SHAPE.grid DRAMALESS_SHAPE.silhouettes DRAMALESS_SHAPE.aa DRAMALESS_SHAPE.renderScale DRAMALESS_SHAPE.renderDistanceSetting tilt zoom SHINY_POKEMON.recolor SHINY_POKEMON.sparkles shaderfx shaderfx2',
  battleEffects='animations battleScene jpBattleIntro jpBattleCameraMotion jpBattleSpacing DRAMALESS_SHAPE.voxel_2d_battles DRAMALESS_SHAPE.battleBack jpFxMoveLight jpFxAfterglow jpFxHitReaction jpFxCritical jpFxIdle jpFxStatus jpFxBattleEnvironment battleLayout battleFit battleHud battleBg',
  fieldEffects='DRAMALESS_SHAPE.sceneryFade DRAMALESS_SHAPE.weather DRAMALESS_SHAPE.weatherStrength DRAMALESS_SHAPE.weatherLightning jpFollower jpFxGrass jpFxFootsteps jpFxTracks running_shoes.fx jpFxWater jpFxWind jpFxAmbient jpFxLightShafts',
  movement='pipeline.voxel jpAnalogWalk DRAMALESS_SHAPE.INVERT_LOOK_Y',
  touch='jpTouchOptimized jpTouchStick editTouchAreas touchControls enabled editTouchControls openSkinStudio haptics hotbar',
  controls='controls CONTROLLER_RUMBLE.enabled CONTROLLER_RUMBLE.intensity CONTROLLER_RUMBLE.battle_fx CONTROLLER_RUMBLE.ambient CONTROLLER_RUMBLE.story CONTROLLER_RUMBLE.menus controller_rumble_open resetBindings',
  audio='musicVol sfxVol pikaVol musicFilter',
  game='textSpeed battleStyle ruleset jpRulesPreset jpPartyExp jpForgetHM jpReusableTM jpMoveReminder jpRepelRepeat jpFieldActions ACCESS_PC_ANYWHERE.overworld_only speed speedOverworld speedBattle speedMenu running_shoes.speed running_shoes.bike running_shoes.surf running_shoes.burn running_shoes.safe SHINY_POKEMON.enabled SHINY_POKEMON.shiny_rate shiny_pokemon_open',
  data='jpAutoSave jpSettingsFiles importSettings exportSettings dateFormat timeFormat DRAMALESS_SHAPE.exportLog SHINY_POKEMON.debug_ow',mods='mods',
}
function C.sort(rows,group)
  local ranks,original={},{}
  local i=0;for key in (order[group] or ''):gmatch('%S+')do i=i+1;ranks[key]=i end
  for n,row in ipairs(rows)do original[row]=n end
  table.sort(rows,function(a,b)
    local ra,rb=ranks[C.canonical(a.id)] or 10000,ranks[C.canonical(b.id)] or 10000
    return ra==rb and original[a]<original[b] or ra<rb
  end)
  return rows
end

C.rows={
  jpDialogScale={"まどと もじの おおきさ","まどと もじを まとめて\n5だんかいで ちょうせいします。"},
  jpDotMatrix={"ドットの あみめ","ゲームがめんに あみめを つけます。\nせっていの もじは かわりません。"},
  colors={"ゲームの いろ","ちけいや ポケモンごとに いろを つけます。\nおだやかは あざやかさを おさえます。"},
  color={"ゲームの いろ","ゲームに つかう いろを えらびます。"},
  uiLetterbox={"がめんの そとの いろ","ゲームが うつらない まわりの\nいろを えらびます。"},
  orientation={"がめんの むき","たて・よこ・じどうの\nむきを えらびます。"},
  screenPos={"ゲームがめんの いち","ゲームを うつす ばしょを\nがめんの なかで かえます。"},
  jpTopScreen={"うえがめんだけ","したはんぶんを かくす コントローラーよう。\nゲームを うえに せいほうけいで だします。"},
  jpTopScreenSize={"うえがめんの おおきさ","うえがめんだけの ときの\nゲームがめんの おおきさです。"},
  jpTopScreenY={"うえがめんの たての いち","うえがめんだけの ときの たての ばしょ。\nいちばん うえは ステータスバーの したです。"},
  jpTopScreenX={"うえがめんの よこの いち","うえがめんだけの ときの よこの ばしょ。\nおおきさが 100%の ときは かわりません。"},
  videoMode={"まどと ぜんがめん","パソコンの まどの ひらきかたです。"},
  faithfulRes={"もとの がめんひりつ","もとの がめんの ひりつを\nたもつか えらびます。"},
  fpsCap={"えがく かいすう","1びょうに えがく かいすうです。\nゲームの すすむ はやさとは べつです。"},
  performance={"ひょうじの かるさ","うごきが おもいときは かるくします。\nいちぶの ひょうじこうかが へります。"},
  vsync={"がめんの ずれを おさえる","がめんの こうしんに あわせて\nえの ずれを おさえます。"},
  logicClock={"うごきの とけい","ゲームを すすめる きじゅんです。\nふだんは じどうの ままで つかえます。"},
  shaderfx={"がめんの こうか 1","いろや にじみなどの\nがめんぜんたいの こうかです。"},
  shaderfx2={"がめんの こうか 2","1つめに かさねる\nがめんぜんたいの こうかです。"},
  tilt={"がめんの かたむき","もとの がめんを ななめにします。\n3Dの ひょうじとは べつの こうかです。"},
  zoom={"ちかく・とおくに みる","ゲームがめんの ひろさを かえます。\nもじの おおきさとは べつです。"},
  voidFill={"そとの ちけい","もとの マップの そとを\nどのように うめるか えらびます。"},
  ["pipeline:voxel"]={"3Dの みかた","ジオラマは ななめ35どの まとめせってい。\nかくどや いちにんしょうも えらべます。"},
  jpAtmosphere={"けしきの ふんいき","ひかりの にじみと とおくの かすみ。\nHD-2D・ひかえめ・もとの ひょうじ。"},
  jpFxDensity={"えんしゅつの りょう","バトルと フィールドの つぶの りょう。\nこべつの オン・オフは かわりません。"},
  ["pipeline:tiltshift"]={"とおくの ぼかし","フィールドと せんとうで つかいます。\nとおくの けしきを ぼかす つよさです。"},
  controls={"キーの わりあて","キーボードと コントローラーの\nボタンの やくわりを かえます。"},
  touchControls={"タッチボタンを だす","がめんの ボタンを みせるか えらびます。\nけしても おなじ ばしょを さわれば うごきます。"},
  enabled={"タッチボタンを だす","がめんの ボタンを みせるか えらびます。\nけしても おなじ ばしょを さわれば うごきます。"},
  editTouchControls={"ボタンの はいち","がめんの ボタンの いちと\nおおきさを かえます。"},
  editTouchAreas={"タッチエリアの はいち","とうめいな もどる・メニューの いちと おおきさを かえます。\nたて・よこ べつに ほぞん。こうもくの タップが ゆうせんです。"},
  openSkinStudio={"タッチの みため","ボタンの えや みためを\nつくる・えらぶ がめんを ひらきます。"},
  haptics={"タッチの しんどう","がめんの ボタンを おしたときの\nしんどうの つよさです。"},
  hotbar={"ショートカットの ボタン","よくつかう そうさの ボタンを\nがめんに だします。"},
  resetBindings={"キーと はいちを もどす","キーの わりあてと タッチの はいちを\nはじめの じょうたいに もどします。"},
  musicVol={"おんがく","ゲームの おんがくの おおきさです。"},
  sfxVol={"こうかおん","ボタン・わざなどの おとの おおきさです。"},
  pikaVol={"ピカチュウの こえ","ピカチュウの こえの おおきさです。"},
  musicFilter={"おとの やわらかさ","おんがくの おとを\nやわらかく する つよさです。"},
  textSpeed={"もじの はやさ","かいわの もじを だす はやさです。"},
  animations={"わざの うごき","せんとうで わざの うごきを\nみせるか えらびます。"},
  battleStyle={"あいてを たおした あと","いれかえを きくか そのまま\nたたかい つづけるか えらびます。"},
  ruleset={"せんとうの ルール","もとの ルールか ちょうせいした\nルールかを えらびます。"},
  jpRulesPreset={"ルールの まとめ","けいけんち・ひでんわざ・わざマシンの\n3つを まとめて きりかえます。"},
  jpPartyExp={"けいけんちの わけかた","さんかした ポケモンは ぜんぶ・ひかえは はんぶん。\nひんしの ポケモンには はいりません。"},
  jpForgetHM={"ひでんわざを わすれる","わざを おぼえるときに ひでんわざも\nえらんで わすれられます。"},
  jpReusableTM={"わざマシンを くりかえす","わざマシンを つかっても\nかずが へらなくなります。"},
  jpMoveReminder={"わざの おもいだし","てもちから レベルで おぼえる わざを えらべます。\nいれかえるとき PPは ふえません。"},
  jpFollower={"ポケモンの つれあるき","てもちの ポケモンが あとを ついてきます。\nつれていく あいては てもちから えらべます。"},
  jpRepelRepeat={"スプレーの つづけてしよう","きれたとき おなじ スプレーを\nもう1つ つかうか かくにんします。"},
  jpFieldActions={"しらべて ひでんわざ","き・みずべ・いわを しらべると ききます。\nひつような バッジと わざは かわりません。"},
  jpAutoSave={"オートセーブ","いまの スロットに じどうで ほぞんします。\nいどうや バトルの あとと やく1ぷんごと。"},
  jpTouchOptimized={"タッチそうさ さいてきか","ジェスチャー / A・Bボタンを えらべます。A・Bでは ひだりが じゆうスティック。\nこうもくは ちょくせつ タップ。ウィンドウの もどるボタンも つかえます。"},
  jpTouchStick={"タッチの スティック","ひょうじゅんそうさの スティックを きりかえます。\nさいてきかモードでは さわった ばしょから ドラッグで いどうします。"},
  jpAnalogWalk={"3Dの じゆういどう","オン: なめらかに あるく。オフ: マスごと。\nいちにんしょう・さんにんしょうも おなじ。"},
  jpBattleIntro={"せんとうの はじまり","あいてを アップで うつします。\nセリフの あとに がめんを ひきます。"},
  jpBattleCameraMotion={"せんとうカメラの うごき","せんとうちゅうに あいてを うつしたり\nゆっくり がめんを まわします。"},
  jpBattleSpacing={"せんとうの かんかく","せんとうで じぶんと あいての\nはなれかたを えらびます。"},
  speedOverworld={"いどうの はやさ","マップでの いどうや うごきの\nすすむ はやさです。"},
  speedBattle={"せんとうの はやさ","せんとうが すすむ はやさです。"},
  speedMenu={"メニューの はやさ","メニューの そうさが すすむ\nはやさです。"},
  jpStartupScreen={"アプリの きどうじ","ホーム / タイトル / つづきから\nアプリを ひらくときの がめんです。"},
  jpSkipIntro={"オープニングを スキップ","タイトルへ すすむときの せってい。\nオフで ゲームフリークから さいせい。"},
  jpLauncherLanguage={"ホームの ことば","ゲームを はじめるまえの\nホームで つかう ことばです。"},
  reduceMotion={"がめんの うごきを へらす","カメラの うごきと ついかした\nバトル・フィールドの えんしゅつを とめます。"},
  mods={"MODを えらぶ","MODの つかう・つかわないを\nえらぶ がめんを ひらきます。"},
  jpSettingsFiles={"せっていファイル","せっていを ファイルに かきだすか\nほぞんした せっていを よみこみます。"},
  exportSettings={"せっていを かきだす","いまの せっていを ファイルにします。\nゲームの レポートとは べつです。"},
  importSettings={"せっていを よみこむ","ファイルの せっていに きりかえます。\nゲームの レポートは かわりません。"},
  dateFormat={"ひづけの かきかた","とし・つき・ひの ならびを えらびます。"},
  timeFormat={"じこくの かきかた","じかんの ひょうじの しかたを えらびます。"},
}
for _,row in ipairs(require('src.core.JapaneseEffects').rows) do C.rows[row.id]={row.ja,row.help} end
C.modRows={
  buildingHeight={"いえの たかさ","ちいさな いえを たかく みせます。\nいりぐちや あるける ばしょは かわりません。"},
  borderDepth={"そとの けしきの ひろさ","きや もりを もっと おくまで えがきます。\nとおくの きは かるい かたちで えがきます。"},
  sceneryFade={"えんけいの フェード","エリアの さかいめで とおくの けしきを\nゆっくり きりかえます。あんてんは しません。"},
  weather={"そとの てんき","はれ・じどう・あめ・ゆき・きり・あらし。\nたてものの なかと せんとうには つけません。"},
  weatherStrength={"てんきの つよさ","あめ・ゆきの りょうと きりの こさを\nひかえめ・ふつう・つよめから えらべます。"},
  weatherLightning={"かみなりの ひかり","あらしの ときに とおくが ひかります。\nオフでも あめは のこります。"},
  terrainHeights={"ちけいの だんさ","マップを つなぐ・マップごと・たいら\nから だんさの つけかたを えらびます。"},
  grid={"ちけいの わく","3Dの ブロックの はしに\nわくを つけます。"},
  curve={"とおくの ちけいの まるみ","とおくの ちけいを したへ\nまるく まげる つよさです。"},
  daytime={"ひると よる","ひる・よる・じこくに あわせた\nあかるさを えらびます。"},
  water={"みずの はんしゃ","みずに そらや ちけいを\nうつすか えらびます。"},
  shadowQuality={"3Dの かげ","フィールドと せんとうの かげを\nまとめて オン・オフに します。"},
  aa={"3Dの はしを なめらかに","3Dの ギザギザを おさえます。\nおもいときは オフに します。"},
  renderScale={"3Dの こまかさ","こまかく えがくほど きれいに\nなりますが うごきが おもくなります。"},
  renderDistanceSetting={"3Dの みえる きょり","とおくまで みせるほど\nうごきが おもくなります。"},
  battleBack={"せんとうの うしろすがた","じぶんの ポケモンの うしろすがたを\nもとの メニューの うえに だします。"},
  silhouettes={"かくれた ひとの すがた","たてものの うしろに いる ひとの\nすがたを すかして みせます。"},
  INVERT_LOOK_Y={"みる むきの じょうげ","いちにんしょうの みる そうさを\nじょうげ ぎゃくに します。"},
  voxel_2d_battles={"3Dの ばしょで せんとう","いまいる 3Dの ばしょを\nせんとうの はいけいに つかいます。"},
  exportLog={"しらべる きろくを かきだす","ふぐあいを しらべる きろくです。\nゲームの レポートとは べつです。"},
  reset={"3Dの せっていを もどす","このMODの せっていを\nはじめの じょうたいに もどします。"},
}
C.bundledRows={
  ['running_shoes.speed']={'Bで はしる はやさ','Bを おしたときの はやさです。\nゲームぜんたいの ばいそくとは べつです。'},
  ['running_shoes.bike']={'Bで じてんしゃを かそく','じてんしゃでも Bを おして\nはやく いどうできます。'},
  ['running_shoes.surf']={'Bで なみのりを かそく','なみのりでも Bを おして\nはやく いどうできます。'},
  ['running_shoes.fx']={'はしるときの えんしゅつ','Bで はしるときの あとを えらびます。\nすな・ほのお・いなずま・にじ。'},
  ['running_shoes.burn']={'はしって くさを やく','くさを けす きのうです。\nくさを ふむ えんしゅつとは べつです。'},
  ['running_shoes.safe']={'はしるとき そうぐうしない','Bで はしっている ときは\nくさむらで ポケモンに そうぐうしません。'},
  ['SHINY_POKEMON.enabled']={'いろちがいを だす','いろちがいの ポケモンが\nでる きのうを きりかえます。'},
  ['SHINY_POKEMON.shiny_rate']={'いろちがいの でやすさ','いろちがいが でる わりあいです。'},
  ['SHINY_POKEMON.recolor']={'いろちがいの いろを つける','フィールドと バトルの\nいろちがいの すがたを かえます。'},
  ['SHINY_POKEMON.sparkles']={'いろちがいの きらめき','とうじょうと つれあるきの きらめき。\nいろちがいの でやすさは かわりません。'},
  ['SHINY_POKEMON.debug_ow']={'いろちがいの しらべるひょうじ','いろの ふぐあいを しらべる ひょうじ。\nふだんは オフです。'},
  ['ACCESS_PC_ANYWHERE.overworld_only']={'どこでもPCを そとだけにする','オン: そとでだけ PCを ひらけます。\nオフ: たてものの なかでも つかえます。'},
  ['CONTROLLER_RUMBLE.enabled']={'コントローラーの しんどう','コントローラーの しんどうを\nまとめて オン・オフにします。'},
  ['CONTROLLER_RUMBLE.intensity']={'パッドの しんどうの つよさ','コントローラーの しんどうを\nよわい・ふつう・つよい・オフから えらべます。'},
  ['CONTROLLER_RUMBLE.battle_fx']={'バトルの しんどう','こうげき・ひだん・ボールなどで\nコントローラーが ふるえます。'},
  ['CONTROLLER_RUMBLE.ambient']={'あしおと・ピンチの しんどう','あしおと・つり・HPが すくないときの\nこまかな しんどうです。'},
  ['CONTROLLER_RUMBLE.story']={'イベントの しんどう','しんか・どうぐ・いわ・ばしょいどう\nなどの しんどうです。'},
  ['CONTROLLER_RUMBLE.menus']={'メニューの しんどう','カーソルと けっていの しんどうです。'},
}
function C.entry(id)
  local key=type(id)=="string"and (id:match("^DRAMALESS_SHAPE[:%.](.+)$")or id:match("^VOXEL_ASCENDANT[:%.](.+)$"))
  return C.rows[id]or C.bundledRows[C.canonical(id)]or(key and C.modRows[key])
end
function C.info(row)
  local entry=C.entry(row.id)
  return entry and entry[1]or row.label,entry and entry[2]or row.description or row.help
end
function C.value(id,value)
  local key=C.canonical(id)
  local values={
    ['DRAMALESS_SHAPE.weather']={CLEAR='はれ',AUTO='じどう',RAIN='あめ',SNOW='ゆき',FOG='きり',STORM='あらし'},
    ['DRAMALESS_SHAPE.weatherStrength']={GENTLE='ひかえめ',NORMAL='ふつう',STRONG='つよめ'},
    ['DRAMALESS_SHAPE.buildingHeight']={ORIGINAL='もとの たかさ',TALL='たかめ'},
    ['DRAMALESS_SHAPE.borderDepth']={COMPACT='せまい',DEEP='ふつう',WIDE='ひろい'},
  }
  return values[key] and values[key][value] or value
end
return C
