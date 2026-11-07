-- One preference definition for persistence, launcher and in-game menus.
-- Presentation only: never consumes game RNG, changes a queue or waits.
local E = {}
E.rows = {
  {id='jpFxMoveLight',ja='わざの てりかえし',en='Move lighting',group='battleEffects',
    help='わざの いろで じめんと\nポケモンを あざやかに てらします。'},
  {id='jpFxAfterglow',ja='わざの あとの つぶ',en='Move aftermath',group='battleEffects',
    help='ひのこ・こおり・みず・どくなど\nわざの つぶが しばらく のこります。'},
  {id='jpFxHitReaction',ja='ひだんの はんどう',en='Hit reaction',group='battleEffects',
    help='ふんばりと すなぼこり。カメラが\nオンなら しゅんかんてきに よります。'},
  {id='jpFxCritical',ja='きゅうしょの ひかり',en='Critical hit accent',group='battleEffects',
    help='きゅうしょに あたると みじかく ひかります。\nもとの こうかおんは そのままです。'},
  {id='jpFxIdle',ja='ポケモンの まちうごき',en='Pokemon idle motion',group='battleEffects',
    help='たいきちゅうの こきゅうや\nふゆうの うごきです。'},
  {id='jpFxStatus',ja='じょうたいいじょうの え',en='Status particles',group='battleEffects',
    help='どく・まひ・ねむりなどを\nポケモンの そばに えがきます。'},
  {id='jpFxBattleEnvironment',ja='けしきの はんのう',en='Battle environment response',group='battleEffects',
    help='くさの へこみ・わざの かぜ・\nじめんを はしる しょうげきの わです。'},
  {id='jpFxGrass',ja='ふむと へこむ くさ',en='Grass response to walking',group='fieldEffects',
    help='ふんだ くさが へこんで ゆれ\nはなれると もとの かたちに もどります。'},
  {id='jpFxFootsteps',ja='じめんごとの あしもと',en='Footstep particles',group='fieldEffects',
    help='つちでは すな・みずべでは しぶき。\nはしると すこし つよく なります。'},
  {id='jpFxTracks',ja='じめんに のこる あしあと',en='Ground footprints',group='fieldEffects',
    help='すなや つちに あしあとが のこり\nすうびょうで ゆっくり きえます。'},
  {id='jpFxWater',ja='つりと なみのりの なみ',en='Fishing and surf ripples',group='fieldEffects',
    help='つり・なみのりの なみと\nりくに あがった あとの みずしぶきです。'},
  {id='jpFxWind',ja='かぜと くもの かげ',en='Wind and cloud shadows',group='fieldEffects',
    help='そとの くさや はなが ゆれ\nくもの かげが ゆっくり ながれます。'},
  {id='jpFxAmbient',ja='ばしょごとの くうき',en='Location ambience',group='fieldEffects',
    help='もりの は・どうくつの しずく・\nへやの ひかりに まう ほこりです。'},
  {id='jpFxLightShafts',ja='もりの こもれび',en='Forest sunbeams',group='fieldEffects',
    help='ひるの もりに あたたかな\nひかりの すじを えがきます。'},
}
for _,row in ipairs(E.rows) do row.default=true end
function E.normalize(options)
  for _,row in ipairs(E.rows) do
    if type(options[row.id])~='boolean' then options[row.id]=true end
  end
  if options.jpFxDensity~='low' and options.jpFxDensity~='normal' and options.jpFxDensity~='high' then
    options.jpFxDensity='normal'
  end
  return options
end
function E.density(options)
  local value=options and options.jpFxDensity
  return value=='low' and .5 or value=='high' and 1.5 or 1
end
function E.enabled(options,key,battle)
  options=options or {}
  return options[key]~=false and not options.reduceMotion and not options.jpReduceMotion
    and (not battle or options.animations~=false)
end
return E
