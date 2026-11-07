package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('jp24 item sorting')
package.loaded['src.core.Sound']={play=function()end}
package.loaded['src.render.TextBox']={new=function(_,text)return {text=text}end,soundOpts=function()end}
local Data=require('tests.modkit.fixtures').fresh()
Data.constants.language='ja'
require('src.render.Font').load(Data)
require('src.core.Strings').load(Data)
require('src.core.GameVersion').set('red_jp')
local Save=require('src.core.SaveData')
local Bag=require('src.inventory.Bag')
local Sort=require('src.inventory.BagSort')
local Menu=require('src.ui.BagMenu')
local Input=require('src.core.Input')
local Stack=require('src.core.StateStack')
local Effects=require('src.inventory.ItemEffects')
local Fixture=require('tests.jp24_bag_sort_fixture')
local game={data=Data,input=Input,stack=Stack}
local useCalls,turnCalls,usedId=0,0,nil
Effects.use=function(_,_,id)useCalls=useCalls+1;usedId=id;return 'failed',{}end
local function reset()
  game.save=Save.newGame();game.save.version='red_jp';Fixture(Data,game.save)
  Input:init();Stack:init();useCalls,turnCalls,usedId=0,0,nil
end
local function press(key)
  Input:sourcePress(key,'sort-test');Input:step();Stack:update(1/60)
  Input:sourceRelease(key,'sort-test');Input:step();Stack:update(1/60)
end
local function selectId(list,id)
  for i,row in ipairs(list.items)do if row.value==id then list.index=i;return end end
  error('missing item '..id)
end
local function invariant(inv,ref,orderRef,favorite)
  T.eq(game.save.inventory,ref,'quantity table identity remains unchanged')
  T.eq(Save.encode(game.save.inventory),inv,'every quantity/key/badge preserved exactly')
  T.eq(game.save.bagOrder,orderRef,'bagOrder table identity remains valid for existing MOD/menu references')
  T.eq(game.save.registeredItem,favorite,'registered SELECT favorite is untouched')
  local seen={};local valid=true
  for _,id in ipairs(game.save.bagOrder)do
    valid=valid and not seen[id] and game.save.inventory[id]~=nil and not Bag.isBadge(id)
    seen[id]=true
  end
  for id in pairs(game.save.inventory)do if not Bag.isBadge(id)then valid=valid and seen[id]end end
  T.check(valid,'each bag item appears exactly once and badge is not a row')
end
for _,mode in ipairs({'category','name'})do
  reset()
  local ref,ord=game.save.inventory,game.save.bagOrder
  local inv=Save.encode(ref)
  T.check(Sort.apply(game.save,Data,mode),'sort mode accepted '..mode)
  invariant(inv,ref,ord,'BICYCLE')
  local once=Save.encode(ord);Sort.apply(game.save,Data,mode)
  T.eq(Save.encode(ord),once,'repeating same sort is stable '..mode)
  local function at(id)for i,v in ipairs(ord)do if v==id then return i end end end
  T.check(at('DUP_A')<at('DUP_B'),'identical names preserve their original relative order')
  if mode=='category'then
    T.check(at('POTION')<at('POKE_BALL') and at('POKE_BALL')<at('X_ATTACK')
      and at('X_ATTACK')<at('MOON_STONE') and at('MOON_STONE')<at('TM_MEGA')
      and at('TM_MEGA')<at('TM_THUNDER') and at('TM_THUNDER')<at('HM_CUT')
      and at('HM_CUT')<at('BICYCLE'),'category order and TM/HM number order are consistent')
  else
    T.check(at('MOD_A')<at('MOD_Z') and at('MOD_Z')<at('POTION')
      and at('POTION')<at('BICYCLE'),'Japanese kana/name order folds katakana with hiragana')
  end
  local loaded=assert(Save.decode(Save.encode(game.save)))
  T.eq(Save.encode(loaded.bagOrder),once,'ordinary serializer retains chosen order')
  T.eq(loaded.registeredItem,'BICYCLE','ordinary serializer retains favorite')
  T.eq(Save.encode(loaded.inventory),inv,'ordinary serializer retains quantities')
  T.check(Save.save(game.save),'ordinary save accepts sorted bag')
  loaded=assert(Save.load('red_jp'))
  T.eq(Save.encode(loaded.bagOrder),once,'ordinary load restores sorted bag order')
  T.eq(loaded.registeredItem,'BICYCLE','ordinary load restores registered favorite')
