-- SPDX-License-Identifier: GPL-3.0-only
-- Bitmap session windows. Kept outside StateStack so scripts,
-- battles, MOD updates and playtime stay paused while options are open.
local Classic = require("src.ui.ClassicUI")
local GameUILayout = require("src.ui.GameUILayout")
local SessionMenu = {}
SessionMenu.__index = SessionMenu
local raisedKana={}
for ch in ("がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽガギグゲゴザジズゼゾダヂヅデドバビブベボパピプペポヴ"):gmatch("[%z\1-\127\194-\244][\128-\191]*")do raisedKana[ch]=true end
local function raised(text)
  for ch in tostring(text or""):gmatch("[%z\1-\127\194-\244][\128-\191]*")do if raisedKana[ch]then return true end end
  return false
end
local function inside(r, x, y)
  return r and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h
end
local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for k, v in pairs(value) do result[k] = copy(v) end
  return result
end
local function replace(target, source)
  for k in pairs(target) do target[k] = nil end
  for k, v in pairs(source) do target[k] = copy(v) end
end
local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

function SessionMenu.new(game, page)
  return setmetatable({ game = game, page = page or "main", focus = 1,
    scroll = 0, hits = {}, axes = {}, notice = nil }, SessionMenu)
end
function SessionMenu:canSave()
  local g, ow = self.game, self.game.overworld
  if g.systemMenuCanSave then return g:systemMenuCanSave() end
  return not g.linkSession and ow and ow.player and g.save and g.stack
    and g.stack:top() == ow and g:quickSaveAllowed() == true or false
end
function SessionMenu:saveProgress()
  if not self:canSave() then
    self.notice, self.warning = "はなしたり バトルしたり\nしていない ときに\nたちどまって ほぞんしてね", true
    return false
  end
  local ok, result = pcall(self.game.writeSave, self.game)
  if not ok or not result then
    self.notice, self.warning = "レポートを\nかけませんでした！\nゲームは つづけられます", true
    return false
  end
  self.notice, self.warning = "レポートを かきました。", false
  return true
end
function SessionMenu:goHome(save)
  if self.leaving then return false end
  if not self.game.returnToLauncher then
    self.notice, self.warning = "ホームを\nひらけませんでした！", true
    return false
  end
  if save and not self:saveProgress() then return false end
  -- Keep the session paused until main.lua tears it down on the next update.
  local ok = pcall(self.game.returnToLauncher, {})
  if not ok then
    self.notice, self.warning = "ホームを\nひらけませんでした！", true
    return false
  end
  self.leaving = true
  return true
