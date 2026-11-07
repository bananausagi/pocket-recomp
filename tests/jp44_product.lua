-- Installed seven-MOD evolution rules, real backup IO, and the actual home UI.
return function(Game,Renderer,check,write)
 local fs,g=love.filesystem,love.graphics
 local Save=require('src.core.SaveData');local S=require('src.core.SaveSerializer')
 local E=require('src.pokemon.Evolution');local Pokemon=require('src.pokemon.Pokemon')
 local Guide=require('src.pokemon.JapaneseEvolutionGuide')
 local pairs4={{'KADABRA','ALAKAZAM',42},{'HAUNTER','GENGAR',42},{'GRAVELER','GOLEM',42},{'MACHOKE','MACHAMP',45}}
 local party={}
 for _,p in ipairs(pairs4)do
  local mon=Pokemon.new(Game.data,p[1],p[3]-1,function(a)return a end)
  check(E.pendingFor(Game,mon,{kind='levelup'})==nil,p[1]..' does not evolve early')
  mon.level=p[3]
  check(E.pendingFor(Game,mon,{kind='levelup'})==p[2],p[1]..' installed MOD evolves without trading')
  check(E.pendingFor(Game,mon,{kind='manual'})==nil,p[1]..' guide never triggers an evolution')
  check(Guide.text(Game,mon):find('レベル'..p[3],1,true)~=nil,p[1]..' guide uses actual merged level')
  mon.level=p[3]+1
  check(E.pendingFor(Game,mon,{kind='levelup'})==p[2],p[1]..' remains eligible after canceling')
  local oldName=mon.nickname;E.apply(Game,mon,p[2],'LEVEL')
  check(mon.species==p[2] and mon.nickname==oldName and mon.hp>0,p[1]..' native evolution updates species/stats')
  party[#party+1]=mon
 end
 local def=Game.data.pokemon.KADABRA;local original=def.evolutions
 def.evolutions={{method='TRADE',species='ALAKAZAM'}}
 check(Guide.text(Game,{species='KADABRA'}):find('151ひき',1,true)~=nil,'disabled 151 rules show how to enable the existing MOD')
 def.evolutions=original
 local items={{action='stats'},{action='cancel'}};local menu={game=Game}
 Guide.addEntry(menu,items,{species='KADABRA'});Guide.addEntry(menu,items,{species='KADABRA'})
 check(#items==3 and items[2].id=='jpEvolutionGuide','one guide entry before cancel')
 local partyMenu=require('src.ui.PartyMenu').new(Game,{party={}})
 partyMenu.submenu=true;partyMenu.subItems={}
 for i=1,9 do partyMenu.subItems[i]={label='ACTION'..i}end
 local Font=require('src.render.Font');local drawText=Font.draw
 local c=g.newCanvas(160,160)
 for _,selected in ipairs({1,9})do
  local drawn={};Font.draw=function(text,x,y,...)
   if text:match('^ACTION') then drawn[#drawn+1]={text,y}end
   return drawText(text,x,y,...)
  end
  partyMenu.subIndex=selected;g.setCanvas(c);partyMenu:draw();g.setCanvas();Font.draw=drawText
  local found=false;for _,row in ipairs(drawn)do if row[1]=='ACTION'..selected then found=true end end
  check(#drawn==8 and drawn[1][2]>=16 and drawn[#drawn][2]<=128 and found,'extra evolution/MOD actions scroll within the party window '..selected)
 end
 c:release()
 Guide.addEntry({game=Game,battle=true},{},{species='KADABRA'})
 local save=Save.newGame({version='red_jp',playerName='ヨシダ',startMap='ROUTE_3',startX=9,startY=6})
 save.party=party;save.boxes={{party[1]},{party[2]}};save.money=54321;save.playTime=37260
 save.inventory={POTION=17};save.flags.TEST_PROGRESS=true
 save.modData={SHINY_POKEMON={example={17,'preserve'}}};save.party[1].jpFollowerIdentity=19;save.jpFollowerIdentity=19
 local first=assert(Save.createSlot('red_jp'));Save.writeSlot('red_jp',first,save);Save.setActiveSlot('red_jp',first)
 local firstPath='saves/red_jp/'..first..'.lua';local kept=fs.read(firstPath)
 local opts=Save.loadOptions();opts.jpAutoSave=false;opts.jpTouchStick=false
 opts.modOptions.DRAMALESS_SHAPE.weather='snow';opts.modOptions.DRAMALESS_SHAPE.weatherLightning=false
 assert(Save.saveOptions(opts))
 local IO=require('src.import.SaveFileIO');local Transfer=require('src.import.JapaneseSaveTransfer')
 local ok,path=IO.exportActiveSlot('red_jp');check(ok,'native JP export works through the actual SaveFileIO: '..tostring(path))
 local exported=assert(fs.read(path:match('(exports/.+)$')))
 local document=assert(Transfer.decode(exported))
 check(S.encode(document.save.party)==S.encode(party),'backup preserves party, moves, DV/PP/custom follower fields')
 check(S.encode(document.save.boxes)==S.encode(save.boxes),'backup preserves all PC boxes')
 check(document.save.modData.SHINY_POKEMON.example[2]=='preserve','backup preserves custom MOD save data')
 local beforeOptions=fs.read('options.lua')
 for _,bad in ipairs({exported:sub(1,-2),exported:gsub('54321','54322'),string.rep('a',32768)})do
  check(not IO.importToSlot(bad,'red_jp'),'damaged/foreign backup rejected')
  check(fs.read(firstPath)==kept and fs.read('options.lua')==beforeOptions,'failed import leaves current progress and options unchanged')
 end
 check(not IO.importToSlot(exported,'red'),'JP backup rejected for another game')
 local malicious='return { save = os.execute("false") }'
 local digest=love.data.encode('string','hex',love.data.hash('sha256',malicious))
 check(not Transfer.decode(Transfer.MAGIC..digest..'\n'..malicious),'even a correctly checksummed backup cannot execute code')
 local nativeWrite=fs.write;local failOnce=true
 fs.write=function(n,b,...)
  if n=='options.lua' and failOnce then failOnce=false;nativeWrite(n,'partial');return nil,'fixture full disk' end
  return nativeWrite(n,b,...)
 end
 local result=IO.importToSlot(exported,'red_jp');fs.write=nativeWrite
 check(not result and fs.read('options.lua')==beforeOptions,'partial settings write rolls back the registry')
 check(fs.read(firstPath)==kept,'failed import never targets the existing slot')
 local yes,second=IO.importToSlot(exported,'red_jp')
 check(yes and second~=first,'backup imports into a fresh slot')
 check(Save.activeSlot('red_jp')==second,'new slot becomes the Continue target only after successful commit')
 local restored=assert(Save.load('red_jp'))
 check(restored.money==54321 and restored.flags.TEST_PROGRESS and restored.player.map=='ROUTE_3','progress and saved position round trip')
 check(S.encode(restored.party)==S.encode(party) and restored.jpFollowerIdentity==19,'native load preserves party and selected follower')
 check(not restored.options.jpAutoSave and not restored.options.jpTouchStick,'explicit autosave and touch OFF choices round trip')
 check(restored.options.modOptions.DRAMALESS_SHAPE.weather=='snow' and not restored.options.modOptions.DRAMALESS_SHAPE.weatherLightning,'weather choices round trip')
 check(fs.read(firstPath)==kept,'successful import preserves the original slot byte for byte')
 local Imp=require('src.import.RomImporter');local View=require('src.import.LauncherView')
 local launched,request=0
 local imp=Imp.new(function(id,cart,o)launched=launched+1;request=o;check(id=='red_jp' and cart==nil,'home launches the selected game')end,{launcher=true})
 imp.ready.red_jp=true;imp.tab='red_jp'
 local function render(w,h,name)
  love.window.setMode(w,h,{resizable=true});imp._ui.page='games';imp._ui.focus=1
  local c=g.newCanvas(w,h);g.setCanvas(c);imp:draw();g.setCanvas()
  write(name..'.png',c:newImageData():encode('png'):getString());c:release()
  check(#imp._ui.rows==6,'home has six separated choices '..w..'x'..h)
  check(imp._ui.sheets==1,'home fits on one page '..w..'x'..h)
  local rect=imp._ui.layout
  for _,hit in ipairs(imp._ui.hits)do
   check(hit.x>=0 and hit.y>=0 and hit.x+hit.w<=w and hit.y+hit.h<=h,'home target fits '..hit.id)
  end
  check(imp._ui.rows[1].label:find('つづきから',1,true) and imp._ui.rows[1].label:find('ヨシダ',1,true),'Continue card includes saved trainer')
  check(imp._ui.rows[1].label:find('3ばんどうろ',1,true) and imp._ui.rows[1].label:find('10:21',1,true),'Continue card shows saved place and time')
 end
 for _,size in ipairs({{320,480},{480,800},{800,480},{972,1536},{1536,1160}})do render(size[1],size[2],'home-'..size[1]..'x'..size[2])end
 local hit
 for _,h in ipairs(imp._ui.hits)do if h.id=='play' then hit=h end end
 local x,y=hit.x+hit.w/2,hit.y+hit.h/2
 imp:touchpressed(43,x,y);imp:touchreleased(43,x,y);imp:mousepressed(x,y,1)
 check(launched==1 and request.jpContinue,'one tap hands off a direct Continue request, including synthesized mouse filtering')
 local Home=require('src.import.JapaneseHome');local restoredByHome
 local stub={restoreSave=function(_,s,recovery,o)restoredByHome={save=s,options=o}end}
 check(Home.restore(stub) and restoredByHome.save.player.map=='ROUTE_3' and restoredByHome.options.continued,'home uses normal native restore semantics')
 local empty=assert(Save.createSlot('red_jp'));imp:_selectSlot('red_jp',empty)
 check(Home.summary(imp,'red_jp')==nil,'empty slot never pretends to be Continue')
 check(not Home.restore(stub),'empty slot cannot load another slot silently')
 Save.setActiveSlot('red_jp',second)
 imp:_refreshSlots('red_jp');imp._ui.page='saves';imp._ui.focus=1
 local transferCanvas=g.newCanvas(480,800);love.window.setMode(480,800);g.setCanvas(transferCanvas);imp:draw();g.setCanvas()
 write('save-transfer-menu.png',transferCanvas:newImageData():encode('png'):getString());transferCanvas:release()
 local actions={};for _,row in ipairs(imp._ui.rows)do actions[row.id]=row end
 check(actions['export-save'] and actions['import-save'] and actions['save-help'],'home save page exposes transfer and its instructions')
 local nativeCreate=love.system.createFile;local suggested
 love.system.createFile=function(name)suggested=name;return true end
 actions['export-save'].action();love.system.createFile=nativeCreate
 check(suggested and Transfer.matches(fs.read('pending_export.sav')),'Android export stages the native backup through the existing document picker')
 imp:_importSave('red_jp',exported)
 check(imp.saveNotice.red_jp.ok and imp.activeSlot.red_jp~=second,'launcher import refreshes the selected slot and success notice')
 Save.setActiveSlot('red_jp',second)
 -- Backup fallback is still available to direct Continue.
 local current=Save.saveFilename('red_jp');fs.write(current..'.bak',fs.read(current));fs.write(current,'incomplete')
 check(Home.restore(stub) and restoredByHome.save.money==54321,'direct Continue recovers a truncated main file from the native backup')
 require('tests.jp44_startup')(Game,Renderer,check,write,imp,second,kept,firstPath)
 write('product.json',require('src.link.Json').encode({romUsed=false,nativeBackup=true,directContinue=true,evolutionLevels={42,42,42,45}}))
end
