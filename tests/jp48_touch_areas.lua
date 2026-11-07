-- Real input, settings persistence and editor, with ROM-free fixture data.
return function(Game,Renderer,check,write)
 local A=require('src.core.JapaneseTouchAreas');local T=require('src.core.JapaneseTouchMode')
 local E=require('src.ui.JapaneseTouchAreaEditor');local Save=require('src.core.SaveData')
 local Input=require('src.core.Input');local Touch=require('src.core.TouchControls')
 local Stack=require('src.core.StateStack');local Viewport=require('src.render.GameViewport')
 local g=love.graphics;local saved=Save.loadOptions();local opts=Save.loadOptions()
 opts.jpTouchOptimized=true;opts.jpTouchAreas=A.normalize();opts.touchControls={enabled=true}
 Game.save=Save.newGame({version='red_jp'});Game.save.options=opts;Game.sessionMenu=nil
 Input:init();Game.input=Input;Touch:init();Touch:ensureImages();Touch.active=true;Touch:applyOptions(opts)
 Stack:init();Game.stack=Stack;Viewport.reset();Renderer.jpLayout=nil;Renderer.jpBattleState=nil
 local ow={player={px=128,py=128,cellX=8,cellY=8,facing='up'},map={id='TEST'}}
 Game.overworld=ow;Stack:push(ow)
 local function clean()Game:cancelPointers();Touch:reset();Input:reset();Game.sessionMenu=nil end
 local function tap(x,y)Game:touchpressed('areas-tap',x,y);Game:touchreleased('areas-tap',x,y);Input:step()end
 local function center(r)return r.x+r.w/2,r.y+r.h/2 end
 local originalSafe=love.window.getSafeArea
 for _,size in ipairs({{480,800},{800,480},{972,1536}})do
  love.window.setMode(size[1],size[2]);Viewport.reset();clean()
  local w,h=size[1],size[2];local bounds={x=13,y=25,w=w-31,h=h-44}
  love.window.getSafeArea=function()return bounds.x,bounds.y,bounds.w,bounds.h end
  local orientation=A.orientation(w,h)
  opts.jpTouchAreas=A.normalize();local cfg=opts.jpTouchAreas[orientation]
  cfg.back.x=.35;cfg.back.y=.72;cfg.menu.x=.78;cfg.menu.y=.55
  local nav=T.navigation(Game);local bx,by=center(nav[1]);local mx,my=center(nav[2])
  check(math.abs(bx-(bounds.x+bounds.w*.35))<.001 and math.abs(by-(bounds.y+bounds.h*.72))<.001,
    'configured Back maps through safe area '..w)
  check(not T.navHit(bounds.x+bounds.w*.25,bounds.y+4,Game),'old upper strip is absent '..w)
  tap(bx,by);check(Input:wasPressed('b') and not Input:wasPressed('a'),'custom Back emits only B '..w)
  clean();tap(mx,my);check(Game.sessionMenu and Game.sessionMenu.page=='touch','custom Menu opens actions '..w)
  Game:closeSessionMenu();clean()
  -- A drag beginning in Back keeps the same analog origin and never goes back.
  Game:touchpressed('area-drag',bx,by);Game:touchmoved('area-drag',bx+60,by+10)
  check(Touch.floatingGesture and Touch.floatingGesture.x==bx and Touch:layout().dpad.cx==bx,
    'drag from an area becomes movement at its original position '..w)
  Game:touchreleased('area-drag',bx+60,by+10);Input:step()
  check(not Touch.floatingGesture and not Input:wasPressed('b') and not Input:wasPressed('a'),
    'area drag release never navigates or confirms '..w)
  clean();Game:touchpressed('area-stale',bx,by);cfg.back.y=.4
  Game:touchreleased('area-stale',bx,by);Input:step()
  check(not Input:wasPressed('b'),'moving area cancels a held navigation tap '..w)
  cfg.back.enabled=false;check(#T.navigation(Game)==1 and not T.navHit(bx,by,Game),'disabled area has no target '..w)
  cfg.back.enabled=true;cfg.back.x=0;cfg.back.y=1
  local r=T.navigation(Game)[1]
  check(r.x>=bounds.x-1e-6 and r.y+r.h<=bounds.y+bounds.h+1e-6,'edge placement stays inside OS safe area '..w)
 end
 love.window.getSafeArea=originalSafe;love.window.setMode(480,800);Viewport.reset();clean()
 opts.jpTouchAreas=A.normalize()
 local Options=require('src.ui.OptionsMenu');local calls=0
 local state={rows={{label='ONE',activate=function()calls=calls+1 end},
   {label='TWO',activate=function()calls=calls+10 end}},index=1}
 Options.adaptRegisteredState(state,Game);Stack:push(state);state:drawWindowOverlay()
 local l=state.windowPanel:layout();local hit=l.hits[2];local v=l.viewport
 local px,py=v.x+(hit.x+hit.w/2)*v.sx,v.y+(hit.y+hit.h/2)*v.sy
 local cfg=opts.jpTouchAreas.portrait.back;cfg.x=px/480;cfg.y=py/800
 check(not T.navHit(px,py,Game),'visible floating item wins over custom Back')
 tap(px,py);check(calls==10 and not Input:wasPressed('b'),'overlapped floating item executes exactly once')
 clean();Stack.states={ow};Stack.pointerRevision=Stack.pointerRevision+1
 local Pokemon=require('src.pokemon.Pokemon');local Battle=require('src.battle.BattleState')
 Game.save.party={Pokemon.new(Game.data,'FIXMON_A',15)}
 local b=Battle.newWild(Game,'FIXMON_B',8)
 b.phase='menu';b.queue={};b.introSlide=nil;b.jpEncounterAwaitDraw=nil
 b.openParty=function(self)self.chosen='party'end
 -- Begin at choices; cartridge-backed entrance artwork is outside this fixture.
 Stack.states={ow,b};Stack.pointerRevision=Stack.pointerRevision+1
 Renderer.jpLayout='battle';Renderer.jpBattleState=b
 local s=T.battleSurface(Game,b);local c=s.cells[2]
 px,py=s.x+(c.x+c.w/2)*s.sx,s.y+(c.y+c.h/2)*s.sy
 cfg.x=px/480;cfg.y=py/800
 check(not T.navHit(px,py,Game),'visible battle command wins over custom Back')
 tap(px,py);check(b.chosen=='party' and not Input:wasPressed('b'),'overlapped command executes once')
 clean();Stack.states={ow};Stack.pointerRevision=Stack.pointerRevision+1
 Renderer.jpLayout=nil;Renderer.jpBattleState=nil;opts.jpTouchAreas=A.normalize()
 local catalog=require('src.ui.JapaneseSettingsCatalog')
 check(catalog.group('editTouchAreas')=='controls','area editor belongs to Controls once')
 local settings=require('src.import.LauncherSettings')
 local opens,writes=0,0
 local model=settings.open({options=opts,save=function()writes=writes+1;return true end,
   editTouchAreas=function()opens=opens+1 end},'red_jp')
 local function find(rows,id)
  for _,row in ipairs(rows or {})do
   if row.id==id then return row end
   local found=find(row.rows,id);if found then return found end
  end
 end
 local row=find(model.sections,'editTouchAreas')
 check(row~=nil,'launcher settings exposes area editor')
 row.action();check(opens==1 and writes==1,'opening editor saves existing settings first')
 local oldHook=Game.openTouchAreasEditor;Game.openTouchAreasEditor=function()opens=opens+1 end
 local menu=Options.new(Game);local nativeRow=find(menu.rows,'editTouchAreas')
 check(nativeRow~=nil,'in-game settings exposes area editor')
 nativeRow.activate(Game);check(opens==2,'in-game row reaches editor hook')
 local sheet=require('src.ui.SessionMenu').new(Game,'settings')
 row=find(sheet:settings().sections,'editTouchAreas')
 check(row~=nil,'paused session settings exposes area editor')
 Game.openTouchAreasEditor=oldHook

 -- Full editor: move by drag/release, orient, resize, disable, save and reload.
 assert(Save.saveOptions(opts));local closes=0
 E.load({version='red_jp',onClose=function()closes=closes+1 end})
 local function place(nx,ny)
  local p=E.layout().preview;local x,y=p.x+nx*p.w,p.y+ny*p.h
  E.touchpressed('edit',x,y);E.touchreleased('edit',x,y)
 end
 place(.42,.68)
 check(math.abs(E.data.portrait.back.x-.42)<.001 and math.abs(E.data.portrait.back.y-.68)<.001,
   'preview tap places Back away from all edges')
 local p=E.layout().preview
 E.touchpressed('drag',p.x+p.w*.42,p.y+p.h*.68)
 E.touchreleased('drag',p.x+p.w*.50,p.y+p.h*.73)
 check(math.abs(E.data.portrait.back.x-.50)<.001 and math.abs(E.data.portrait.back.y-.73)<.001,
   'coalesced release moves area without motion events')
 E.activate('landscape');place(.30,.62);E.activate('larger');E.activate('menu');E.activate('toggle')
 check(math.abs(E.data.portrait.back.x-.5)<.001 and math.abs(E.data.landscape.back.x-.3)<.001,
   'portrait and landscape placements are independent')
 check(not E.data.landscape.menu.enabled,'each orientation area can be disabled')
 for _,size in ipairs({{480,800},{800,480},{360,640}})do
  love.window.setMode(size[1],size[2]);E.orientation=A.orientation(size[1],size[2]);E.layout()
  local canvas=g.newCanvas(size[1],size[2]);g.setCanvas(canvas);E.draw();g.setCanvas()
  write('touch-area-editor-'..size[1]..'x'..size[2]..'.png',canvas:newImageData():encode('png'):getString());canvas:release()
  l=E.layout()
  check(l.preview.h>40 and l.preview.y+l.preview.h<l.footer,'editor preview fits toolbar and footer '..size[1])
 end
 love.window.setMode(480,800);E.orientation='portrait';local expected=A.key(E.data)
 check(E.close(true) and closes==1,'Save closes editor once')
 check(A.key(Save.loadOptions().jpTouchAreas)==expected,'saved placement survives options reload')
 local unrelated=Save.loadOptions().jpBattleSpacing
 E.load({onClose=function()closes=closes+1 end});place(.2,.4);E.close(false)
 check(A.key(Save.loadOptions().jpTouchAreas)==expected,'Cancel leaves persisted layout unchanged')
 check(Save.loadOptions().jpBattleSpacing==unrelated,'area editing retains unrelated settings')
 E.load();E.activate('reset');p=E.layout().preview
 E.touchpressed('rotate',p.x+p.w*.5,p.y+p.h*.5)
 love.window.setMode(800,480);E.touchreleased('rotate',50,60)
 check(E.pointer==nil and E.drag==nil,'rotation cancels editor pointer even without an update')
 love.window.setMode(480,800);E.layout();p=E.layout().preview
 E.touchpressed('focus',p.x+p.w*.45,p.y+p.h*.6);E.focus(false)
 check(not E.pointer and not E.drag,'focus loss clears editor pointer')
 E.data=A.normalize();E.data.portrait.back.x=E.data.portrait.menu.x
 check(E.close(true)==false and not E.closed,'overlapping enabled areas cannot be saved ambiguously')
 E.data.portrait.menu.enabled=false
 local save=Save.saveOptions;Save.saveOptions=function()return nil end
 check(E.close(true)==false and not E.closed,'write failure keeps editor open for retry')
 Save.saveOptions=save;E.close(false)
 local codec=require('src.import.SettingsTransfer');local before=Save.loadOptions()
 local exported=assert(codec.export(before));local imported=assert(codec.import(exported,Save.defaultOptions()))
 check(A.key(imported.jpTouchAreas)==expected,'settings transfer preserves both area layouts')
 local invalid=Save.loadOptions();invalid.jpTouchAreas.portrait.back.x=2
 check(not codec.export(invalid),'settings transfer rejects out-of-range placement')
 local bad=A.normalize({portrait={back={x=0/0,y=math.huge,size=-99}}})
 check(bad.portrait.back.x==.16 and bad.portrait.back.y==.18 and bad.portrait.back.size==A.MIN_SIZE,
   'malformed local layout falls back to bounded defaults')
 assert(Save.saveOptions(saved));Game.save.options=saved;clean();love.window.setMode(480,800)
 write('touch-areas.json',require('src.link.Json').encode({romUsed=false,editorSavedAndReloaded=true,
   orientationLayouts=true,oldEdgeStripRemoved=true,visibleChoicesHavePriority=true}))
end
