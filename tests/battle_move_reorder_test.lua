-- ROM-free: the real battle update and physical/touch input paths, not a
-- standalone swap helper. Includes coalesced mobile input after a slow frame.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('battle SELECT move reorder')
local Battle=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local SaveData=require('src.core.SaveData')
local Input=require('src.core.Input')
local Game=require('src.core.Game')
local Touch=require('src.core.TouchControls')
local Font=require('src.render.Font')
local Sound=require('src.core.Sound')
local sounds={}
Sound.play=function(_,id)sounds[#sounds+1]=id end
love.graphics.getDimensions=function()return 480,800 end
local function fresh(layout)
  local data=require('tests.fixture_data').load()
  data.constants.language='ja'
  local mon=Pokemon.new(data,'FIXMON_A',10)
  mon.moves={{id='FIX_TACKLE',pp=11,ppUps=1},{id='FIX_SCRATCH',pp=17,ppUps=2},
    {id='FIX_EMBERISH',pp=3,ppUps=3},{id='FIX_CUT',pp=0,ppUps=0}}
  local options={battleLayout=layout=='wide' and 'wide' or 'classic',battleFit=layout=='responsive' and 'fill' or 'fixed'}
  local game=setmetatable({data=data,save={party={mon},options=options,inventory={},player={name='あ'}},
    input=Input,stack={push=function()end,top=function()end}}, {__index=Game})
  local state=Battle.newWild(game,'FIXMON_B',5)
  state.phase='moveSelect';state.queue={};state.moveIndex=1;state.playerMoveListIndex=1
  state.resolveTurn=function(self,move)self.resolvedMove=move end
  game.stack.top=function()return state end
  Input:init();Touch:init();Touch.active=true;Touch.img={};Touch.hotbarEnabled=false
  return state,game,mon
end
local function key(state,...)
  local game=state.game
  for i=1,select('#',...)do game:keypressed(select(i,...)) end
  Input:step();state:update(1/60)
  for i=1,select('#',...)do game:keyreleased(select(i,...)) end
  Input:step();state:update(1/60)
end
local function touch(state,...)
  local game,L=state.game,Touch:layout()
  for i=1,select('#',...)do
    local name=select(i,...);local b=L[name]
    local x,y=b and b.cx or L.dpad.cx,b and b.cy or L.dpad.cy+L.dpad.w*0.4
    game:touchpressed('touch'..i,x,y)
    game:mousepressed(x,y,1,true) -- SDL's synthetic twin must not double SELECT.
    game:touchreleased('touch'..i,x,y)
    game:mousereleased(x,y,1,true)
  end
  Input:step();state:update(1/60)
  Input:step();state:update(1/60)
end
for _,layout in ipairs({'classic','responsive','wide'})do
  local state,game,mon=fresh(layout)
  local original={unpack(mon.moves)}
  touch(state,'select')
  T.eq(state.moveSwapIndex,1,layout..' actual SELECT touch marks a move exactly once')
  key(state,layout=='wide' and 'right' or 'down')
  T.eq(state.moveIndex,2,layout..' list/grid moves to swap target')
  T.eq(state.moveSwapIndex,1,layout..' marked source remains fixed while navigating')
  touch(state,'select')
  T.eq(state.moveSwapIndex,nil,layout..' second SELECT finishes reorder')
  T.eq(mon.moves[1],original[2],layout..' destination record moves into first party slot')
  T.eq(mon.moves[2],original[1],layout..' source record moves into second party slot')
  T.eq(mon.moves[1].pp,17,layout..' remaining PP follows move')
  T.eq(mon.moves[1].ppUps,2,layout..' PP Up count follows move')
  T.eq(state.phase,'moveSelect',layout..' swapping stays in move selection')
  T.eq(state.resolvedMove,nil,layout..' swapping never spends a battle turn')
  local persisted=assert(SaveData.decode(SaveData.encode(game.save)))
  T.eq(persisted.party[1].moves[1].id,'FIX_SCRATCH',layout..' order survives save serialization')
  T.eq(persisted.party[1].moves[1].pp,17,layout..' PP survives save serialization')
  T.eq(persisted.party[1].moves[1].ppUps,2,layout..' PP Ups survive save serialization')
  state.moveIndex=2;state.player.disabledSlot=2
  key(state,'tab');key(state,layout=='wide' and 'right' or 'down');key(state,'z')
  T.eq(state.resolvedMove,nil,layout..' A confirms reorder without attacking')
  T.eq(state.moveSwapIndex,nil,layout..' A clears reorder mark')
  T.eq(state.player.disabledSlot,2,layout..' same-slot swap leaves DISABLE attached')
  state.moveIndex=1;key(state,'tab');key(state,'x')
  T.eq(state.phase,'menu',layout..' B cancels reorder back to battle commands')
  T.eq(state.moveSwapIndex,nil,layout..' cancellation clears mark')
  T.eq(mon.moves[1],original[2],layout..' cancellation does not change party order')
  state.phase='moveSelect';state.moveIndex=1
  -- Two events may arrive before one fixed update when the GPU stalls.
  -- Direction processing used to discard SELECT through an elseif chain.
  touch(state,'select','down')
  T.eq(state.moveSwapIndex,1,layout..' coalesced direction cannot swallow touch SELECT')
  state.moveSwapIndex=nil;state.moveIndex=1
  key(state,'tab','down')
  T.eq(state.moveSwapIndex,1,layout..' coalesced direction cannot swallow keyboard SELECT')
end
-- Transformed moves are borrowed. Their ordering/PP must not rewrite the
-- original party record, while the copied battle moves can still be swapped.
do
  local state,game,mon=fresh('classic')
  local original={unpack(mon.moves)}
  state.player.curMoves={{id='FIX_EMBERISH',pp=5,ppUps=0},{id='FIX_CUT',pp=2,ppUps=0}}
  local borrowed={unpack(state.player.curMoves)}
  state.player.disabledSlot=1
  key(state,'tab');key(state,'down');key(state,'tab')
  T.eq(state.player.curMoves[1],borrowed[2],'borrowed battle move records reorder')
  T.eq(state.player.curMoves[2].pp,5,'borrowed PP stays with its own move')
  T.eq(state.player.disabledSlot,2,'DISABLE follows swapped borrowed move')
  for i=1,4 do T.eq(mon.moves[i],original[i],'Transform preserves original party slot '..i)end
end
-- Mimic remembers the entry object, so its restored id follows a reordered
-- record rather than restoring whichever move later occupies the old slot.
do
  local state,game,mon=fresh('classic')
  local mimicked=mon.moves[1]
  mimicked.id='FIX_CUT';mimicked.mimic=true
  state.mimicRestores={{battler=state.player,entry=mimicked,id='FIX_TACKLE'}}
  key(state,'tab');key(state,'down');key(state,'tab')
  state:restoreMimicked(state.player)
  T.eq(mon.moves[2],mimicked,'Mimic restore follows moved entry identity')
  T.eq(mon.moves[2].id,'FIX_TACKLE','Mimic restores original id at its new slot')
  T.eq(mon.moves[2].pp,11,'Mimic reorder/restore preserves remaining PP')
  T.eq(mon.moves[2].ppUps,1,'Mimic reorder/restore preserves PP Ups')
end
-- Controller SELECT uses SDL "back", while guide belongs to the session
-- menu. It must keep working alongside a queued d-pad event.
do
  local state,game,mon=fresh('wide')
  local joystick={isGamepadDown=function()return false end}
  game:gamepadpressed(joystick,'back');game:gamepadpressed(joystick,'dpdown')
  Input:step();state:update(1/60)
  T.eq(state.moveSwapIndex,1,'controller SELECT survives a simultaneous d-pad event')
  T.eq(game.sessionMenu,nil,'controller SELECT never opens host session menu')
  game:gamepadreleased(joystick,'back');game:gamepadreleased(joystick,'dpdown');Input:step()
  key(state,'down')
  T.eq(state.moveIndex,3,'wide grid moves one row to slot three')
  game:gamepadpressed(joystick,'back');Input:step();state:update(1/60)
  game:gamepadreleased(joystick,'back');Input:step()
  T.eq(mon.moves[3].id,'FIX_TACKLE','controller SELECT completes the exchange')
  T.eq(mon.moves[3].ppUps,1,'controller exchange preserves PP Ups')
end
for _,layout in ipairs({'classic','responsive','wide'})do
  local state,game,mon=fresh(layout)
  local first,third=mon.moves[1],mon.moves[3]
  state.player.disabledSlot=1
  key(state,'tab');key(state,'down');if layout~='wide' then key(state,'down')end
  key(state,'z','up')
  T.eq(mon.moves[1],third,layout..' A confirms selected target even with queued direction')
  T.eq(mon.moves[3],first,layout..' A exchange moves original entry intact')
  T.eq(state.player.disabledSlot,3,layout..' DISABLE follows its actual moved entry')
  T.eq(state.resolvedMove,nil,layout..' A exchange does not execute an attack')
  key(state,'tab');key(state,'x','down')
  T.eq(state.phase,'menu',layout..' B cancels even with queued direction')
  T.eq(state.moveSwapIndex,nil,layout..' combined cancel clears pending exchange')
  state.phase='moveSelect';state.moveIndex=2
  key(state,'z')
  T.eq(state.resolvedMove,mon.moves[2],layout..' ordinary A still selects an attack')
  -- Record real menu draw calls, keeping genuine slot/cursor layout logic.
  state.resolvedMove=nil;state.moveSwapIndex=state.moveIndex
  Font.load(state.data)
  local draw,code,box=Font.draw,Font.drawCode,Font.drawBox
  local text={};Font.draw=function(str,x,y)text[#text+1]={str,x,y}end
  Font.drawCode=function()end;Font.drawBox=function()end
  if layout=='wide' then require('src.battle.WideBattle').draw(state)else state:drawTextArea()end
  Font.draw,Font.drawCode,Font.drawBox=draw,code,box
  local shown=false
  for _,row in ipairs(text)do if row[1]=='いれかえ' then shown=true end end
  T.check(shown,layout..' reorder label remains visible when both cursors share a slot')
end
-- Three-move grid: navigation skips the missing fourth slot and SELECT still
-- marks a valid record instead of indexing a blank entry.
do
  local state,game,mon=fresh('wide');table.remove(mon.moves,4)
  state.moveIndex=3
  key(state,'right')
  T.eq(state.moveIndex,3,'three-move grid never selects an empty fourth slot')
  key(state,'tab')
  T.eq(state.moveSwapIndex,3,'SELECT marks the third valid grid slot')
  key(state,'tab')
  T.eq(mon.moves[1].id,'FIX_EMBERISH','third grid slot swaps with remembered first slot')
  T.eq(mon.moves[1].pp,3,'third grid slot keeps its own PP after exchange')
end
T.finish()