end
function SessionMenu:open(page, section)
  if page~=self.page then
    self.history=self.history or {}
    self.history[#self.history+1]={page=self.page,section=self.section}
  end
  self.page, self.section, self.focus, self.scroll = page, section, 1, 0
  self.listPage, self.noticePage = 1, 1
  self.notice, self.warning, self.pointer = nil, false, nil
  self.footerSelected=false
end
function SessionMenu:back()
  self:cancelTransfers()
  if self.notice then
    if self.page=="blocked" then self.game:closeSessionMenu() else self.notice=nil end
    return
  end
  local previous=self.history and table.remove(self.history)
  if previous then
    self.page,self.section=previous.page,previous.section
    self.focus,self.scroll,self.listPage=1,0,1
    self.notice,self.pointer,self.footerSelected=nil,nil,false
  elseif self.page=="settings-detail" then
    self.page,self.section,self.focus,self.scroll="settings",nil,1,0
  else self.game:closeSessionMenu() end
end
function SessionMenu:cancelTransfers()
  local files = package.loaded["src.import.SettingsFiles"]
  if files and files.cancel then files.cancel() end
end
function SessionMenu:settings()
  if self.model then return self.model end
  self.model = require("src.import.LauncherSettings").open({
    options = self.game.save.options,
    save = function() return self.game:writeOptions() end,
    importSettings = function() self:importSettings() end,
    exportSettings = function() self:exportSettings() end,
    editTouchAreas = self.game.openTouchAreasEditor and function() self.game:openTouchAreasEditor() end,
  }, require("src.core.GameVersion").get())
  local pipelines = require("src.render.Pipelines")
  local translate = require("src.ui.JapaneseUIStrings").lookup
  local rows = {}
  for _, entry in ipairs(pipelines.list()) do
    local id = entry.id
    local names = { voxel = "3Dの かくど", tiltshift = "とおくの ぼかし" }
    rows[#rows + 1] = { id = "pipeline." .. id, label = names[id] or translate(entry.def.label or id),
      value = function()
        local label = pipelines.levelLabel(id)
        return label == "OFF" and "オフ" or label == "ON" and "オン" or translate(label)
      end,
      step = function(delta)
        pipelines.cycle(id, delta)
        pipelines.syncOptions(self.game.save.options)
        return true
      end }
  end
  if #rows > 0 then
    local target
    for _,section in ipairs(self.model.sections)do if section.id=="world"then target=section end end
    if target then for _,row in ipairs(rows)do target.rows[#target.rows+1]=row end
    else self.model.sections[#self.model.sections + 1] = { title = "3Dと エフェクト", rows = rows } end
  end
  return self.model
end
function SessionMenu:applyImportedSettings(candidate)
  if self.game.sessionMenu ~= self or not self:canSave() then
    return false, "いまは せっていを\nよみこめません"
  end
  if type(candidate) ~= "table" then return false, "せっていを よみこめません" end
  require("src.render.PausedFrame").invalidate()
  local options = self.game.save.options
  local snapshot = copy(options)
  local restart = false
  for _, key in ipairs({ "mods", "modsByVersion", "modsGen2", "safeMode" }) do
    if not same(options[key], candidate[key]) then restart = true end
  end
  replace(options, candidate)
  local ok = pcall(function()
    self.game:applyOptions(options)
    assert(self.game:writeOptions(), "options write failed")
  end)
  if not ok then
    replace(options, snapshot)
    pcall(self.game.applyOptions, self.game, options)
    if self.game.mods then self.game.mods.modOptions = options.modOptions or {} end
    self.model = nil
    return false, "せっていを よみこめません！\nまえの せっていに\nもどしました"
  end
  if self.game.mods then self.game.mods.modOptions = options.modOptions or {} end
  self.model = nil
  self:open("settings")
  self.importRestartPending = restart
  return true
end
function SessionMenu:importSettings()
  if not self:canSave() then
    self.notice, self.warning = "はなしや バトルを おえて\nたちどまってから\nよみこんでね", true
    return false
  end
  local files = require("src.import.SettingsFiles")
  self.importRestartPending = nil
  return files.import(self.game.save.options, {
    apply = function(candidate) return self:applyImportedSettings(candidate) end,
    notify = function(message, ok)
      if self.game.sessionMenu ~= self then return end
      self.notice = message
      if ok and self.importRestartPending then
        self.notice = message .. "\nMODの きりかえは\nゲームを ひらきなおすと\nはんえいされます"
        self.importRestartPending = nil
      end
      self.noticePage, self.warning = 1, not ok
    end,
  })
end
function SessionMenu:exportSettings()
  local files = require("src.import.SettingsFiles")
  return files.export(self.game.save.options, {
    notify = function(message, ok)
      if self.game.sessionMenu ~= self then return end
      self.notice, self.noticePage, self.warning = message, 1, not ok
    end,
  })
end
function SessionMenu:change(item, delta)
  if not item.step then return end
  -- A color-pack switch rebuilds NPCs. Never do it during an escort,
  -- scripted transition, text interaction or a battle suspended underneath.
  if item.id == "colors" and not self:canSave() then
    self.notice, self.warning = "いろを かえる ときは\nはなしや バトルを おえて\nたちどまってね", true
    return
  end
  local options = self.game.save.options
  local snapshot = copy(options)
  local ok, changed = pcall(item.step, delta)
  if ok and not changed then return end
  require("src.render.PausedFrame").invalidate()
  if ok then
    ok = pcall(function()
      if item.id == "tilt" and (options.tilt or 0) > 0 then
        local pipelines = require("src.render.Pipelines")
        for _, entry in ipairs(pipelines.list()) do
          if entry.def.drawWorld then pipelines.setLevel(entry.id, 0) end
        end
        pipelines.syncOptions(options)
      end
      self.game:applyOptions(options)
      assert(self.game:writeOptions(), "options write failed")
      if self.game.mods and type(options.modOptions) == "table" then
        self.game.mods.modOptions = options.modOptions
      end
    end)
  end
  if not ok then
    replace(options, snapshot)
    pcall(self.game.applyOptions, self.game, options)
    if self.game.mods and type(options.modOptions) == "table" then
      self.game.mods.modOptions = options.modOptions
    end
    -- Model row closures point into nested option tables: rebuild after a
    -- rollback so a later tap cannot write to an abandoned table.
    self.model = nil
    self.notice, self.warning = "せっていを\nほぞんできませんでした！\nまえの せっていに もどします", true
  else
    self.notice, self.warning = nil, false
  end
end
function SessionMenu:rows()
  if self.page == 'touch' then
    return {
      {id='touch-start',label='ゲームメニュー',action=function()
        self.game:closeSessionMenu();self.game:navigateSystemMenu()
      end},
      {id='touch-select',label='SELECT',action=function()
        self.game:closeSessionMenu();require('src.core.JapaneseTouchMode').key('select')
      end},
      {id='settings',label='せってい',action=function()self:open('settings')end},
      {id='home',label='ホームへ',action=function()self:open('home')end},
      {id='resume',label='もどる',action=function()self:back()end},
    }
  elseif self.page == "main" then
    return {
      { id = "resume", label = "もどる", action = function() self.game:closeSessionMenu() end },
      { id = "settings", label = "せってい", action = function() self:open("settings") end },
      { id = "save", label = "レポート", disabled = not self:canSave(), action = function() self:saveProgress() end },
      { id = "home", label = "ホームへ", action = function() self:open("home") end },
    }
  elseif self.page == "home" then
    return {
      { id = "save-home", label = "レポートして もどる", disabled = not self:canSave(), action = function() self:goHome(true) end },
      { id = "discard-home", label = "ほぞんせず もどる", warning = true, action = function() self:goHome(false) end },
      { id = "cancel", label = "やめる", action = function() self:back() end },
    }
  end
  local model, rows = self:settings(), {}
  local function allowed(item)
    -- Only declarative value rows. File pickers, reset operations and ROM
    -- actions are never executed from a running game's session controls.
    if item.id == "importSettings" or item.id == "exportSettings" then return item.action ~= nil end
    return item.step and not item.action and not item.danger and item.id ~= "hotbar"
  end
  if self.page == "settings-files" then
    for _,section in ipairs(model.sections)do
      for _,item in ipairs(section.rows)do
        if item.id == "importSettings" or item.id == "exportSettings" then
          rows[#rows+1]={id=item.id,label=item.label,action=item.action,description=item.description}
        end
      end
    end
  elseif self.page == "settings" then
    for index, section in ipairs(model.sections) do
      local count = 0
      for _, item in ipairs(section.rows) do if allowed(item) then count = count + 1 end end
      if count > 0 then
        rows[#rows + 1] = { id = "section-" .. index, label = section.title,description=section.description,
          action = function() self:open("settings-detail", index) end }
      end
    end
  else
    local section = model.sections[self.section]
    for _, item in ipairs(section and section.rows or {}) do
      if allowed(item) then
        local row = { id = item.id, label = item.label,description=item.descriptionFor and item.descriptionFor() or item.description or item.help, value = item.value and tostring(item.value()) or "" }
        if item.id == "importSettings" or item.id == "exportSettings" then row.action = item.action
        else row.step = function(delta) self:change(item, delta) end end
        rows[#rows + 1] = row
      end
    end
  end
  return rows
end

local function tileCeil(value) return math.ceil(value / 8) * 8 end
local function pageFor(pages, index)
  for n, page in ipairs(pages) do
    if index >= page.first and index <= page.last then return n end
  end
  return 1
end

function SessionMenu:layout()
  local rows = self:rows()
  local main, home = self.page == "main" or self.page == 'touch', self.page == "home"
  if main and not self.notice then
    local view = GameUILayout.overlay(self.game, {
      anchor = "topright", box = { x = 48, y = 8, w = 104, h = 16+#rows*16 },
    })
    local l = { viewport = view, compact = true, rows = rows, first = 1, last = #rows,
      body = { x = 56, y = 16, w = 96, h = #rows*16 }, rowHeight = 16,
      perPage = #rows, pages = 1, page = 1, pageRanges = {{first=1,last=#rows}},
      frame = {6,1,13,2+#rows*2}, hits = {} }
    for i, row in ipairs(rows) do
      l.hits[#l.hits+1] = { x=56,y=12+(i-1)*16,w=96,h=16,
        row=row,index=i,id=row.id,delta=1 }
    end
    self.geometry,self.hits=l,l.hits
    return l
  end

  local m = GameUILayout.panelMetrics(self.game, {minHeight=home and 192 or 128})
  local width = m.width
  local tap = (home or self.notice) and 16 or 12
  local line = tap
  local native = self.game.data and self.game.data.font and self.game.data.font.composites
  local footerH = tap+16
  local help
  local selected=rows[self.focus or 1]
  local helpHeight=0
  if not self.notice and selected and selected.description and not selected.category then
    help=Classic.wrap(tostring(selected.description):gsub("\n"," "),width-32)
    local lines=m.height<240 and 1 or 2
    if #help>lines then
      help[lines]=Classic.clip(table.concat(help,"",lines),width-32)
      while #help>lines do table.remove(help)end
    end
    helpHeight=lines*16+8;footerH=footerH+helpHeight
  end
  local title = home and "ホームに もどる" or "せってい"
  if self.page == "settings-files" then title="せっていファイル" end
  if self.title then title=self.title end
  if self.page == "settings-detail" then
    local section=self:settings().sections[self.section]
    title=section and section.title or title
  end
  if self.notice then title=self.warning and "おしらせ" or "かくにん" end
  local titleLines=Classic.wrap(title,width-32)
  if #titleLines>2 then
    titleLines[2]=Classic.clip(table.concat(titleLines,"",2),width-32)
    while #titleLines>2 do table.remove(titleLines) end
  end
  local bodyY=20+math.min(2,#titleLines)*16
  local intro
  if home and not self.notice then
    intro=Classic.wrap(self:canSave()
      and "ほぞんせず もどると\nレポートあとの きろくは\nきえて しまいます！"
      or "いまは ほぞんできません\nもどると レポートあとの\nきろくが きえます！",width-32)
    bodyY=bodyY+#intro*16+8
    footerH=8 -- The third home action is the visible Cancel button.
  end
  local capacity=math.max(tap,m.height-bodyY-footerH)
  local wide=width>=192
  local labelWidth=wide and math.floor((width-64)*0.58/8)*8 or width-40
  local valueX=wide and 24+labelWidth+8 or 24
  local valueWidth=width-16-valueX
  local entries,pages={},{{first=1,last=0,height=0}}
  for i,row in ipairs(rows) do
    local labelWidth,valueX,valueWidth=labelWidth,valueX,valueWidth
    local sameLine=wide
    if row.value==nil then labelWidth=width-40
    else
      local need=math.max(24,Classic.width(row.value)+(row.step and 2*tap or 0))
      if Classic.width(row.label)+need<=width-48 then
        sameLine=true;labelWidth=width-48-need
        valueX=24+labelWidth+8;valueWidth=need
      end
    end
    local pad=not home and native and (raised(row.label)or raised(row.value))and 4 or 0
    local rowLine=pad>0 and 16 or line
    local label=Classic.wrap(row.label,labelWidth)
    local value=row.value~=nil and Classic.wrap(row.value or "",valueWidth-(row.step and 2*tap or 0)) or nil
    local function height()
      local lines=value and (sameLine and math.max(#label,#value) or #label+#value) or #label
      return math.max(tap,pad+(lines-1)*rowLine+line)
    end
    -- An unusually long third-party label may exceed a whole window. Retain
    -- its start with the usual bitmap ellipsis; it must not hide the footer.
    while height()>capacity and (#label>1 or value and #value>1) do
      local list=(value and #value>#label) and value or label
      local removed=table.remove(list)
      list[#list]=Classic.clip(list[#list]..removed, list==label and labelWidth or valueWidth-(row.step and 2*tap or 0))
    end
    local rh=height()
    local page=pages[#pages]
    if page.height+rh>capacity and page.last>=page.first then
      page={first=i,last=i-1,height=0};pages[#pages+1]=page
    end
    entries[i]={row=row,label=label,value=value,y=bodyY+page.height,h=rh,pad=pad,line=rowLine,
      labelX=24,labelW=labelWidth,valueX=valueX,valueW=valueWidth,wide=sameLine}
    page.last,page.height=i,page.height+rh
  end
  if self.notice then
    local lines=Classic.wrap(self.notice,width-32)
    local per=math.max(1,math.floor(capacity/16))
    self.noticePage=math.max(1,math.min(self.noticePage or 1,math.ceil(#lines/per)))
    local first=(self.noticePage-1)*per+1
    local shown={}
    for i=first,math.min(#lines,first+per-1) do shown[#shown+1]=lines[i] end
    pages={{first=1,last=0,height=math.max(32,math.min(per,#lines)*16)}}
    entries={}
    intro=shown
    bodyY=20+math.min(2,#titleLines)*16
    self._noticePages=math.max(1,math.ceil(#lines/per))
  end
  self.focus=math.max(1,math.min(self.focus,math.max(1,#rows)))
  -- A value can add a wrapped line without resizing the window. Follow the
  -- selected row after every reflow, including value changes and rotation.
  self.listPage=pageFor(pages,self.focus)
  local current=pages[self.listPage]
  local used=0;for _,page in ipairs(pages) do used=math.max(used,page.height) end
  local height=math.min(m.height,math.max(112,tileCeil(bodyY+used+footerH)))
  local view=GameUILayout.overlay(self.game,{anchor="center",width=width,height=height,
    scale=m.scale,margin=m.margin,rect=m.rect})
  local l={viewport=view,rows=rows,entries=entries,pageRanges=pages,
    first=current.first,last=current.last,perPage=current.last-current.first+1,
    rowHeight=tap,pages=#pages,page=self.listPage,wide=wide,tap=tap,
    title=titleLines,intro=intro,help=help,notice=self.notice~=nil,home=home,
    body={x=16,y=bodyY,w=width-32,h=used},frame={0,0,width/8,height/8},hits={}}
  if self.notice then
    l.hits[1]={id="notice",x=8,y=8,w=width-16,h=height-16,
      action=function()self:acknowledge()end}
  else
    for i=current.first,current.last do
      local e=entries[i]
      if e.value and e.row.step then
        local valueTop=e.wide and 0 or #e.label*e.line
        l.hits[#l.hits+1]={x=e.valueX,y=e.y+valueTop,w=tap,h=e.h-valueTop,
          row=e.row,index=i,id=e.row.id.."-",delta=-1}
        l.hits[#l.hits+1]={x=width-16-tap,y=e.y+valueTop,w=tap,h=e.h-valueTop,
          row=e.row,index=i,id=e.row.id.."+",delta=1}
      end
      l.hits[#l.hits+1]={x=16,y=e.y,w=width-32,h=e.h,
        row=e.row,index=i,id=e.row.id,delta=1}
    end
  end
  if not home or self.notice then
    local fy=height-tap-16
    if help then l.helpY=fy-helpHeight+8 end
    local navW=tap
    local countW=40
    local backW=math.min(88,width-32-navW*2-countW)
    l.back={x=16,y=fy,w=backW,h=tap+8}
    l.footerY=fy+8+math.floor((tap-8)/16)*8
    l.nav={prev={x=width-16-navW*2-countW,y=fy,w=navW,h=tap+8},
      next={x=width-16-navW,y=fy,w=navW,h=tap+8},countX=width-16-navW-countW,countW=countW}
    if not self.notice then
      l.hits[#l.hits+1]={x=l.back.x,y=fy,w=backW,h=l.back.h,id="back",action=function()self:back()end}
      if #pages>1 then
        for _,which in ipairs({"prev","next"}) do
          local r=l.nav[which];local delta=which=="prev" and -1 or 1
          l.hits[#l.hits+1]={x=r.x,y=r.y,w=r.w,h=r.h,id="page-"..which,
            action=function()self:changePage(delta)end}
        end
      end
    end
  end
  self.scroll=current.first-1
  self.geometry,self.hits=l,l.hits
  return l
end

local function drawLines(lines,x,y,width,spacing)
  for n,line in ipairs(lines or {}) do Classic.text(line,x,y+(n-1)*(spacing or 16),{width=width,clip=true}) end
end

local function pointerLayoutKey(l)
  local v=l.viewport
  return table.concat({v.x,v.y,v.w,v.h,v.sx,v.sy},',')
end
function SessionMenu:validTouch(p,l)
  return p and p.gesture and require('src.core.JapaneseTouchMode').sameContext(self.game,p.gesture)
    and p.page==self.page and p.section==self.section and p.notice==self.notice
    and p.listPage==self.listPage and p.noticePage==self.noticePage
    and p.layoutKey==pointerLayoutKey(l)
end

function SessionMenu:draw()
  local l=self:layout()
  local p=self.pointer
  local pressed=self:validTouch(p,l) and not p.gesture.dragged and p.hit or nil
  local focus=pressed and pressed.index or self.focus
  local footerSelected=pressed and pressed.id=='back' or (not pressed and self.footerSelected)
  local box=l.compact and {x=48,y=8,w=104,h=80} or nil
  Classic.backdrop(l.viewport,box,l.compact and 0 or 0.16)
  Classic.begin(self.game,{layout=l.viewport,paper={0,0,0,0}})
  Classic.box(unpack(l.frame))
  if pressed and pressed.x then
    -- Use a native grey shade so the four-colour palette retains feedback.
    love.graphics.setColor(.67,.67,.67,1)
    love.graphics.rectangle('fill',pressed.x,pressed.y,pressed.w,pressed.h)
  end
  if l.compact then
    for i,row in ipairs(l.rows) do
      local y=16+(i-1)*16
      if i==focus then Classic.cursor(56,y) end
      Classic.text(row.label,64,y,{width=80,clip=true})
    end
  else
    local width,height=l.viewport.width,l.viewport.height
    drawLines(l.title,16,16,width-32)
    local g=love.graphics
    g.setColor(0,0,0,1)
    g.rectangle("fill",16,20+math.min(2,#l.title)*16-8,width-32,1)
    if l.intro then
      local y=l.notice and l.body.y or 20+math.min(2,#l.title)*16
      drawLines(l.intro,16,y,width-32)
    end
    if not l.notice then
      for i=l.first,l.last do
        local e=l.entries[i]
        local y=e.y+e.pad
        if i==focus and not footerSelected then Classic.cursor(12,y) end
        drawLines(e.label,e.labelX,y,e.labelW,e.line)
        if e.row.category then Classic.text(">",width-24,y)end
        if self.page=="settings" then Classic.text(">",width-32,y) end
        if e.value then
          local vy=e.wide and y or y+#e.label*e.line
          if e.row.step then
            Classic.text("<",e.valueX+math.floor((l.tap-8)/16)*8,vy)
            Classic.text(">",width-16-l.tap+math.floor((l.tap-8)/16)*8,vy)
          end
          local pad=e.row.step and l.tap or 0
          drawLines(e.value,e.valueX+pad,vy,e.valueW-2*pad,e.line)
        end
      end
    end
    if l.footerY then
      if l.help then
        g.setColor(0,0,0,1);g.rectangle("fill",16,l.helpY-8,width-32,1)
        drawLines(l.help,16,l.helpY,width-32,16)
      end
      g.setColor(0,0,0,1);g.rectangle("fill",16,height-l.tap-20,width-32,1)
      local caption=l.notice and ((self.noticePage or 1)<(self._noticePages or 1) and "つづき" or "もどる") or "もどる"
      if footerSelected then Classic.cursor(12,l.footerY) end
      Classic.text(caption,16,l.footerY,{width=l.back.w,clip=true})
      if not l.notice and l.pages>1 then
        Classic.text("<",l.nav.prev.x+math.floor((l.nav.prev.w-8)/16)*8,l.footerY)
        Classic.text(l.page.."/"..l.pages,l.nav.countX,l.footerY,{width=l.nav.countW,align="center",clip=true})
        Classic.text(">",l.nav.next.x+math.floor((l.nav.next.w-8)/16)*8,l.footerY)
      end
    end
  end
  Classic.finish()
end

function SessionMenu:activate(row, delta)
  if self.leaving or not row then return end
  if row.disabled then
    if row.id == "save" or row.id == "save-home" then self:saveProgress() end
    return
  end
  if row.step then row.step(delta or 1) elseif row.action then row.action() end
end
function SessionMenu:acknowledge()
  if not self.notice then return end
  self:layout()
  local pages = self._noticePages or 1
  if (self.noticePage or 1) < pages then self.noticePage = (self.noticePage or 1) + 1
  elseif self.page=="blocked" then self.game:closeSessionMenu()
  else self.notice, self.noticePage = nil, 1 end
end
function SessionMenu:changePage(delta)
  if self.notice then return end
  self.footerSelected=false
  local l = self:layout()
  self.listPage = math.max(1, math.min(l.pages, l.page + delta))
  self.focus = l.pageRanges[self.listPage].first
  self:layout()
end
function SessionMenu:keypressed(key)
  if self.leaving then return end
  if key == "escape" or key == "acback" or key == "backspace" or key == "x" then self:back(); return end
  if self.notice then
    if key == "return" or key == "space" or key == "z" then self:acknowledge() end
    return
  end
  local l = self:layout()
  if key == "up" or key == "down" then
    if self.footerSelected then
      self.footerSelected=false;self.focus=key=='up' and #l.rows or 1
    else
      local nextIndex=self.focus+(key=='up' and -1 or 1)
      if l.footerY and (nextIndex<1 or nextIndex>#l.rows) then self.footerSelected=true end
      self.focus=math.max(1,math.min(#l.rows,nextIndex))
    end
    self.listPage = pageFor(l.pageRanges,self.focus)
  elseif key == "left" or key == "right" then
    if self.footerSelected then return end
    local row = l.rows[self.focus]
    if row and row.step then self:activate(row, key == "left" and -1 or 1)
    else self:changePage(key == "left" and -1 or 1) end
  elseif key == "return" or key == "space" or key == "z" then
    if self.footerSelected then self:back()else self:activate(l.rows[self.focus],1)end
  end
end
function SessionMenu:gamepadpressed(button)
  local keys = { dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
    a = "return", b = "escape", back = "escape", start = "escape", guide = "escape" }
  if keys[button] then self:keypressed(keys[button]) end
end
function SessionMenu:gamepadaxis(axis, value)
  if axis ~= "leftx" and axis ~= "lefty" then return end
  local direction = value < -0.55 and -1 or value > 0.55 and 1 or 0
  if direction ~= 0 and direction ~= self.axes[axis] then
    self:keypressed(axis == "leftx" and (direction < 0 and "left" or "right") or (direction < 0 and "up" or "down"))
  end
  self.axes[axis] = direction
end
function SessionMenu:wheelmoved(dy)
  if dy ~= 0 then self:changePage(dy < 0 and 1 or -1) end
end
function SessionMenu:contentHit(x,y)
  local l = self:layout()
  local px, py, contained = Classic.hit(l.viewport, x, y)
  if contained then
    if self.notice then return { id = "notice", action = function() self:acknowledge() end } end
    for _, hit in ipairs(l.hits) do if inside(hit, px, py) then return hit end end
  end
end
function SessionMenu:hit(x, y)
  local item=self:contentHit(x,y)
  if item then return item end
  if require('src.core.JapaneseTouchMode').configured(self.game) then
    local control=require('src.core.JapaneseTouchMode').navHit(x,y,self.game)
    if control then return {id=control,action=function()
      if control=='touch-back' then self:back()
      elseif self.page=='touch' then self.game:closeSessionMenu()
      else self:open('touch')end
    end}end
  end
  -- The original on-screen pad remains visible around a small START-style
  -- menu. Route it to this overlay only; never enqueue gameplay input.
  local touch = self.game.touchControls
  if touch and touch.visible and touch:visible() then
    local control = touch:hitTest(x, y)
    local key = ({ a = "return", b = "escape", start = "escape" })[control]
    if control == "dpad" then
      local zone = touch:layout().dpad
      local dx, dy = x - zone.cx, y - zone.cy
      if math.max(math.abs(dx), math.abs(dy)) >= zone.w * 0.1 then
        key = math.abs(dx) >= math.abs(dy) and (dx < 0 and "left" or "right") or (dy < 0 and "up" or "down")
      end
    end
    if key then return { id = "pad-" .. key, action = function() self:keypressed(key) end } end
  end
end
function SessionMenu:pressed(id, x, y)
  if self.pointer then return end
  self.pointer = { id = id, x = x, y = y, lastY = y, hit = self:hit(x, y) }
  local T=require('src.core.JapaneseTouchMode')
  if T.configured(self.game) then
    self.pointer.gesture=T.stamp(self.game,x,y)
    self.pointer.page,self.pointer.section,self.pointer.notice=self.page,self.section,self.notice
    self.pointer.listPage,self.pointer.noticePage=self.listPage,self.noticePage
    self.pointer.layoutKey=pointerLayoutKey(self:layout())
  end
end
function SessionMenu:cancelPointers()
  self.pointer, self.axes = nil, {}
end
function SessionMenu:moved(id, x, y)
  local p = self.pointer
  if not p or p.id ~= id then return end
  if math.abs(y - p.y) > 9 or math.abs(x - p.x) > 9 then p.drag = true end
  if p.gesture then require('src.core.JapaneseTouchMode').track(p.gesture,x,y)end
  p.lastY = y
end
function SessionMenu:released(id, x, y)
  local p = self.pointer
  if not p or p.id ~= id then return end
  self.pointer = nil
  if p.gesture then
    local T=require('src.core.JapaneseTouchMode')
    if not self:validTouch(p,self:layout()) then return end
    local direction=T.flick(p.gesture,x,y)
    if p.gesture.dragged then
      if direction then self:keypressed(direction)end
      return
    end
    if not T.isTap(p.gesture,x,y) then return end
    local hit=self:hit(x,y)
    if not p.hit and not hit then self:keypressed('return');return end
    -- Keep the initially pressed item through small finger wobble. Resolve
    -- it again at the press location so stale callbacks are never reused.
    hit=p.hit and self:hit(p.x,p.y)
    if not hit or hit.id~=p.hit.id or hit.index~=p.hit.index then return end
    if hit.action then hit.action()
    else self.footerSelected=false;self.focus=hit.index;self:activate(hit.row,hit.delta)end
    return
  end
  if p.drag then
    if math.abs(y - p.y) >= 24 then self:changePage(y < p.y and 1 or -1) end
    return
  end
  local hit = self:hit(x, y)
  if not p.hit or not hit or hit.id ~= p.hit.id then return end
  if hit.action then hit.action()
  else self.footerSelected=false;self.focus = hit.index; self:activate(hit.row, hit.delta) end
end

return SessionMenu
