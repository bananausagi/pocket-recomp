-- SPDX-License-Identifier: GPL-3.0-only
-- Independent launcher. Original geometry; no upstream launcher UI or artwork.
-- Every glyph remains 8px; controller lists use the available columns/rows.
local View = {}
View.CREDIT = "Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC (https://github.com/bryanthaboi/gen1recomp)"
local Classic = require("src.ui.ClassicUI")
local GameVersion = require("src.core.GameVersion")
local SafeArea = require("src.core.SafeArea")
local SaveData = require("src.core.SaveData")
local UIStrings = require("src.ui.JapaneseUIStrings")
local GameUILayout = require("src.ui.GameUILayout")
local ROWS = 5
local raisedKana={}
for ch in ("がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽガギグゲゴザジズゼゾダヂヅデドバビブベボパピプペポヴ"):gmatch("[%z\1-\127\194-\244][\128-\191]*")do raisedKana[ch]=true end
local function raised(text)
  for ch in tostring(text or""):gmatch("[%z\1-\127\194-\244][\128-\191]*")do if raisedKana[ch]then return true end end
  return false
end
local function state(imp)
  imp._ui = imp._ui or {page="games",scroll=0,focus=1,hits={}}
  local ui=imp._ui
  ui.options=ui.options or SaveData.loadOptions()
  ui.page=ui.page or "games"
  ui.focus=ui.focus or 1
  ui.sheet=ui.sheet or 1
  return ui
end
local function lang(imp,ja,en)
  local ui=state(imp)
  local opts=imp._settings and imp._settings.opts or ui.options
  return opts and opts.jpLauncherLanguage=="en" and en or ja
end
local function translated(imp,text)
  local ui=state(imp)
  local opts=imp._settings and imp._settings.opts or ui.options
  return UIStrings.lookup(text,opts and opts.jpLauncherLanguage)
end
local function translatedStatus(imp,text)
  text=tostring(text or "")
  if lang(imp,false,true) then return text end
  local required,current=text:match("^Needs engine (.+) %(current (.+)%)$")
  if required then return UIStrings.format("Needs engine %s (current %s)",nil,required,current) end
  local target,excluded=text:match("^For (.+), not (.+)$")
  if target then return UIStrings.format("For %s, not %s",nil,target,excluded) end
  local name=text:match("^Conflicts with (.+)$")
  if name then return UIStrings.format("Conflicts with %s",nil,translated(imp,name)) end
  name=text:match("^Forced onto (.+)$")
  if name then return UIStrings.format("Forced onto %s",nil,name) end
  local need,reason=text:match("^Needs (.-) %((.+)%)$")
  if need then
    local game=reason:match("^not for (.+)$")
    reason=game and UIStrings.format("not for %s",nil,game) or translated(imp,reason)
    return UIStrings.format("Needs %s (%s)",nil,need,reason)
  end
  return translated(imp,text)
end
local function saveSettings(imp)
  local ui=state(imp)
  if imp._settings then imp._settings.save();ui.options=imp._settings.opts;imp._settings=nil end
end
local parent={more="games",library="more",saves="games",cloud="saves",["save-detail"]="saves",about="more",license="about",mods="more",["mod-list"]="mods",["mod-detail"]="mod-list",discover="mods",settings="games",["settings-detail"]="settings"}
local function open(imp,page)
  local ui=state(imp)
  if page~="settings" and page~="settings-detail" then saveSettings(imp)end
  ui.page,ui.sheet,ui.focus,ui.scroll=page,1,1,0
  if page=="settings"then ui.settingsChild=nil end
  ui.pressedId=nil;ui.touch=nil;ui.rows=nil;ui.focusHit=nil;ui.pageRanges=nil
  if page=="mods" then imp:_refreshMods()end
end
local function back(imp)
  require("src.import.SettingsFiles").cancel()
  local ui=state(imp)
  if ui.edit then ui.edit=nil;if love.keyboard.setTextInput then love.keyboard.setTextInput(false)end
  elseif imp._modConfirm then imp._modConfirm=nil
  elseif ui.page=="settings-detail"then
    local section,child=ui.settingsSection,ui.settingsChild
    if child then
      local group=imp._settings and imp._settings.sections[section]
      ui.settingsChild=nil;open(imp,"settings-detail");ui.focus=#(group and group.rows or{})+child
    else open(imp,"settings");ui.focus=section or 1 end
  elseif ui.page=="message" then open(imp,ui.messageParent or "games")
  elseif ui.page=="games" then open(imp,"more")
  else open(imp,parent[ui.page] or "games")end
end
local function message(imp,title,body)
  local ui=state(imp)
  ui.messageParent=ui.page
  ui.messageTitle,ui.messageBody=title,tostring(body or "")
  open(imp,"message")
end
function View.showMessage(imp,title,body) return message(imp,title,body) end
local function gameName(imp,id)
  local names={red_jp={"あか にほんご","RED / JAPANESE"},red={"あか えいご","RED / ENGLISH"},blue={"あお えいご","BLUE / ENGLISH"},yellow={"ピカチュウ えいご","YELLOW / ENGLISH"},gold={"きん えいご","GOLD / ENGLISH"},silver={"ぎん えいご","SILVER / ENGLISH"},crystal={"クリスタル えいご","CRYSTAL / ENGLISH"},firered={"ファイアレッド","FIRE RED"}}
  names.gold_jp={"きん にほんご（けんしょうばん）","GOLD / JAPANESE BETA"}
  names.silver_jp={"ぎん にほんご（けんしょうばん）","SILVER / JAPANESE BETA"}
  names.crystal_jp={"クリスタル にほんご（けんしょうばん）","CRYSTAL / JAPANESE BETA"}
  local n=names[id];return n and lang(imp,n[1],n[2]) or tostring(id)
