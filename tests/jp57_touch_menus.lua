-- Exercise actual game screens, native callbacks and rendered targets with
-- no A/B controls. The ROM-free display fixture supplies only data/assets.
return function(Game,Renderer,check,write,u)
 local put,draw,tap=u.put,u.draw,u.tap
 local H=require('src.ui.JapaneseTouchTargets')
 local Input=require('src.core.Input')
 local Stack=Game.stack
 local suffix=u.suffix
 local function ok(value,label)check(value,'JP57 '..label..' '..suffix)end
 local function exists(id)
  for _,t in ipairs(assert(H.frameFor(Game)).targets)do if t.id==id then return t end end
 end
 u.opts.jpTouchOptimized=true
 if suffix=='480x800' then
  local g=love.graphics;local Style=require('src.core.TouchControlsStyle')
  local canvas=g.newCanvas(1000,640,{dpiscale=1})
  g.push('all');g.setCanvas(canvas);g.origin();g.setShader();g.clear(.88,.88,.845,1)
  local font=g.newFont('assets/fonts/noto/NotoSansJP-Regular.ttf',24)
  font:setFilter('linear','linear');g.setFont(font);g.setColor(.17,.19,.22,1)
  g.print('POCKET RECOMP  /  jp.57',54,40)
  g.setColor(.37,.38,.39,1);g.print('標準タッチボタンの素材・実際の描画',54,82)
  Style.draw({dpad={cx=235,cy=320,w=310},a={cx=826,cy=279,w=154},
    b={cx=667,cy=373,w=154},start={cx=529,cy=519,w=154},select={cx=360,cy=519,w=154}},
    {},nil,1,nil,false,false)
  g.setFont(font);g.setColor(.37,.38,.39,1)
  g.print('「ボタンなし」では、これらを表示せず項目を直接選びます。',54,588)
  g.pop();write('gen1recomp-jp57-controls-preview.png',canvas:newImageData():encode('png'):getString());canvas:release()
 end
 ok(not require('src.core.TouchControls'):optimizedButtons(),'no A/B controls')
 local Menu=require('src.ui.Menu')
 local entries={};local chosen
 for i=1,16 do entries[i]={label='ITEM '..i,onSelect=function()chosen=i end}end
 local menu=put(Menu.new(Game,entries,{maxVisible=4,noSound=true}))
 draw('jp57-long-menu-'..suffix);tap('action-next');draw()
 ok(menu.index==5 and menu.scroll>0,'long menu next page')
 tap('row-5');ok(chosen==5 and Stack:top()==u.ow,'page item opens once')
 menu=put(Menu.new(Game,{{label='えらぶ'}},{cancelable=false,noSound=true}));draw()
 ok(not exists('action-back'),'forced choice has no false cancel command')
 local List=require('src.ui.ListMenu');local selected
 local items={};for i=1,15 do items[i]={label='どうぐ '..i}end
 local list=put(List.new(Game,'どうぐ',items,{itemBox=true,onChoose=function(item)selected=item end}))
 draw('jp57-bag-'..suffix);tap('action-next');draw();tap('item-'..list.index)
 ok(selected==items[4],'bag paging selects actual scrolled item')
 draw();tap('action-back');ok(Stack:top()==u.ow,'bag returns to parent')
 local party=put(require('src.ui.PartyMenu').new(Game))
 party.swapFrom=1;draw();tap('action-back')
 ok(not party.swapFrom and Stack:top()==party,'swap cancellation stays in party list')
 party.softboiledFrom=1;draw();tap('action-back')
 ok(not party.softboiledFrom and Stack:top()==party,'transfer cancellation stays in party list')
 draw();tap('party-1');draw('jp57-party-actions-'..suffix)
 tap('action-back');ok(not party.submenu and Stack:top()==party,'party command Back is one level')
 local Summary=require('src.ui.SummaryMenu')
 local summary=put(Summary.new(Game,Game.save.party[1]));summary.whiteHold=0
 draw('jp57-summary-'..suffix);tap('action-page');draw();tap('action-page')
 ok(summary.page==1,'summary previous page works')
 draw();tap('action-back');ok(summary.closing or Stack:top()~=summary,'summary Back exits first page')
 local dex=put(require('src.ui.DexEntryMenu').new(Game,'FIXMON_A'))
 dex.picDelay=0;dex.crySrc=nil;dex.pageCount=3;draw();tap('action-page')
 draw();tap('action-previous');ok(dex.page==1,'dex previous page works')
 draw();tap('action-back');ok(Stack:top()==u.ow,'dex Back exits first page')
 local name=put(require('src.ui.NamingScreen').new(Game));draw();local before=name.lower
 tap('action-case');ok(name.lower~=before,'keyboard case command')
 local Prize=require('src.ui.PrizeCounter');local picked,cancelled
 local prize=put(Prize.new(Game,{{name='けいひん1',cost=10},{name='けいひん2',cost=20},{name='けいひん3',cost=30}},
  {onPick=function(p,i)picked=i end,onCancel=function()cancelled=true end}))
 draw('jp57-prizes-'..suffix);tap('prize-2');ok(picked==2,'prize direct selection')
 draw();tap('prize-4');ok(cancelled,'prize cancel choice')
 -- Reminder uses the actual eligibility and snapshot validation. No mock
 -- of its apply/confirm methods; selecting a slot must open confirmation.
 u.opts.jpMoveReminder=true
 local mon=Game.save.party[1];local def=Game.data.pokemon[mon.species]
 local oldLearn=def.learnset;def.learnset={}
 for i=1,7 do
  local id='TOUCH57_'..i;Game.data.moves[id]={id=id,name='わざ '..i,pp=20,power=40,type='NORMAL'}
  def.learnset[i]={level=1,move=id}
 end
 local reminder=put(require('src.ui.JapaneseMoveReminderMenu').new(Game,mon))
 draw('jp57-reminder-'..suffix);tap('reminder-2')
 ok(reminder.phase=='replace','reminder opens slot chooser for tapped move')
 draw();tap('action-back');ok(reminder.phase=='learn' and Stack:top()==reminder,'reminder returns one level')
 draw();tap('action-next');draw();ok(reminder.index>5,'reminder next page')
 local t=u.target('reminder-'..reminder.index);local x,y=t.x+t.w/2,t.y+t.h/2
 Game:touchpressed('reminder-stale',x,y);reminder.moves={}
 Game:touchreleased('reminder-stale',x,y);u.tick()
 ok(reminder.phase=='learn','replaced reminder list cancels held tap')
 reminder:refresh();reminder.index=1;reminder.scroll=0;draw();tap('reminder-1');draw();tap('reminder-2')
 ok(Stack:top()~=reminder and mon.moves[2].id~='TOUCH57_1','move replacement requires native confirmation')
 def.learnset=oldLearn
 -- Move-learning cancellation keeps the game's explicit abandon prompt.
 local learn=put(require('src.ui.MoveLearnMenu').new(Game,mon,'TOUCH57_1'))
 while Stack:top()~=learn do Stack:pop()end
 learn.selecting=true;draw('jp57-learn-move-'..suffix);tap('action-back')
 ok(Stack:top()~=learn and mon.moves[1].id~='TOUCH57_1','forget move Back requires abandon confirmation')
 local evolution=put(require('src.ui.EvolutionState').new(Game,mon,'FIXMON_B',nil,'LEVEL'))
 evolution.loading=nil;evolution.cryWait=false;evolution.t=90
 draw('jp57-evolution-'..suffix);tap('action-back')
 ok(evolution.canceled and mon.species=='FIXMON_A','visible evolution cancel respects native grace period')
 local stone=put(require('src.ui.EvolutionState').new(Game,mon,'FIXMON_B',nil,'ITEM'))
 stone.loading=nil;stone.cryWait=false;stone.t=90;draw()
 ok(not exists('action-back'),'item evolution has no misleading cancellation')
 local Report=require('src.ui.QuarantineReport');local report=put(Report.new(Game,{}))
 report.lines={};for i=1,20 do report.lines[i]='LINE '..i end
 draw();tap('action-next');ok(report.offset>0,'load report page forward')
 draw();tap('action-continue');ok(Stack:top()==u.ow,'load report continue command')
 local Battle=require('src.battle.BattleState')
 put({})
 local battle=Battle.newWild(Game,'FIXMON_B',8)
 Stack.states={u.ow,battle};Stack.pointerRevision=Stack.pointerRevision+1
 battle.phase='moveSelect';battle.queue={};battle.introSlide=0;battle.jpEncounterAwaitDraw=nil
 battle.showPlayerBack=false;battle.showEnemy=false;draw('jp57-battle-no-buttons-'..suffix)
 tap('action-arrange');ok(battle.moveSwapIndex~=nil,'battle rearrange without SELECT button')
 draw();tap('action-back');ok(not battle.moveSwapIndex and battle.phase=='moveSelect','battle Back cancels move rearrangement one level')
 battle.phase='mimicSelect';battle.mimicMoves=battle.player.curMoves;battle.mimicIndex=1;draw()
 ok(not exists('action-back'),'Mimic forced choice does not offer invalid cancel')
 local Palette=require('src.render.Palette');local color
 local palette=put(require('src.ui.PaletteScreen').new(Game,{palette=Palette,get=function()return ''end,set=function(v)color=v end}))
 palette:push('mono');draw('jp57-palette-'..suffix);tap('palette-2')
 ok(color~=nil and palette.index==2,'color grid directly selects displayed swatch')
 draw();tap('action-back');ok(palette.view=='root' and Stack:top()==palette,'color grid returns to parent palette page')
 local pic=put(require('src.ui.PicBox').new(Game,'missing-test-image.png'));draw();tap('action-back')
 ok(Stack:top()==u.ow,'picture window return choice')
 local diploma=put(require('src.ui.Diploma').new(Game));draw();tap('action-back')
 ok(Stack:top()==u.ow,'diploma return choice')
 local league=put(require('src.ui.LeaguePC').new(Game));draw();tap('action-back')
 ok(Stack:top()==u.ow,'Hall of Fame viewer return choice')
 local bindings=put(require('src.ui.BindingsMenu').new(Game));draw();tap('item-1')
 ok(bindings.capture~=nil,'binding row arms actual capture')
 draw('jp57-binding-capture-'..suffix);ok(not exists('item-2'),'capture blocks underlying rows')
 tap('action-back');ok(not bindings.capture and Stack:top()==bindings,'capture Back cancels without assigning or leaving')
 draw();tap('action-tools');ok(Stack:top()~=bindings,'binding reset commands accessible without START/SELECT')
 -- Floating habitat panel routes through its own final window transform.
 local hf=require('tests.jp25_habitat_fixture')()
 hf.save.options=u.opts;hf.stack=Stack;hf.input=Input
 hf.save.jpHabitatVisited={ROUTE_1=true,ROUTE_2=true,MT_MOON_1F=true,ROUTE_3=true}
 local habitat=put(require('src.ui.JapaneseHabitatList').new(hf))
 local function habitatTap(id)
  draw();local l=habitat:layout();local x,y
  if id:match('^row') then x,y=24,l.body+4
  else
   for i,a in ipairs(habitat:commands(l))do if a.id==id then
    x,y=16+((i-1)%2)*(l.width-16)/2,l.footer+math.floor((i-1)/2)*16+8
   end end
  end
  x,y=l.view.x+x*l.view.sx,l.view.y+y*l.view.sy
  Game:touchpressed('habitat',x,y);Game:touchreleased('habitat',x,y)
 end
 draw('jp57-habitat-'..suffix);habitatTap('areas');ok(habitat.areaMode,'habitat area choices open')
 habitatTap('row');ok(not habitat.areaMode,'habitat direct area choice')
 local method=habitat.method;habitatTap('filter');ok(habitat.method~=method,'habitat filter command')
 habitatTap('areas');habitatTap('back');ok(Stack:top()==habitat and not habitat.areaMode,'habitat Back is one level')
 habitatTap('back');ok(Stack:top()==u.ow,'habitat Back returns to parent')
 -- All session roots and nested pages have a return route.
 local Session=require('src.ui.SessionMenu')
 local session=Session.new(Game,'touch');Game.sessionMenu=session
 local resume;for _,r in ipairs(session:rows())do if r.id=='resume'then resume=r end end
 ok(resume~=nil,'touch session has explicit return choice')
 session:open('settings');session:open('settings-detail',1);session:back()
 ok(session.page=='settings' and Game.sessionMenu==session,'settings detail returns to settings')
 session:back();ok(session.page=='touch' and Game.sessionMenu==session,'settings returns to entry menu')
 session:back();ok(Game.sessionMenu==nil,'entry menu Back resumes game')
 put(Menu.new(Game,{{label='たたかう'},{label='ポケモン'}},{noSound=true}))
 draw('jp57-no-buttons-'..suffix)
end
