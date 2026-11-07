local function run()
  local out=assert(os.getenv('STUDIO_LOCALE_QA_OUT'))
  local Studio=require('src.ui.SkinStudio')
  local Skin=require('src.core.TouchSkin')
  local Save=require('src.core.SaveData')
  local Kit=require('src.ui.kit.Kit')
  local Theme=require('src.ui.kit.Theme')
  local Strings=require('src.ui.JapaneseUIStrings')
  local Json=require('src.link.Json')
  local checks,labels,captures=0,{},{}
  local function check(value,message)
    assert(value,message);checks=checks+1
    print('PASS '..message)
  end
  local skin=Skin.newSkin('MySkin100')
  skin.name='My Skin 100%'
  skin.pages[1].name='My Page 100%'
  skin.pages[1].controls={Skin.newControl('a',.8,.72,.15,.12,'radial'),Skin.newControl('left|up',.2,.7,.18,.16,'rect')}
  local entry={id=skin.id,root=skin.root,source='user'}
  Skin.list=function()return {entry}end
  Skin.find=function(id)if id==entry.id then return entry end end
  Skin.load=function()return skin end
  Skin.listImages=function()return {'Custom Artwork 100%.png'}end
  local saved={touchControls={enabled=true,skin=skin.id}}
  Save.loadOptions=function()return saved end
  Save.saveOptions=function(value)saved=value end
  local original={}
  local labelSlots={button=5,checkbox=6,text=2,textBold=2,textCenter=2,textCenterBold=2,caption=3,textfield=7}
  for method,index in pairs(labelSlots) do
    original[method]=Kit[method]
    Kit[method]=function(...)
      local args={...};local value=args[index]
      if type(value)=='string' then labels[#labels+1]=value end
      return original[method](...)
    end
  end
  local function draw(name,legacy)
    labels={}
    local w,h=love.graphics.getDimensions()
    local canvas=love.graphics.newCanvas(w,h)
    love.graphics.setCanvas(canvas);love.graphics.clear()
    if legacy then Studio.drawLegacy() else Studio.draw() end
    love.graphics.setCanvas()
    local filename=name..'-'..w..'x'..h
    local f=assert(io.open(out..'/'..filename..'.png','wb'))
    f:write(canvas:newImageData():encode('png'):getString());f:close();canvas:release()
    captures[filename]=labels
    for _,font in pairs(Kit.fonts)do
      if type(font)=='userdata' and font.hasGlyphs then
        for _,value in ipairs(labels)do check(font:hasGlyphs(value),'glyphs '..filename..' '..value)end
      end
    end
    return table.concat(labels,'\n')
  end
  for _,size in ipairs({{480,800},{800,480},{320,480},{1024,768}})do
    love.window.setMode(size[1],size[2],{resizable=true,vsync=0})
    Studio.load({version='red_jp',skinId=skin.id})
    local text=draw('ja-library')
    check(text:find('スキンいちらん',1,true),'Japanese library title')
    check(not text:find('My Skins',1,true),'English title absent in Japanese')
    Studio.enterEditor();Studio.selected=2
    text=draw('ja-editor')
    check(Studio.skin.name=='My Skin 100%','custom skin name unchanged')
    check(Studio.selectedControl().spec=='left|up','action identifier unchanged after drawing')
    for _,kind in ipairs({'bind','image','open','page','export','screen'})do
      Studio.openModal(kind)
      if kind=='page'then Studio.pageNameField=Studio.page().name end
      draw('ja-'..kind)
      Studio.closeModal()
    end
    Studio.ask(Strings.lookup('SkinStudio: Return to My Skins and lose the unsaved changes?','ja'),function()end)
    draw('ja-confirm');Studio.confirmNo()
    if size[1]==1024 then draw('ja-legacy',true)end
    Studio.unload()
  end
  love.window.setMode(480,800,{resizable=true,vsync=0})
  Studio.load({version='red',skinId=skin.id})
  check(draw('en-library'):find('My Skins',1,true),'English title restored without reloading module')
  Studio.enterEditor();Studio.selected=2
  check(Studio.bindLabel('left|up')=='left|up','English bind spelling unchanged')
  draw('en-editor')
  Studio.openModal('screen');draw('en-screen');Studio.closeModal()
  Studio.version='red_jp'
  check(Studio.bindLabel('left|up')=='左 + 上','Japanese compound bind label')
  check(Studio.bindLabel('key:escape|a')=='Esc キー + A','Japanese keyboard bind label')
  check(Studio.bindLabel('custom_action')=='custom_action','unknown custom action untouched')
  Studio.imageTarget='bezel'
  check(Studio.imageTargetLabel()=='bezel','image target protocol unchanged')
  local name,detail=Studio.pageLabel(1)
  check(name=='My Page 100%' and detail:find('2個',1,true),'page name and control count preserved')
  Studio.renamePage('Save 100%')
  check(Studio.page().name=='Save 100%','rename does not translate user input')
  check(Studio.status:find('Save 100%',1,true),'rename status preserves percent and English name')
  Studio.version='red'
  Studio.renamePage('English Name')
  check(Studio.status=='Renamed page 1 to English Name','English format remains exact')
  Studio.version=nil
  check(Studio.uiLanguage()=='ja','unspecified launch language uses Japanese')
  local oldSave,oldExport,oldImport=Skin.saveTo,Skin.export,Skin.importImage
  Skin.saveTo=function()return 'skins/MySkin100',{'missing.png'}end
  Studio.save()
  check(Studio.status:find('skins/MySkin100',1,true) and Studio.status:find('1個',1,true),'save status preserves path and missing count')
  Skin.export=function()return nil,'no writable filesystem'end
  Studio.export()
  check(Studio.status:find('ファイルを保存できません',1,true),'known backend error translated at display boundary')
  Skin.importImage=function()return 'My Art 100%.png'end
  Studio.adoptImage('My Art 100%.png','fixture','bezel')
  check(Studio.page().imagePath=='My Art 100%.png','import preserves image filename')
  check(Studio.status:find('My Art 100%.png',1,true) and Studio.status:find('がめん',1,true),'bezel import includes Japanese detection hint')
  Skin.saveTo,Skin.export,Skin.importImage=oldSave,oldExport,oldImport
  local f=assert(io.open(out..'/captured-labels.json','w'));f:write(Json.encode(captures));f:close()
  print('RESULT '..checks..' checks passed')
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