end

-- Bottomless Bag patches capacity to 255; sorting must cover every slot.
reset();Data.constants.bagSize=255
for i=1,240 do
  local id=('MOD_%03d'):format(i)
  Data.items[id]={name=('どうぐ%03d'):format(241-i),index=100+i}
  T.check(Bag.add(game.save,id,i%99+1,Data),'large mod bag accepts item '..i)
end
local ref,ord=game.save.inventory,game.save.bagOrder;local inv=Save.encode(ref)
Sort.apply(game.save,Data,'name');invariant(inv,ref,ord,'BICYCLE')
T.eq(#ord,254,'all 254 Bottomless Bag entries are kept')
T.eq(Bag.capacity(Data),255,'sorting never changes MOD capacity')

for _,battleMode in ipairs({false,true})do
  reset()
  local battle=battleMode and {itemUsed=function()turnCalls=turnCalls+1 end}or nil
  local list=Menu.new(game,{battle=battle});Stack:push(list)
  selectId(list,'POKE_BALL')
  local selected=list.items[list.index].value
  local before=Save.encode(game.save)
  press('start');T.eq(Stack:top().title,'ならべかえ','START opens visible sort choice')
  press('b');T.eq(Stack:top(),list,'B returns to same bag without closing it')
  T.eq(Save.encode(game.save),before,'cancel changes no save content')
  press('select');local pending=list.swapIndex
  T.eq(pending,list.index,'SELECT still begins original manual swap')
  press('start');press('start')
  T.eq(Stack:top(),list,'START also cancels the sort popup')
  T.eq(list.swapIndex,pending,'cancel keeps pending manual swap intact')
  press('start');press('a')
  T.eq(Stack:top(),list,'sort completes into same bag')
  T.eq(list.swapIndex,nil,'successful sort clears stale manual swap index')
  T.eq(list.items[list.index].value,selected,'selected item follows its new slot')
  T.check(list.index>list.scroll and list.index<=list.scroll+(list.cursorRows or list.rows),'cursor stays in visible rows')
  T.eq(useCalls,0,'opening/sorting never invokes item use')
  T.eq(turnCalls,0,'sorting never consumes battle turn')
  T.eq(game.save.registeredItem,'BICYCLE','battle/field sorting keeps registered tool')
  local reopen=Menu.new(game,{battle=battle})
  T.eq(reopen.items[reopen.index].value,selected,'reopening bag restores sorted selection')
  if battleMode then
    press('a')
    T.eq(useCalls,1,'only explicit A enters native item use after sorting')
    T.eq(usedId,selected,'native item use resolves selected id after slot changes')
    T.eq(turnCalls,0,'refused item use retains original non-consuming behavior')
  end
  -- The cancel pseudo-item can be sorted without becoming a usable id.
  list.index=#list.items;press('start');press('down');press('a')
  T.check(list.items[list.index].cancel,'sorting while on CANCEL retains CANCEL')
  press('a');T.eq(Stack:top(),nil,'CANCEL still closes bag')
end

reset();local list=Menu.new(game);Stack:push(list);selectId(list,'BICYCLE')
press('start');press('down');press('a');press('select')
T.eq(game.save.registeredItem,nil,'SELECT unregister still works after name sort')
Stack:pop();press('select')
T.eq(game.save.registeredItem,'BICYCLE','SELECT registration still works after name sort')
Stack:pop();selectId(list,'POTION');press('select');local first=list.swapIndex
selectId(list,'ANTIDOTE');local second=list.index;press('a')
T.eq(game.save.bagOrder[first],'ANTIDOTE','manual swap source preserved after sort')
T.eq(game.save.bagOrder[second],'POTION','manual swap destination preserved after sort')
T.eq(useCalls,0,'manual swap never uses the swapped item')

reset();game.save.inventory={};game.save.bagOrder={};game.save.registeredItem=nil
list=Menu.new(game);Stack:push(list);press('start');press('a')
T.eq(#list.items,1,'empty bag still has exactly CANCEL')
T.check(list.items[1].cancel,'empty bag sorting is safe')
T.eq(Sort.apply(game.save,Data,'invalid'),false,'unknown mode does not modify save')
Data.constants.language='en';list=Menu.new(game);Stack.states={list};press('start')
T.eq(Stack:top(),list,'foreign-language bag retains original START behavior')
T.eq(list.footer,nil,'foreign-language bag does not receive Japanese instructions')
T.finish()
