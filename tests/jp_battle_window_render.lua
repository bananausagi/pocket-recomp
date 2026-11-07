-- Exercise the final, real battle composition at all saved window sizes.
-- Called only by the opt-in authored-art intro fixture, after real input has
-- reached dialogue or the command menu. No production renderer is replaced.
return function(Game,Renderer,battle,tag,render,check)
  local Font=require('src.render.Font')
  local Panels=require('src.battle.JapaneseBattlePanels')
  local Input=Game.input
  local phase=battle.phase
  local oldFactor=Game.save.options.jpDialogScale
  local oldDraw=Panels.draw
  local runs,codes
  Panels.draw=function(b,m)
    local draw,code=Font.draw,Font.drawCode
    runs,codes={},{}
    local depth,inText=0,false
    Font.draw=function(text,x,y,...)
      if y>=m.command.y then runs[#runs+1]={text=text,x=x,y=y,width=Font.width(text)}end
      inText=true;draw(text,x,y,...);inText=false
    end
    Font.drawCode=function(c,x,y,...)
      if depth==0 and not inText and y>=m.command.y then
        codes[#codes+1]={code=c,x=x,y=y,width=Font.advanceOf(c)}
      end
      depth=depth+1;code(c,x,y,...);depth=depth-1
    end
    oldDraw(b,m)
    Font.draw,Font.drawCode=draw,code
  end
  local function pulse(key)
    Input:sourcePress(key,'window-qa');Game:step(1/60)
    Input:sourceRelease(key,'window-qa');Game:step(1/60)
  end
  local function firstMove()
    -- Unlike the command menu, the move grid wraps at its edges.
    if battle.moveIndex>2 then pulse('up')end
    if battle.moveIndex%2==0 then pulse('left')end
  end
  local function shot(label)
    local _,m=render('window-'..tag..'-'..Game.save.options.jpDialogScale..'-'..label)
    local r=m.command
    check(r.x==m.enemyHUD.x and r.x+r.w==m.playerHUD.x+m.playerHUD.w,
      label..' lower window follows the two status outer edges')
    check(r.x+r.w/2==m.width/2,label..' window stays centred')
    check(r.w>=160 and r.w<=208,label..' readable width is independent of unused viewport space')
    local pixels=Renderer.battlePresentationCanvas:newImageData()
    local cr,cg,cb,ca=pixels:getPixel(r.x+r.w-6,r.y+6)
    check(cr==1 and cg==1 and cb==1 and ca==1,label..' shortened window keeps opaque white paper')
    local _,_,_,left=pixels:getPixel(math.max(0,r.x-1),r.y+8)
    local _,_,_,right=pixels:getPixel(math.min(m.width-1,r.x+r.w),r.y+8)
    check(r.x==0 or (left==0 and right==0),label..' both newly exposed margins remain transparent')
    local safe=true
    for _,list in ipairs({runs,codes})do for _,run in ipairs(list)do
      safe=safe and run.x>=r.x+3 and run.x+run.width<=r.x+r.w-3
        and run.y>=r.y+8 and run.y+8<=r.y+r.h-3
    end end
    check(safe,label..' glyph runs remain inside the shortened black frame')
    return m
  end
  for _,factor in ipairs({1,.75,.5})do
    Game.save.options.jpDialogScale=factor
    if phase=='messages' then
      local expected=0;for _,line in ipairs(battle.shown or {})do expected=expected+#line end
      shot('messages')
      local count=0;for _,c in ipairs(codes)do if c.code~=0xEE then count=count+1 end end
      check(expected>0 and count==expected,'all actual intro dialogue glyphs survive the new window width')
    else
      pulse('up');pulse('left')
      local m=shot('commands')
      local cells=Panels.cells(m,'menu')
      local cursor=codes[1]
      check(battle.menuIndex==1 and cursor and cursor.code==0xED
        and cursor.x==cells[1].x+2,'command cursor follows the inset first cell')
      pulse('right');pulse('down');m=shot('commands-last')
      cells=Panels.cells(m,'menu');cursor=codes[1]
      check(battle.menuIndex==4 and cursor and cursor.x==cells[4].x+2
        and cursor.y==cells[4].y+8,'actual directional input selects the inset fourth cell')
      pulse('up');pulse('left');pulse('a')
      check(battle.phase=='moveSelect','actual FIGHT input opens the move grid')
      firstMove()
      shot('moves')
      local present={};for _,run in ipairs(runs)do present[run.text]=true end
      local complete=true
      for _,move in ipairs(battle.player.curMoves)do
        complete=complete and present[battle.data.moves[move.id].name]
      end
      check(complete,'all four complete authored move names fit, including seven kana')
      local pp=false;for _,run in ipairs(runs)do if run.text:match('^PP %d+/%d+$')then pp=true end end
      check(pp,'move details preserve a complete PP fraction')
      pulse('right');pulse('down');shot('moves-pp-ups')
      local move=battle.player.curMoves[4]
      local base=battle.data.moves[move.id].pp
      local expected='PP '..move.pp..'/'..(base+move.ppUps*math.floor(base/5))
      local found=false;for _,run in ipairs(runs)do if run.text==expected then found=true end end
      check(battle.moveIndex==4 and found,'fourth-cell PP includes existing PP Ups without clipping')
      firstMove()
      pulse('select');pulse('right');m=shot('moves-swap')
      local marked={};for _,c in ipairs(codes)do marked[c.code]=true end
      check(battle.moveSwapIndex~=nil and marked[0xED] and marked[0xEC],
        'SELECT origin and active move cursor both follow the inset grid')
      pulse('b')
      check(battle.phase=='menu' and battle.moveSwapIndex==nil,'B cancels move selection without a battle turn')
    end
  end
  Game.save.options.jpDialogScale=oldFactor
  Panels.draw=oldDraw
end
