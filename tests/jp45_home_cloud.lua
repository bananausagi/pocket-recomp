-- Real launcher geometry and the real native-backup staging path. No ROM or
-- live Google account: Android's document provider is substituted at its seam.
return function(Game,Renderer,check,write)
 local fs,g=love.filesystem,love.graphics
 local Save=require('src.core.SaveData');local Version=require('src.core.Version')
 local View=require('src.import.LauncherView');local Imp=require('src.import.RomImporter')
 local Classic=require('src.ui.ClassicUI');local Transfer=require('src.import.JapaneseSaveTransfer')
 local slot=Save.activeSlot('red_jp');local before=fs.read(Save.saveFilename('red_jp'))
 local opts=Save.loadOptions();local originalLang=opts.jpLauncherLanguage
 local imp=Imp.new(function()end,{launcher=true});imp.ready.red_jp=true;imp.tab='red_jp'
 local function draw(w,h,name)
  love.window.setMode(w,h,{resizable=true});local c=g.newCanvas(w,h);g.setCanvas(c)
  imp:draw();g.setCanvas()
  if name then write(name..'.png',c:newImageData():encode('png'):getString())end
  c:release()
 end
 check(Version.appName=='ポケットリコンプ','user-selected application name')
 for _,language in ipairs({'ja','en'})do
  opts.jpLauncherLanguage=language;Save.saveOptions(opts);imp._ui.options=opts
  for _,size in ipairs({{320,480},{480,800},{800,480},{972,1536},{1536,1160}})do
   imp._ui.page='games';imp._ui.focus=1
   local boxes=0;local box=Classic.box
   Classic.box=function(...)boxes=boxes+1;return box(...)end
   draw(size[1],size[2],'pocket-home-'..language..'-'..size[1]..'x'..size[2])
   Classic.box=box
   check(boxes==0,'home has no enclosing or nested window frames '..language..' '..size[1])
   check(imp._ui.sheets==1,'all six home actions fit '..language..' '..size[1])
   local hits=imp._ui.hits;local ok=true
   for i,a in ipairs(hits)do
    ok=ok and a.x>=0 and a.y>=0 and a.x+a.w<=size[1] and a.y+a.h<=size[2]
    for j=i+1,#hits do local b=hits[j]
     ok=ok and not(a.x<b.x+b.w and b.x<a.x+a.w and a.y<b.y+b.h and b.y<a.y+a.h)
    end
   end
   check(ok,'visible home touch regions fit without overlap '..language..' '..size[1])
   local reached={}
   for i=1,12 do reached[imp._ui.focus]=true;View.keypressed(imp,'down')end
   -- Column navigation visits its column; Tab provides sequential traversal.
   imp._ui.focus=1
   for i=1,6 do reached[imp._ui.focus]=true;View.keypressed(imp,'tab')end
   local n=0;for _ in pairs(reached)do n=n+1 end
   check(n==6,'keyboard can reach every home action '..language..' '..size[1])
  end
 end
 opts.jpLauncherLanguage='ja';Save.saveOptions(opts);imp._ui.options=opts
 imp._ui.page='saves';draw(480,800)
 local rows={};for _,r in ipairs(imp._ui.rows)do rows[r.id]=r end
 check(rows['cloud-save']~=nil,'cloud backup is accessible from save management')
 rows['cloud-save'].action();draw(480,800,'cloud-backup')
 rows={};for _,r in ipairs(imp._ui.rows)do rows[r.id]=r end
 check(rows['cloud-export'] and rows['cloud-import'] and rows['cloud-help'],'cloud screen offers manual save, restore, and help')
 local picker=love.system.createFile;local suggestion
 love.system.createFile=function(n,dir)suggestion=n;check(dir==fs.getSaveDirectory(),'provider stages from the actual save directory');return true end
 rows['cloud-export'].action();love.system.createFile=picker
 local bytes=assert(fs.read('pending_export.sav'));local document=Transfer.decode(bytes)
 check(suggestion and suggestion:match('^pocket%-recomp%-slot%d+%-%d+%-%d+%-%x+%.sav$'),'cloud filename is dated and content identified')
 check(document and document.game=='red_jp','cloud export stages the interoperable checksummed native backup')
 check(fs.read(Save.saveFilename('red_jp'))==before and Save.activeSlot('red_jp')==slot,'cloud export preserves local progress and active slot')
 check(not imp.saveNotice.red_jp.text:find('Save exported',1,true),'opening a picker is not reported as completed upload')
 local choose=imp.chooseSaveImport;local requested
 imp.chooseSaveImport=function(_,v)requested=v end
 rows['cloud-import'].action();imp.chooseSaveImport=choose
 check(requested=='red_jp','cloud restore uses the native backup picker for the selected game')
 rows['cloud-help'].action();draw(480,800,'cloud-help')
 check(imp._ui.messageBody:find('しゅどう',1,true) and imp._ui.messageBody:find('じどう どうきは まだ',1,true),'manual cloud support never claims working automatic account sync')
 local previous=before
 local ok,newSlot=Transfer.import(bytes,'red_jp')
 check(ok and newSlot~=slot and fs.read('saves/red_jp/'..slot..'.lua')==previous,'cloud snapshot restore preserves the source adventure')
 Save.setActiveSlot('red_jp',slot);opts.jpLauncherLanguage=originalLang;Save.saveOptions(opts)
end
