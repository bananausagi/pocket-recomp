-- Real UI fonts, modal bounds, and unchanged picker/keyboard input semantics.
local function run()
  local root = assert(os.getenv('JP_KIT_ROOT'))
  local out = assert(os.getenv('JP_KIT_OUT'))
  package.path = root .. '/?.lua;' .. package.path
  local T = require('tests.harness').suite('Japanese UI kit')
  local Kit = require('src.ui.kit.Kit')
  local Browser, Keyboard = Kit.FileBrowser, Kit.VirtualKeyboard
  local UI = require('src.ui.JapaneseUIStrings')
  local catalog = require('src.core.JapaneseStringsKit')
  local Json = require('src.link.Json')
  local function formats(s) local a = {} for x in s:gmatch('%%[%-+ #0%d%.]*[cdiouxXeEfgGqs%%]') do a[#a+1] = x end return table.concat(a,'|') end
  Kit.layout(640,480)
  for key,value in pairs(catalog) do
    T.eq(formats(key),formats(value),'format arguments retained: '..key)
    T.check(Kit.font('small'):hasGlyphs(value),'real UI font has every glyph: '..key)
  end
  local popen = io.popen
  io.popen = function() return {read=function() return 'Folder/\n100% custom.gb\nFile Two.zip\nLong User Supplied Name That Must Not Be Changed.zip\n' end, close=function()end} end
  local picked, cancelled
  Browser.open({initialPath='/fixture',mode='all',language='ja',onSelect=function(path)picked=path end,onCancel=function()cancelled=true end})
  io.popen = popen
  T.eq(Browser.entries[1].name,'Folder','directory name is stored verbatim')
  local function capture(which,W,H,shot)
    love.window.setMode(W,H,{vsync=0})
    Kit.layout(W,H)
    Kit.beginFrame(-1,-1,false,0)
    local canvas = love.graphics.newCanvas(W,H)
    love.graphics.setCanvas(canvas);love.graphics.clear(0,0,0,1)
    local drawn = {}
    local cellOverflow = {}
    local center, bold = Kit.textCenter, Kit.textCenterBold
    local function trackCenter(fn)
      return function(name,str,x,y,w,...)
        if Kit.textWidth(name,str) > w then cellOverflow[#cellOverflow+1]=str end
        return fn(name,str,x,y,w,...)
      end
    end
    Kit.textCenter,Kit.textCenterBold=trackCenter(center),trackCenter(bold)
    local draw = Kit.text
    Kit.text = function(name,str,x,y,...)
      drawn[#drawn+1]={name=name,str=str,x=x,y=y,w=Kit.textWidth(name,str),h=Kit.textHeight(name)}
      return draw(name,str,x,y,...)
    end
    which.draw({W=W,H=H,s=Kit.scale})
    Kit.text = draw
    Kit.textCenter,Kit.textCenterBold=center,bold
    if which.language=='ja' then
      T.check(#cellOverflow==0,'centered labels fit their controls at '..W..': '..table.concat(cellOverflow,', '))
    end
    Kit.endFrame()
    love.graphics.setCanvas()
    if shot then
      local data=canvas:newImageData(); local encoded=data:encode('png')
      local f=assert(io.open(out..'/'..shot,'wb'));f:write(encoded:getString());f:close();data:release()
    end
    canvas:release()
    return drawn
  end
  local function contains(rows,str)for _,r in ipairs(rows)do if r.str==str then return true end end return false end
  local function allBounds(rows,W,H,label)
    local okay=true;local detail=''
    for _,r in ipairs(rows)do
      if r.x < 0 or r.y < 0 or r.x+r.w > W+1 or r.y+r.h > H+1 then okay=false;detail=detail..r.str..' ' end
    end
    T.check(okay,label..' text inside viewport: '..detail)
  end
  for _,size in ipairs({{320,480},{640,480},{972,1536}})do
    local W,H=size[1],size[2]
    local rows=capture(Browser,W,H,'file-browser-'..W..'.png')
    T.check(contains(rows,'ファイルを えらぶ'),'pre-ROM browser title is Japanese')
    T.check(contains(rows,'[フォルダ] Folder'),'folder marker translates without changing folder name')
    T.check(contains(rows,'[ファイル] 100% custom.gb'),'filename and percent remain literal')
    allBounds(rows,W,H,'browser '..W)
  end
  Browser.selectedIdx=2;Browser.gamepadpressed('a')
  T.eq(picked,'/fixture/100% custom.gb','selected path and callback retain exact bytes')
  T.check(not Browser.active,'selection closes browser')
  io.popen=function()return{read=function()return ''end,close=function()end}end
  Browser.open({initialPath='/',language='ja',onCancel=function()cancelled=true end})
  io.popen=popen
  Browser.entries={}
  local rows=capture(Browser,320,480)
  T.check(contains(rows,'ファイルが ありません。'),'empty folder message is Japanese')
  Browser.keypressed('escape');T.check(cancelled,'cancel callback unchanged')
  Browser.active=true;Browser.language='en';Browser.title='Select File';Browser.mode='all'
  rows=capture(Browser,640,480)
  T.check(contains(rows,'Select File'),'English browser title retained')
  T.check(contains(rows,'No files found in this folder.'),'English empty message retained')
  Browser.active=false

  local completed,confirmed
  T.check(Keyboard.open({language='ja',text='Name 100%',onDone=function(v,ok)completed,confirmed=v,ok end}),'handheld keyboard opens')
  T.eq(Keyboard.text,'Name 100%','keyboard input starts unchanged')
  for _,size in ipairs({{320,480},{640,480},{972,1536}})do
    local W,H=size[1],size[2]
    rows=capture(Keyboard,W,H,'keyboard-'..W..'.png')
    for _,label in ipairs({'もじを いれる','大文字','きごう','空白','消す','決定','全消去','https://','.json','.zip'})do
      T.check(contains(rows,label),'keyboard label visible: '..label)
    end
    allBounds(rows,W,H,'keyboard '..W)
  end
  Keyboard.row,Keyboard.col=5,1;Keyboard.gamepadpressed('a')
  T.eq(Keyboard.mode,2,'translated shift still changes mode')
  rows=capture(Keyboard,320,480);T.check(contains(rows,'小文字'),'upper mode displays lowercase action')
  Keyboard.row,Keyboard.col=1,1;Keyboard.gamepadpressed('a')
  Keyboard.gamepadpressed('y');Keyboard.gamepadpressed('x')
  Keyboard.row,Keyboard.col=6,1;Keyboard.gamepadpressed('a')
  T.eq(Keyboard.text,'Name 100%1https://','character, space, backspace and URL actions unchanged')
  Keyboard.gamepadpressed('start')
  T.eq(completed,'Name 100%1https://','confirmation receives exact input');T.eq(confirmed,true,'confirmation flag retained')
  Keyboard.open({language='en',title='CUSTOM 100% TITLE',text='unchanged',onDone=function(v,ok)completed,confirmed=v,ok end})
  rows=capture(Keyboard,640,480)
  T.check(contains(rows,'CUSTOM 100% TITLE'),'custom title is preserved')
  for _,label in ipairs({'Shift','Sym','Space','Bksp','Done','Clear'})do T.check(contains(rows,label),'English key retained: '..label)end
  Keyboard.gamepadpressed('b');T.eq(completed,'unchanged','cancel preserves text');T.eq(confirmed,false,'cancel flag retained')
  package.loaded['src.core.Game']={data={constants={language='ja'},strings={['UI kit: Done']='MOD Done'}}}
  Keyboard.open({language='ja'});rows=capture(Keyboard,640,480)
  T.check(contains(rows,'MOD Done'),'explicit MOD UI translation wins')
  package.loaded['src.core.Game']=nil
  Keyboard.close(false)
  Kit.layout(640,480);Kit.beginFrame(-1,-1,false,0);Kit._activateId='language-test'
  Kit.textfield('language-test',0,0,200,40,'saved','Enter Text',{language='en'})
  T.eq(Keyboard.language,'en','textfield passes explicit caller language')
  Keyboard.close(false);Kit.endFrame()
  local f=assert(io.open(out..'/results.json','wb'));f:write(Json.encode({checks=T.checks,failures=T.failures,messages=T.messages}));f:close()
  T.finish()
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