end
local function item(rows,id,label,action,value,step)
  rows[#rows+1]={id=id,label=label,action=action,value=value,step=step}
end
local function noticeRow(imp,rows,notice,id)
  if notice then
    local body=notice.text or (tostring(notice.status or "").."\n"..tostring(notice.detail or ""))
    item(rows,id,lang(imp,"おしらせ","NOTICE"),function()message(imp,lang(imp,"おしらせ","NOTICE"),body)end)
  end
end
local modNames={DRAMALESS_SHAPE="Dramaless Shape",running_shoes="Running Shoes",erilab_bottomless_bag="Bottomless Bag",SHINY_POKEMON="Shiny Pokemon",ACCESS_PC_ANYWHERE="PC Anywhere",CONTROLLER_RUMBLE="Controller Rumble"}
local function model(imp)
  local ui=state(imp);local rows={};local page=ui.page
  local id=GameVersion.VERSIONS[imp.tab] and imp.tab or "red_jp"
  imp.tab=id;imp.modScope=id
  local title,subtitle=lang(imp,"ホーム","HOME"),nil
  if page=="games" then
    local brand=require('src.core.Version')
    title=lang(imp,brand.appName,brand.appNameEn);subtitle=id~='red_jp' and gameName(imp,id) or nil
    if imp.ready[id] then
      local summary=require('src.import.JapaneseHome').summary(imp,id)
      local label=id=='red_jp' and lang(imp,'つづきから','CONTINUE') or lang(imp,'ゲームを はじめる','PLAY GAME')
      if summary then
        label=label..'\n'..summary.name..' / '..summary.time
        label=label..'\n'..lang(imp,summary.place or ('バッジ '..summary.badges..'こ'),summary.badges..' BADGES')
      elseif id=='red_jp' then label=label..'\n'..lang(imp,'レポートが ありません','NO SAVE IN THIS SLOT') end
      item(rows,'play',label,function()
        if id~='red_jp' or summary then imp:play(id,{jpContinue=id=='red_jp'}) end
      end)
      rows[#rows].disabled=id=='red_jp' and not summary
      if id=='red_jp' then
        item(rows,'new-game',lang(imp,'はじめから','NEW GAME'),function()imp:play(id,{jpNewGame=true})end)
        rows[#rows].card=true
        item(rows,'open-title',lang(imp,'タイトルへ','OPEN TITLE'),function()imp:play(id)end)
        rows[#rows].card=true
      end
    else
      item(rows,"rom",lang(imp,"ROMを よみこんで はじめる","IMPORT ROM TO PLAY"),function()imp:choose(id)end)
    end
    if imp.workState=="working"then rows[1].label=lang(imp,"よみこみを まってね","PLEASE WAIT FOR IMPORT")end
    if imp.ready[id] then
      item(rows,"saves",lang(imp,"セーブと いこう","SAVES"),function()open(imp,"saves")end)
      rows[#rows].section=true
    end
    item(rows,"home-settings",lang(imp,"せってい","SETTINGS"),function()open(imp,"settings")end)
    item(rows,"home-more",lang(imp,"そのほか","MORE"),function()open(imp,"more")end)
  elseif page=="more" then
    title=lang(imp,"そのほか","MORE")
    item(rows,"home-mods","MOD",function()open(imp,"mods")end)
    item(rows,"game-select",lang(imp,"ゲームを えらぶ","SELECT GAME"),function()open(imp,"library")end)
    item(rows,"rom",lang(imp,"ROMを よみこむ","IMPORT ROM"),function()imp:choose(id)end)
    item(rows,"home-about",lang(imp,"このアプリについて","ABOUT"),function()open(imp,"about")end)
    item(rows,"quit",lang(imp,"アプリを おわる","QUIT"),function()imp:_quitApp()end)
  elseif page=="library" then
    title=lang(imp,"ゲームを えらぶ","SELECT GAME")
    local order={"red_jp"};for _,v in ipairs(GameVersion.ORDER)do if v~="red_jp"then order[#order+1]=v end end
    for _,version in ipairs(order)do
      item(rows,"game-"..version,(imp.ready[version]and "*"or " ")..gameName(imp,version),function()imp:_switchTab(version);imp.mods=nil;ui.sheet=1 end)
    end
  elseif page=="saves" then
    title=lang(imp,"レポート","SAVE DATA")
    item(rows,"new-save",lang(imp,"あたらしい レポート","NEW SAVE SLOT"),function()imp:_newSlot(id)end)
    if id~="red_jp"then
      item(rows,"import-save",lang(imp,".savを よみこむ","IMPORT .sav"),function()imp:chooseSaveImport(id)end)
      item(rows,"export-save",lang(imp,".savを かきだす","EXPORT .sav"),function()imp:exportSave(id)end)
    else
      item(rows,'cloud-save',lang(imp,'クラウドに ほぞん・ふくげん','CLOUD BACKUP / RESTORE'),function()open(imp,'cloud')end)
      item(rows,'export-save',lang(imp,'バックアップを かきだす','EXPORT BACKUP'),function()imp:exportSave(id)end)
      item(rows,'import-save',lang(imp,'バックアップを よみこむ','IMPORT BACKUP'),function()imp:chooseSaveImport(id)end)
      item(rows,'save-help',lang(imp,'データいこうの つかいかた','TRANSFER HELP'),function()message(imp,lang(imp,'データいこう','SAVE TRANSFER'),lang(imp,'APKは アンインストールせず\nうわがきで こうしんしてね。\nレポートは そのまま つかえます。\n\nべつの たんまつへ うつすには\nバックアップを かきだして\nあたらしい たんまつで よみこみます。\n\nせんたくちゅうの レポートと\nせっていを まとめて うつします。\nもとの セーブは けしません。\n\nこのアプリ せんようです。\nカセットの .savとは ちがいます。','Update the APK in place to keep saves.\n\nExport the selected slot and settings, then import the backup on the other device. Import creates a new slot and keeps existing saves.\n\nThis is a Pocket Recomp backup (also accepts Kanto Player JP), not a cartridge .sav.'))end)
    end
    imp:_ensureSlots(id)
    for _,slot in ipairs(imp.slots[id]or{})do
      local sid=slot.id or slot.slotId
      item(rows,"save-"..tostring(sid),(imp.activeSlot[id]==sid and "*"or" ")..tostring(slot.label or slot.name or sid),function()ui.slotId=sid;ui.slotName=tostring(slot.label or slot.name or sid);open(imp,"save-detail")end)
    end
    noticeRow(imp,rows,imp.saveNotice[id],"save-notice")
  elseif page=='cloud' then
    title=lang(imp,'クラウド バックアップ','CLOUD BACKUP')
    subtitle=lang(imp,'ファイルを えらんで ほぞん','MANUAL FILE BACKUP')
    item(rows,'cloud-export',lang(imp,'Driveなどに ほぞん','SAVE TO DRIVE / FILES'),function()imp:exportSave(id,{cloud=true})end)
    item(rows,'cloud-import',lang(imp,'クラウドから ふくげん','RESTORE FROM CLOUD'),function()imp:chooseSaveImport(id)end)
    item(rows,'cloud-help',lang(imp,'つかいかた','HOW TO USE'),function()
      message(imp,title,lang(imp,
        'ほぞんさきの がめんで\nメニューから Google Driveを\nえらんでください。\n\nDriveが でないときは\nDriveアプリで ログインしてね。\n\nひづけつきの ファイルを\nあたらしく ほぞんします。\nべつの たんまつでは\nそのファイルを よみこみます。\n\nふくげんは あたらしい\nレポートに おこないます。\nもとの レポートは のこります。\n\nこれは しゅどうの ほぞんです。\nGoogleログインによる\nじどう どうきは まだ ありません。',
        'In the system file picker, open its menu and choose Google Drive. If Drive is missing, install the Drive app and sign in there.\n\nSave a new dated file. On another device, select Restore from cloud and choose that file.\n\nRestore creates a new slot and keeps existing reports.\n\nThis is manual backup. Automatic Google account sync is not available yet.'))
    end)
    noticeRow(imp,rows,imp.saveNotice[id],'cloud-notice')
  elseif page=="save-detail"then
    title=lang(imp,"レポート","SAVE SLOT");subtitle=ui.slotName
    item(rows,"select-save",lang(imp,"このレポートを つかう","USE THIS SAVE"),function()imp:_selectSlot(id,ui.slotId);open(imp,"games")end)
    if imp.onEditSave then item(rows,"edit-save",lang(imp,"へんしゅうする","EDIT SAVE"),function()imp.onEditSave(id,ui.slotId)end)end
  elseif page=="mods"then
    title="MOD";subtitle=gameName(imp,id)
    item(rows,"mod-list",lang(imp,"MODを えらぶ","INSTALLED MODS"),function()open(imp,"mod-list")end)
    item(rows,"mod-import",lang(imp,"ZIPを よみこむ","IMPORT ZIP"),function()imp:chooseMod()end)
    item(rows,"mod-discover",lang(imp,"MODを さがす","FIND MODS"),function()open(imp,"discover")end)
    noticeRow(imp,rows,imp.modNotice,"mod-notice");noticeRow(imp,rows,imp.requiredImportNotice,"required-notice")
  elseif page=="mod-list"then
    title=lang(imp,"MODを えらぶ","INSTALLED MODS")
    imp:_ensureMods()
    for _,mod in ipairs(imp.mods)do
      local mid=mod.id
      item(rows,"mod-"..mid,(mod.enabled and "+ "or"- ")..(modNames[mid]or mod.name or mid),function()ui.modId=mid;open(imp,"mod-detail")end)
    end
    if #rows==0 then subtitle=lang(imp,"MODは ありません","NO MODS INSTALLED")end
  elseif page=="mod-detail"then
    imp:_ensureMods();local mod
    for _,m in ipairs(imp.mods)do if m.id==ui.modId then mod=m;break end end
    title="MOD"
    if mod then
      subtitle=modNames[mod.id]or mod.name or mod.id
      item(rows,"toggle-"..mod.id,lang(imp,mod.enabled and "つかう: はい"or"つかう: いいえ",mod.enabled and "ENABLED: YES"or"ENABLED: NO"),function()imp:_toggleMod(mod.id)end)
      item(rows,"mod-info",lang(imp,"せつめいを よむ","DESCRIPTION"),function()message(imp,translated(imp,mod.name or mod.id),table.concat({translated(imp,mod.name or mod.id),tostring(mod.version or""),translated(imp,mod.description or""),translatedStatus(imp,mod.statusDetail or mod.reason or mod.status or"")},"\n"))end)
      for _,spec in ipairs(require("src.mods.RequiredImports").specs(mod.manifest or{}))do
        item(rows,"required-"..mod.id.."-"..spec.id,translated(imp,spec.label or spec.id),function()imp:chooseRequiredImport(mod.id,spec.id)end)
      end
    else subtitle=lang(imp,"MODが みつかりません","MOD NOT FOUND")end
  elseif page=="settings"or page=="settings-detail"then
    if not imp._settings then imp:_openSettings();ui.page=page end
    local settings=imp._settings
    title=lang(imp,"せってい","SETTINGS")
    if page=="settings-detail"and settings.sections[ui.settingsSection or 0]then
      local section=settings.sections[ui.settingsSection]
      if ui.settingsChild then section=(section.children or{})[ui.settingsChild]or section end
      title=section.title
      for n,row in ipairs(section.rows)do
        local label=row.label
        local key="setting-"..ui.settingsSection.."-"..n
        local value=row.value and tostring(row.value())or""
        if row.step then
          item(rows,key,label,function()row.step(1);settings.save()end,value,function(delta)row.step(delta);settings.save()end)
        elseif row.setText then
          item(rows,key,label,function()ui.edit={row=row,text=value,model=settings};if love.keyboard.setTextInput then love.keyboard.setTextInput(true)end end,value)
        elseif row.action then
          item(rows,key,label,function()row.action();if imp._settings==settings then settings.save()end end,
            row.actionLabel or lang(imp,"ひらく","Open"))
        else item(rows,key,label,function()message(imp,label,value)end,value)end
        rows[#rows].description=row.descriptionFor and row.descriptionFor() or row.description or row.help or section.description
        rows[#rows].optionId=row.id
      end
      for n,child in ipairs(section.children or{})do
        item(rows,"settings-mod-"..n,child.title,function()ui.settingsChild=n;open(imp,"settings-detail")end)
        rows[#rows].category=true
        rows[#rows].description=child.description
      end
    else
      ui.page="settings"
      for n,section in ipairs(settings.sections)do
        item(rows,"settings-section-"..n,section.title,function()ui.settingsSection=n;ui.settingsChild=nil;open(imp,"settings-detail")end)
        rows[#rows].category=true
        rows[#rows].description=section.description
      end
      for n,warning in ipairs(settings.warnings or{})do item(rows,"settings-warning-"..n,lang(imp,"おしらせ","NOTICE"),function()message(imp,title,tostring(warning))end)end
    end
  elseif page=="discover"then
    title=lang(imp,"MODを さがす","FIND MODS")
    item(rows,"qol-release","Quality of Life",function()love.system.openURL("https://github.com/unxpected-uxp/pokemon-gen1-recomp-mod-qol/releases/tag/v1.3.0")end)
    item(rows,"catchable-source","Catchable 151",function()love.system.openURL("https://github.com/wowabox/All_Pokemon_Catchable_151_Mod")end)
    item(rows,"upstream-repo",lang(imp,"もとの プロジェクト","ORIGINAL PROJECT"),function()love.system.openURL("https://github.com/bryanthaboi/gen1recomp")end)
    item(rows,"mod-help",lang(imp,"MODの いれかた","INSTALL HELP"),function()message(imp,lang(imp,"MODの いれかた","INSTALL HELP"),lang(imp,"さくしゃの ページから\nZIPを ほぞんして\nよみこんでください。\n\nQuality of Lifeは\nゲームの せっていで\nきのうを ONにします。\n\nMODは ゲームの しゅるいで\nうごかない ことがあります。","Save the release ZIP from its author and import it here.\n\nFor Quality of Life, enable its features in the game settings.\n\nCompatibility depends on the game and region."))end)
    for n,source in ipairs(SaveData.loadOptions().modIndexes or{})do
      local url=type(source)=="string"and source or source.base or source.feed
      if type(url)=="string"and url:match("^https?://")then item(rows,"index-"..n,type(source)=="table"and source.label or url,function()love.system.openURL(url)end)end
    end
  elseif page=="about"then
    title=lang(imp,"このアプリについて","ABOUT")
    subtitle=require("src.core.Version").distribution
    item(rows,"about-info",lang(imp,"このバージョン","THIS VERSION"),function()message(imp,require("src.core.Version").appName,tostring(require("src.core.Version").distribution).."\n\n"..lang(imp,"にほんご ROMに たいおうした\nひこうしきの かいへんばんです。\n\nゲームデータは\nはいっていません。\n\nオンライン たいせん・こうかん\nクラウド どうき\nスキンの よみこみ\nMODの じどう こうしんは\nまだ たいおうしていません。","Unofficial modified version with Japanese ROM support. Game data is not included.\n\nOnline play, cloud sync, skin import and automatic mod updates are unavailable."))end)
    item(rows,"license",lang(imp,"ライセンス","LICENSE"),function()open(imp,"license")end)
    item(rows,"attribution",lang(imp,"クレジット","CREDITS"),function()message(imp,lang(imp,"クレジット","CREDITS"),View.CREDIT)end)
    item(rows,"quit",lang(imp,"アプリを おわる","QUIT"),function()imp:_quitApp()end)
  end
  if page=="games"or page=="more"then
    if imp.workState=="working"then subtitle=lang(imp,"よみこみちゅう ","IMPORTING ")..math.floor(100*(imp.progress or 0)).."%"
    elseif imp.workState=="error"then noticeRow(imp,rows,{text=imp.detail},"import-error")end
    noticeRow(imp,rows,imp.notice,"import-notice")
  end
  return {title=tostring(title or""),subtitle=subtitle,rows=rows}
end
local function invoke(imp,hit)
  if not hit or hit.disabled or not hit.action or imp.workState=="working"then return end
  local ok,err=pcall(hit.action)
  if not ok then message(imp,lang(imp,"エラー","ERROR"),tostring(err))end
end
local function rectContains(r,x,y)return x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h end
local function addHit(ui,id,x,y,w,h,action,row)
  local l=ui.layout;local sx=l.sx or l.scale;local sy=l.sy or l.scale
  ui.hits[#ui.hits+1]={id=id,x=l.x+x*sx,y=l.y+y*sy,w=w*sx,h=h*sy,lx=x,ly=y,lw=w,lh=h,action=action,row=row,body=true}
end
local function text(str,x,y,w,align)
  return Classic.text(tostring(str or""),x,y,{width=w or 144,clip=true,align=align or"left",color={0,0,0,1}})
end
local function focusPage(ui)
  for n,p in ipairs(ui.pageRanges or{})do
    if ui.focus>=p.first and ui.focus<=p.last then return n end
  end
  return math.floor((ui.focus-1)/math.max(1,ui.pageRows or ROWS))+1
end
local function sheet(imp,delta)
  local ui=state(imp)
  ui.sheet=math.max(1,math.min(ui.sheets or 1,ui.sheet+delta))
  local page=ui.pageRanges and ui.pageRanges[ui.sheet]
  ui.focus=page and page.first or (ui.sheet-1)*(ui.pageRows or ROWS)+1
  ui.scroll=ui.focus-1
end
local function footer(imp)
  local ui=state(imp)
  if ui.panel then
    local p=ui.panel;local y=p.height-p.tap-8
    local baseline=y+math.floor((p.tap-8)/16)*8
    local navX=p.width-16-p.tap*2-40
    local home=ui.page=="games"
    local leftW=(ui.sheets or 1)>1 and navX-24 or p.width-32
    if home then
      if (ui.sheets or 1)==1 then
        Classic.text(require("src.core.Version").distribution,16,baseline,
          {width=p.width-32,align='center',color={.38,.43,.4,1}})
      end
    else
      text(lang(imp,"もどる","BACK"),16,baseline,leftW)
      addHit(ui,"page-back",16,y,leftW,p.tap,function()back(imp)end)
    end
    if (ui.sheets or 1)>1 then
      text("<",navX+math.floor((p.tap-8)/16)*8,baseline,8)
      text(ui.sheet.."/"..ui.sheets,navX+p.tap,baseline,40,"center")
      text(">",p.width-16-p.tap+math.floor((p.tap-8)/16)*8,baseline,8)
      addHit(ui,"page-prev",navX,y,p.tap,p.tap,function()sheet(imp,-1)end)
      addHit(ui,"page-next",p.width-16-p.tap,y,p.tap,p.tap,function()sheet(imp,1)end)
    end
    return
  end
  if ui.page~="games"then
    text(lang(imp,"もどる","BACK"),16,128,48)
    addHit(ui,"page-back",8,120,64,16,function()back(imp)end)
  else
    text(lang(imp,"けってい","SELECT"),16,128,64)
    addHit(ui,"activate",8,120,72,16,function()invoke(imp,ui.focusHit)end)
  end
  if (ui.sheets or 1)>1 then
    text("<",96,128,8);text(">",136,128,8)
    local pageLabel=tostring(ui.sheet).."/"..tostring(ui.sheets)
    if Classic.width(pageLabel)>32 then pageLabel=tostring(ui.sheet)end
    text(pageLabel,104,128,32)
    addHit(ui,"page-prev",88,120,32,16,function()sheet(imp,-1)end)
    addHit(ui,"page-next",120,120,32,16,function()sheet(imp,1)end)
  end
end
local function listPanel(imp,rect)
  local ui=state(imp);local menu=model(imp)
  local options=imp._settings and imp._settings.opts or ui.options
  local home=ui.page=="games"
  local minimum=home and (rect.w>rect.h and 192 or 256) or 128
  local m=GameUILayout.panelMetrics({save={options=options}},{rect=rect,minHeight=minimum})
  local columns=home and m.width>=208 and 2 or 1
  local split=home and not m.portrait and m.width>=320 and menu.rows[2] and menu.rows[2].id=='new-game'
  local colW=math.floor((m.width-32-(columns-1)*16)/columns/8)*8
  local tap=home and (m.portrait and 24 or 16) or 12
  local line=home and 16 or 12
  local wide=m.width>=192
  local hasValues=false
  for _,row in ipairs(menu.rows)do if row.value~=nil then hasValues=true;break end end
  local labelW=hasValues and wide and math.floor((m.width-64)*0.58/8)*8 or colW-8
  local valueX=wide and 24+labelW+8 or 24
  local valueW=m.width-16-valueX
  local bodyY=home and (menu.subtitle and 72 or 56) or (menu.subtitle and 56 or 40)
  local footerGap=home and 8 or 16 -- Back's voiced mark stays above its baseline.
  local help,helpHeight
  if not home then
    local focused=menu.rows[math.max(1,math.min(ui.focus,#menu.rows))]
    if focused and focused.description and not focused.category then
      help=Classic.wrap(tostring(focused.description):gsub("\n"," "),m.width-32)
      local lines=m.height<240 and 1 or 2
      if #help>lines then
        help[lines]=Classic.clip(table.concat(help,"",lines),m.width-32)
        while #help>lines do table.remove(help)end
      end
      helpHeight=lines*16+8;footerGap=footerGap+helpHeight
    end
  end
  local capacity=m.height-bodyY-tap-footerGap
  local rowH=home and m.portrait and math.max(16,math.ceil((m.height*.60-bodyY-tap-8)/math.max(1,#menu.rows)/4)*4)or tap
  local labels={}
  for i,row in ipairs(menu.rows)do
    local pad=not home and imp.tab=="red_jp"and imp.ready.red_jp
      and (raised(row.label)or raised(row.value))and 4 or 0
    local rowLine=pad>0 and 16 or line
    local primary=home and i==1
    local card=primary or row.card
    local rowLabelW=primary and (split and colW-40 or m.width-72) or row.card and colW-40 or labelW
    local rowValueX,rowValueW,sameLine=valueX,valueW,wide
    if not home and row.value==nil then rowLabelW=m.width-40
    elseif not home then
      local need=math.max(24,Classic.width(row.value)+(row.step and 2*tap or 0))
      if Classic.width(row.label)+need<=m.width-48 then
        sameLine=true;rowLabelW=m.width-48-need
        rowValueX=24+rowLabelW+8;rowValueW=need
      end
    end
    local label=Classic.wrap(row.label,rowLabelW)
    local value=row.value~=nil and Classic.wrap(row.value,rowValueW-(row.step and tap*2 or 0)) or nil
    local lines=value and (sameLine and math.max(#label,#value) or #label+#value) or #label
    local height=math.max(rowH,pad+(lines-1)*rowLine+line)
    if primary then pad=16;height=math.max(32,16+#label*line)end
    if row.card then pad=8;height=math.max(32,16+#label*line)end
    while height>capacity and (#label>1 or value and #value>1)do
      local list=value and #value>#label and value or label
      local last=table.remove(list)
      list[#list]=Classic.clip(list[#list]..last,list==label and rowLabelW or rowValueW-(row.step and tap*2 or 0))
      lines=value and (sameLine and math.max(#label,#value) or #label+#value) or #label
      height=math.max(rowH,pad+(lines-1)*rowLine+line)
    end
    labels[i]={label=label,value=value,h=height,pad=pad,line=rowLine,labelW=rowLabelW,primary=primary,card=card,
      valueX=rowValueX,valueW=rowValueW,wide=sameLine}
  end
  local pages={{first=1,last=0,height=0}}
  local first=1
  if split then
    local height=math.max(labels[1].h,labels[2].h+labels[3].h+8)
    labels[1].x,labels[1].y,labels[1].w,labels[1].h=16,bodyY,colW,height
    for i=2,3 do
      labels[i].x=32+colW;labels[i].y=bodyY+(i==3 and labels[2].h+8 or 0);labels[i].w=colW
    end
    pages[1].last,pages[1].height=3,height
    first=4
  end
  while first<=#menu.rows do
    -- The first home action owns a full row, independently of the management
    -- grid below it. It keeps the same action ID and bitmap font as before.
    local primary=home and first==1
    local last=math.min(#menu.rows,first+(primary and 1 or columns)-1)
    -- Keep game actions and save/settings management in separate rows.
    for i=first+1,last do if menu.rows[i].section then last=i-1;break end end
    local rh=0;for i=first,last do rh=math.max(rh,labels[i].h)end
    local page=pages[#pages]
    local gap=menu.rows[first].section and 8 or 0
    if page.height+rh+gap>capacity and page.last>=page.first then
      page={first=first,last=first-1,height=0};pages[#pages+1]=page
      gap=0
    end
    page.height=page.height+gap
    for i=first,last do
      labels[i].x=16+(i-first)*(colW+16);labels[i].y=bodyY+page.height;labels[i].h=rh
      labels[i].w=primary and m.width-32 or colW
    end
    page.height=page.height+rh+((primary or home and menu.rows[first].card) and 8 or 0);page.last=last
    first=last+1
  end
  local used=0;for _,page in ipairs(pages)do used=math.max(used,page.height)end
  local height=math.max(112,math.ceil((bodyY+used+tap+footerGap)/8)*8)
  local panel={width=m.width,height=height,tap=tap,wide=wide,rowH=rowH,line=line,pages=pages,
    columns=columns,colW=colW,bodyY=bodyY,home=home,help=help,helpHeight=helpHeight,
    labelW=labelW,valueX=valueX,valueW=valueW,labels=labels,menu=menu}
  panel.viewport=GameUILayout.overlay(nil,{rect=rect,anchor="center",width=panel.width,
    height=height,scale=m.scale,margin=m.margin})
  return panel
end
local function drawListPanel(imp,p)
  local ui=state(imp);local rows=p.menu.rows;ui.rows=rows
  ui.focus=math.max(1,math.min(ui.focus,math.max(1,#rows)))
  ui.pageRanges=p.pages;ui.sheets=#p.pages;ui.sheet=math.max(1,math.min(ui.sheets,focusPage(ui)))
  local current=p.pages[ui.sheet];ui.pageRows=current.last-current.first+1
  if p.home then
    text(p.menu.title,16,12,p.width-32,'center')
    Classic.text(lang(imp,'POCKET RECOMP','ポケットリコンプ'),16,28,
      {width=p.width-32,align='center',color={.28,.36,.35,1}})
    if p.menu.subtitle then text(p.menu.subtitle,16,48,p.width-32,'center')end
  else
    text(p.menu.title,16,16,p.width-32)
    love.graphics.setColor(0,0,0,1);love.graphics.rectangle("fill",16,32,p.width-32,1)
    if p.menu.subtitle then text(p.menu.subtitle,16,40,p.width-32)end
  end
  for index=current.first,current.last do
    local row=rows[index]
    if row then
      local label=p.labels[index]
      local x,y=label.x,label.y+label.pad
      if row.section then
        love.graphics.setColor(.76,.8,.77,1);love.graphics.rectangle('fill',16,label.y-4,p.width-32,1)
      end
      if label.card then
        if p.home then
          local selected=ui.focus==index or ui.pressedId==row.id
          local fill=row.disabled and {.88,.89,.87,1} or label.primary and {.78,.88,.82,1} or {.9,.93,.9,1}
          love.graphics.setColor(fill);love.graphics.rectangle('fill',x,label.y,label.w,label.h)
          if selected then
            love.graphics.setColor(.12,.25,.23,1)
            love.graphics.rectangle('fill',x,label.y,2,label.h)
          end
        else Classic.box(x/8,label.y/8,label.w/8,label.h/8)end
      end
      local textX=x+(label.card and 20 or 8)
      if ui.focus==index then Classic.cursor(textX-12,y);ui.focusHit=row end
      for n,line in ipairs(label.label)do
        Classic.text(line,textX,y+(n-1)*label.line,{width=label.labelW,clip=true,
          align=label.card and not label.primary and 'center' or 'left',
          color=row.disabled and {.42,.46,.43,1} or {0,0,0,1}})
      end
      if row.category then text(">",p.width-32,y,8)end
      if label.value then
        local vy=label.wide and y or y+#label.label*label.line
        local vx=label.valueX+(row.step and p.tap or 0)
        for n,line in ipairs(label.value)do text(line,vx,vy+(n-1)*label.line,label.valueW-(row.step and p.tap*2 or 0))end
        if row.step then
          text("<",label.valueX+math.floor((p.tap-8)/16)*8,vy,8)
          text(">",p.width-16-p.tap+math.floor((p.tap-8)/16)*8,vy,8)
        end
      end
      addHit(ui,row.id,x,label.y,label.w,label.h,function()ui.focus=index;invoke(imp,row)end,index)
      if row.step then
        local valueTop=label.wide and 0 or #label.label*label.line
        addHit(ui,row.id.."-prev",label.valueX,label.y+valueTop,p.tap,label.h-valueTop,function()ui.focus=index;row.step(-1)end,index)
        addHit(ui,row.id.."-next",p.width-16-p.tap,label.y+valueTop,p.tap,label.h-valueTop,function()ui.focus=index;row.step(1)end,index)
      end
    end
  end
  love.graphics.setColor(0,0,0,1)
  if p.help then
    local y=p.height-p.tap-8-p.helpHeight
    love.graphics.rectangle("fill",16,y-8,p.width-32,1)
    for n,line in ipairs(p.help)do text(line,16,y+(n-1)*16,p.width-32)end
  end
  if not p.home then love.graphics.rectangle("fill",16,p.height-p.tap-20,p.width-32,1)end
  footer(imp)
end
local function drawMessage(imp,title,body)
  local ui=state(imp)
  if ui.panel then
    local p=ui.panel
    text(title,16,16,p.width-32)
    love.graphics.setColor(0,0,0,1);love.graphics.rectangle("fill",16,32,p.width-32,1)
    ui.rows={};ui.pageRows=p.per
    ui.sheets=math.max(1,math.ceil(#p.lines/p.per));ui.sheet=math.max(1,math.min(ui.sheet,ui.sheets))
    for n=1,p.per do
      local line=p.lines[(ui.sheet-1)*p.per+n]
      if line then text(line,16,40+(n-1)*16,p.width-32)end
    end
    footer(imp)
    return
  end
  text(title,16,16,128)
  local lines=Classic.wrap(body,144);local per=5
  ui.sheets=math.max(1,math.ceil(#lines/per));ui.sheet=math.max(1,math.min(ui.sheet,ui.sheets))
  for i=1,per do local line=lines[(ui.sheet-1)*per+i];if line then text(line,8,40+(i-1)*16,144)end end
  footer(imp)
end
local function messagePanel(imp,rect)
  local ui=state(imp)
  local m=GameUILayout.panelMetrics({save={options=ui.options}},{rect=rect,minHeight=128})
  local width=m.width
  local body=ui.page=="license"and(love.filesystem.read("LICENSE.MD")or"License unavailable")or ui.messageBody or""
  local lines=Classic.wrap(body,width-32)
  local per=math.max(1,math.floor((m.height-64)/16))
  local height=math.max(112,64+math.min(#lines,per)*16)
  return {width=width,height=height,tap=16,per=per,lines=lines,
    viewport=GameUILayout.overlay(nil,{rect=rect,anchor="center",width=width,height=height,
      scale=m.scale,margin=m.margin})}
end
local function drawModal(imp)
  local ui=state(imp);local c=imp._modConfirm;local edit=ui.edit
  text(c and c.title or edit.row.label,16,16,128)
  local body=c and table.concat(c.lines or{},"\n")or edit.text.."_"
  local lines=Classic.wrap(body,144);local per=4
  ui.sheets=math.max(1,math.ceil(#lines/per));ui.sheet=math.max(1,math.min(ui.sheet,ui.sheets))
  for i=1,per do local line=lines[(ui.sheet-1)*per+i];if line then text(line,8,40+(i-1)*16,144)end end
  if ui.sheets>1 then
    text("< "..ui.sheet.."/"..ui.sheets.." >",48,104,64)
    addHit(ui,"page-prev",24,96,56,16,function()sheet(imp,-1)end)
    addHit(ui,"page-next",80,96,56,16,function()sheet(imp,1)end)
  end
  text(lang(imp,"やめる","CANCEL"),16,128,56)
  text(lang(imp,"けってい","CONFIRM"),88,128,56)
  addHit(ui,"confirm-cancel",8,120,72,16,function()back(imp)end)
  addHit(ui,"confirm-yes",80,120,72,16,function()
    if edit then edit.row.setText(edit.text);edit.model.save();ui.edit=nil;if love.keyboard.setTextInput then love.keyboard.setTextInput(false)end
    elseif c.kind=="importOversize"then imp._modConfirm=nil;imp:_importSave(c.version,c.source,true)
    elseif c.kind=="largeImport"then imp._modConfirm=nil;imp:_importRequiredSource(c.modId,c.importId,c.source,true)
    else imp._modConfirm=nil end
  end)
end
function View.draw(imp)
  local ui=state(imp);local g=love.graphics
  local x,y,w,h=SafeArea.windowRect()
  local pw=love.graphics.getPixelDimensions and love.graphics.getPixelDimensions() or w
  local creditScale=math.max(1,math.min(2,math.floor(pw/640)))
  local creditSX,creditSY=Classic.bitmapScale(creditScale)
  local creditLines=Classic.bitmapWrap(View.CREDIT,math.max(8,math.floor((w-16)/creditSX)))
  local creditH=#creditLines*8*creditSY
  local footerY=y+h-creditH-8
  ui.credit={scale=creditScale,lines=creditLines,y=footerY,height=creditH}
  -- Carry the menu paper out to the display edge. The logical bitmap stays
  -- sharp without presenting a tiny white screen inside a black surround.
  local paper=ui.page=="games" and {.965,.969,.945,1} or {1,1,1,1}
  g.push("all");g.origin();g.setScissor();g.setShader();g.clear(paper)
  ui.hits={};ui.focusHit=nil
  ui.pageRanges=nil
  ui.panel=nil
  local rect={x=x,y=y,w=w,h=math.max(144,footerY-y)}
  if not imp._modConfirm and not ui.edit then
    if ui.page=="message"or ui.page=="license"then ui.panel=messagePanel(imp,rect)
    else ui.panel=listPanel(imp,rect)end
    if ui.page~="games"then g.clear(0.9,0.9,0.9,1);Classic.backdrop(ui.panel.viewport,nil,0)end
  end
  ui.layout=Classic.begin(nil,{rect=rect,layout=ui.panel and ui.panel.viewport,
    paper=paper,version=imp.tab,useROM=imp.ready[imp.tab]==true})
  ui.s=ui.layout.scale;ui.top=ui.layout.y;ui.bottom=ui.layout.y+ui.layout.h;ui.bodyH=ui.layout.h
  ui.x=ui.layout.x;ui.w=ui.layout.w
  if ui.page~="games" or imp._modConfirm or ui.edit then
    Classic.box(0,0,(ui.layout.width or 160)/8,(ui.layout.height or 144)/8,{1,1,1,1})
  end
  if ui.panel and ui.panel.menu then
    drawListPanel(imp,ui.panel)
  elseif imp._modConfirm or ui.edit then
    drawModal(imp)
  elseif ui.page=="message"then
    drawMessage(imp,ui.messageTitle or"",ui.messageBody or"")
  elseif ui.page=="license"then
    drawMessage(imp,"LICENSE.MD",love.filesystem.read("LICENSE.MD")or"License unavailable")
  else
    local menu=model(imp);ui.rows=menu.rows
    local count=#menu.rows
    local values=false;for _,row in ipairs(menu.rows)do if row.value~=nil then values=true;break end end
    ui.pageRows=values and 3 or ROWS
    local firstY,spacing=values and 32 or 40,values and 32 or 16
    ui.sheets=math.max(1,math.ceil(count/ui.pageRows));ui.sheet=math.max(1,math.min(ui.sheet,ui.sheets))
    ui.focus=math.max(1,math.min(ui.focus,math.max(1,count)))
    local twoHeaders=menu.subtitle and menu.title:match("^[%w%s/_%.%-]+$")
    text(menu.title,16,twoHeaders and 8 or 16,128)
    if twoHeaders then text(menu.subtitle,16,24,128)end
    for n=1,ui.pageRows do
      local index=(ui.sheet-1)*ui.pageRows+n;local row=menu.rows[index]
      if row then
        local ry=firstY+(n-1)*spacing
        local hitH=math.min(spacing,120-ry)
        if ui.focus==index then Classic.cursor(8,ry)end
        if ui.pressedId==row.id then
          g.setColor(0,0,0,1);g.rectangle("fill",16,ry+15,136,1)
        end
        text(row.label,24,ry,128)
        if row.value~=nil then text((row.step and "< "or"")..row.value..(row.step and " >"or""),32,ry+16,120)end
        addHit(ui,row.id,8,ry,144,hitH,function()ui.focus=index;invoke(imp,row)end,index)
        if row.step then
          -- The left quarter moves backwards; the rest advances. Both retain
          -- the same complete row touch target and visible grid.
          addHit(ui,row.id.."-prev",8,ry,32,hitH,function()ui.focus=index;row.step(-1)end,index)
          addHit(ui,row.id.."-next",40,ry,112,hitH,function()ui.focus=index;row.step(1)end,index)
        end
        if ui.focus==index then ui.focusHit=row end
      end
    end
    footer(imp)
  end
  ui.maxScroll=math.max(0,(ui.sheets-1)*(ui.pageRows or ROWS))
  Classic.finish()
  -- Keep the exact required attribution outside every app panel, using the
  -- same real bitmap font at a native integer scale.
  for n,line in ipairs(creditLines)do Classic.bitmapText(line,math.floor(x+8),math.floor(footerY+(n-1)*8*creditSY),creditScale,{0,0,0,1})end
  local Kit=package.loaded["src.ui.kit.Kit"]
  if Kit and Kit.FileBrowser and Kit.FileBrowser.active then
    local original=require("src.ui.kit.Layout").metrics();local metrics={}
    for key,value in pairs(original)do metrics[key]=value end
    metrics.H=footerY
    local pointer=ui.fileClick or{};ui.fileClick=nil
    Kit.beginFrame(pointer.x or-1,pointer.y or-1,pointer.x~=nil,0);Kit.FileBrowser.draw(metrics);Kit.endFrame()
    g.setColor(1,1,1,1);g.rectangle("fill",x,footerY,w,creditH)
    for n,line in ipairs(creditLines)do Classic.bitmapText(line,math.floor(x+8),math.floor(footerY+(n-1)*8*creditSY),creditScale,{0,0,0,1})end
  end
  g.pop()
end
function View.update(imp)
  local ui=state(imp)
  if imp.tab=="mods"then imp.tab=imp.modScope or"red_jp";open(imp,"mods")end
end
function View.detach(imp)
  local ui=state(imp);ui.hits={};ui.touch=nil;ui.pressedId=nil
  if love.keyboard.setTextInput then love.keyboard.setTextInput(false)end
end
function View.clickAt(imp,x,y)
  local ui=state(imp)
  local Kit=package.loaded["src.ui.kit.Kit"]
  if Kit and Kit.FileBrowser and Kit.FileBrowser.active then ui.fileClick={x=x,y=y};return end
  for i=#ui.hits,1,-1 do local hit=ui.hits[i]
    if rectContains(hit,x,y)then if hit.row then ui.focus=hit.row end;invoke(imp,hit);return true end
  end
end
function View.mousepressed(imp,x,y)
  local ui=state(imp);local pulse=imp.pulse or 0
  if ui.touch or pulse<(ui.ignoreMouseUntil or 0)or pulse<(ui.touchMouseUntil or 0)then return end
  return View.clickAt(imp,x,y)
end
function View.touchpressed(imp,id,x,y)
  local ui=state(imp)
  if ui.touch then return end
  ui.touch={id=id,x=x,y=y};ui.touchMouseUntil=(imp.pulse or 0)+0.5
  for i=#ui.hits,1,-1 do local hit=ui.hits[i]
    if rectContains(hit,x,y)then ui.pressedId=hit.id;break end
  end
end
function View.touchmoved(imp,id,x,y)
  local ui=state(imp);local t=ui.touch
  if not t or t.id~=id then return end
  if math.abs(x-t.x)>12 or math.abs(y-t.y)>12 then t.drag=true;ui.pressedId=nil end
end
function View.touchreleased(imp,id,x,y)
  local ui=state(imp);local t=ui.touch
  if not t or t.id~=id then return end
  ui.touch=nil;ui.pressedId=nil;ui.touchMouseUntil=(imp.pulse or 0)+0.5
  if t.drag then
    local delta=y-t.y;if math.abs(delta)>40 then sheet(imp,delta<0 and 1 or-1)end
  else View.clickAt(imp,x,y)end
end
function View.touchcancelled(imp,id)
  local ui=state(imp)
  if ui.touch and ui.touch.id==id then ui.touch=nil;ui.pressedId=nil end
  ui.touchMouseUntil=(imp.pulse or 0)+0.5
end
function View.wheelmoved(imp,_,dy)
  if dy~=0 then sheet(imp,dy<0 and 1 or-1)end
end
function View.keypressed(imp,key)
  local ui=state(imp)
  local Kit=package.loaded["src.ui.kit.Kit"]
  if Kit and Kit.FileBrowser and Kit.FileBrowser.active then return Kit.keypressed(key)end
  if key=="escape"or key=="acback"then back(imp);return true end
  if ui.edit then
    if key=="backspace"then ui.edit.text=ui.edit.text:gsub("[%z\1-\127\194-\244][\128-\191]*$","")
    elseif key=="return"then ui.edit.row.setText(ui.edit.text);ui.edit.model.save();ui.edit=nil;if love.keyboard.setTextInput then love.keyboard.setTextInput(false)end end
    return true
  end
  if imp._modConfirm then
    if key=="left"or key=="pageup"then sheet(imp,-1)
    elseif key=="right"or key=="pagedown"then sheet(imp,1)
    elseif key=="return"or key=="space"then for _,h in ipairs(ui.hits)do if h.id=="confirm-yes"then invoke(imp,h);break end end end
    return true
  end
  local rows=ui.rows or{}
  if ui.page=="games"and ui.panel and ui.panel.columns>1
      and (key=="up"or key=="down"or key=="left"or key=="right")then
    local count=#rows
    if count>1 then
      if key=="left"or key=="right"then
        if ui.focus==1 then ui.focus=key=="left"and 2 or math.min(count,3)
        else
          local first=2+math.floor((ui.focus-2)/2)*2
          ui.focus=ui.focus==first and math.min(count,first+1)or first
        end
      elseif key=="down"then
        ui.focus=ui.focus==1 and 2 or ui.focus+2<=count and ui.focus+2 or 1
      else
        ui.focus=ui.focus==1 and (2+math.floor((count-2)/2)*2)or ui.focus<=3 and 1 or ui.focus-2
      end
    end
    ui.sheet=focusPage(ui);ui.keyboard=true
    return true
  end
  if key=="up"or key=="down"or key=="tab"then
    if #rows>0 and ui.page~="license"and ui.page~="message"then
      ui.focus=(ui.focus-1+(key=="up"and-1 or 1))%#rows+1
      ui.sheet=focusPage(ui);ui.keyboard=true
    else sheet(imp,key=="up"and-1 or 1)end
    return true
  elseif key=="left"or key=="right"then
    local row=rows[ui.focus]
    if row and row.step and ui.page=="settings-detail"then row.step(key=="left"and-1 or 1)
    else sheet(imp,key=="left"and-1 or 1)end
    return true
  elseif key=="return"or key=="space"then
    if ui.page~="message"and ui.page~="license"then invoke(imp,rows[ui.focus])end
    return true
  elseif key=="pagedown"then sheet(imp,1);return true
  elseif key=="pageup"then sheet(imp,-1);return true end
end
function View.textinput(imp,input)
  local ui=state(imp);local e=ui.edit
  if e then
    local max=(e.row.editText and e.row.editText.maxLen)or 128
    local all=e.text..input;local result={}
    for ch in all:gmatch("[%z\1-\127\194-\244][\128-\191]*")do if #result>=max then break end;result[#result+1]=ch end
    e.text=table.concat(result)
  end
end
return View
