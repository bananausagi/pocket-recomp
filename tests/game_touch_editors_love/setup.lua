-- Actual main.lua + Game/Input/StartMenu/Options/Editors. Only Game.load is
-- replaced with a synthetic field, so no ROM or extracted graphics are needed.
return function(importer)
  local Data=require('src.core.Data');Data.constants={language='ja'};Data.field={};Data.render_pipelines={}
  require('tests.jp_battle_bitmap_font')(Data)
  require('src.core.Strings').load(Data)
  local Game=require('src.core.Game');local Input=require('src.core.Input')
  local Stack=require('src.core.StateStack');local Touch=require('src.core.TouchControls')
  local Renderer=require('src.render.Renderer');local Save=require('src.core.SaveData')
  local Runtime=require('src.mods.Runtime')
  local q={game=Game,worldTicks=0,loads=0,updates=0,releases=0,pointerCancels=0,checks=0}
  _G.gameEditorQA=q
  function q.check(ok,label)assert(ok,label);q.checks=q.checks+1;print('EDITOR PASS '..label)end
  local originalLoad=Game.load
  Game.load=function(self)
    q.loads=q.loads+1
    Input:init();Stack:init();Touch:init();Touch.active=true;Touch.sessionMenuActive=true;Renderer:init()
    require('src.render.Pipelines').install(Data)
    require('src.render.DotMatrix').setLevel(0);require('src.render.PaletteFX').setMode('gbc')
    self.data=Data;self.renderer=Renderer;self.input=Input;self.stack=Stack
    self.save={options=Save.defaultOptions(),flags={},player={name='レッド'},party={},playTime=123,
      pokedex={owned={},seen={}},bag={},modData={}}
    self.save.options.colors='gbc';self.save.options.jpDialogScale=1
    self.save.options.musicVol=6;self.save.options.modOptions={fixture={preserve='live'}}
    local disk=Save.defaultOptions();disk.musicVol=3;disk.modOptions={fixture={preserve='disk'}};Save.saveOptions(disk)
    self.mods={generation=1,status=function()return {available={},errors={}}end,
      releaseModInput=function()q.releases=q.releases+1 end}
    self.modStatus=self.mods:status()
    local field={isOpaque=true,isOverworld=true,player={}}
    function field:update()q.worldTicks=q.worldTicks+1 end
    function field:draw()
      local g=love.graphics;local w,h=g.getDimensions();local previous=g.getCanvas()
      if not self.image or self.image:getWidth()~=w or self.image:getHeight()~=h then
        if self.image then self.image:release()end
        self.image=g.newCanvas(w,h,{dpiscale=1})
      end
      g.setCanvas(self.image);g.clear(.22,.48,.30,1)
      for x=0,w,32 do g.setColor(.19,.42,.26,1);g.rectangle('fill',x,0,16,h)end
      g.setColor(.62,.55,.35,1);g.rectangle('fill',w*.15,0,w*.12,h)
      g.setColor(.15,.34,.58,1);g.rectangle('fill',w*.66,h*.12,w*.25,h*.23)
      g.setCanvas(previous);Renderer:setWorldOverride(self.image)
    end
    q.field=field;self.overworld=field;Stack.states={field}
  end
  local update=Game.update
  Game.update=function(self,dt)q.updates=q.updates+1;return update(self,dt)end
  local cancel=Game.cancelPointers
  Game.cancelPointers=function(self)q.pointerCancels=q.pointerCancels+1;return cancel(self)end
  package.preload['src.core.Game']=function()return Game end
  local sound=require('src.core.Sound');sound.play=function()end
  local call=Runtime.call
  Runtime.call=function(event,base,...)
    local result=call(event,base,...)
    if event=='ui.options.rows'then result[#result+1]={id='fixture-mod-row',label='MOD OPTION',step=function()q.modSteps=(q.modSteps or 0)+1;return true end}end
    return result
  end
  importer.ready.red_jp=true;importer:play('red_jp')
  Game.load=originalLoad
  q.check(type(Game.openTouchControlsEditor)=='function'and type(Game.openSkinStudio)=='function','real bootGame installs editor callbacks')
  Game:openSessionMenu();q.start=Stack:top()
  local function press(button)
    Input:sourcePress(button,'qa-main');Input:sourceRelease(button,'qa-main');Game:update(1/60+.00001)
  end
  for index,row in ipairs(q.start.items)do if row.id=='system-settings'then q.start.index=index;break end end
  press('a');q.options=Stack:top();q.liveOptions=Game.save.options
  q.check(q.options.screenId=='OptionsMenu'and q.options.floatingPanel,'actual native START opens floating Options')
  local found={};for _,row in ipairs(q.options.rows)do found[row.id]=true end
  q.check(found.editTouchControls and found.openSkinStudio and found['fixture-mod-row'],'both new routes and external MOD row hook remain')
  function q.select(id)
    q.check(Stack:top()==q.options,'same Options instance before editor')
    assert(q.options:focusRow(id),'missing '..id)
    q.beforeUpdates=q.updates;q.beforeReleases=q.releases;q.beforeCancels=q.pointerCancels
    Input:sourcePress('right','qa-held-before-editor')
  end
  function q.opened(kind)
    local editor=package.loaded[kind=='touch'and 'src.ui.TouchControlsEditor'or 'src.ui.SkinStudio']
    q.check(editor and editor.onClose~=nil,'actual '..kind..' editor loaded through main')
    q.check(not Input:isDown('right'),'opening editor clears held game input')
    q.check(q.releases>q.beforeReleases and q.pointerCancels>q.beforeCancels,'opening editor cancels MOD/private pointers')
    q.check(Stack:top()==q.options and Stack.states[2]==q.start and #Stack.states==3,'editor preserves exact underlying menu stack')
    q.overlayUpdates=q.updates;q.beforeReleases=q.releases;q.beforeCancels=q.pointerCancels
  end
  function q.frozen()
    q.check(q.updates==q.overlayUpdates and q.worldTicks==0 and Game.save.playTime==123,'main overlay freezes game/MOD update and play time')
  end
  function q.closed()
    q.check(Stack:top()==q.options and #Stack.states==3 and Stack.states[1]==q.field,'close returns to same Options over same field')
    q.check(Game.save.options==q.liveOptions and Game.save.options.musicVol==6
      and Game.save.options.modOptions.fixture.preserve=='live','non-editor live options and object identity retained')
    local disk=Save.loadOptions()
    q.check(disk.musicVol==3 and disk.modOptions.fixture.preserve=='disk','editor does not overwrite unrelated stored options')
    q.check(Touch.active and Touch.sessionMenuActive and not Touch.preview,'touch runtime mode restored without preview or old hotbar')
    q.check(not Input:isDown('right')and q.releases>q.beforeReleases and q.pointerCancels>q.beforeCancels,'close releases held game/MOD input again')
    q.check(q.loads==1 and q.worldTicks==0 and Game.save.playTime==123,'no game reboot, progress save, or world step')
  end
  function q.finish()
    -- Test completion must bypass the real in-game window-close save prompt.
    love.quit=function()return false end
    local rows=q.options.rows;local Options=require('src.ui.OptionsMenu')
    Data.constants.language='en'
    local english=Options.new(Game);local found=false
    for _,row in ipairs(english.rows)do found=found or row.id=='editTouchControls'or row.id=='openSkinStudio'end
    q.check(not found,'other-language Options stay unchanged')
    Data.constants.language='ja'
    q.options.rows=rows
    local f=assert(io.open(assert(os.getenv('JP_MAIN_QA_OUTPUT'))..'/editor-results.json','wb'))
    f:write(require('src.link.Json').encode({checks=q.checks,worldTicks=q.worldTicks,loads=q.loads,
      playTime=Game.save.playTime,actualMain=true,actualGame=true,romFree=true}));f:close()
  end
end
