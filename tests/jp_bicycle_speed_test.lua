-- Actual 16px ground displacement, not animation-rate guesses: exercise the
-- bundled free movement modules through running_shoes' real adapter.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Japanese bicycle/free-camera speed')
local Game=require('src.core.Game')
local Player=require('src.world.Player')
local Data=require('tests.fixture_data').load()
Data.field.playerSprites={walk='SPRITE_FIX_PLAYER'}
Game.data=Data
local bHeld=false
Game.input={isDown=function(_,key)return key=='b' and bHeld end,wasPressed=function()return false end}
Game.save={onBike=false,options={}}
for _,renderer in ipairs({'DRAMALESS_SHAPE','DRAMATIC_SHAPE'})do
  local source=renderer=='DRAMATIC_SHAPE' and 'DRAMALESS_SHAPE' or renderer
  local FP={pointBody=function()return 'right'end,moveVector=function()return 1,0 end,
    moveWorld=function(x,z)return x,z end,releaseBody=function()end}
  local FM=assert(loadfile('vendor/jp-mods/'..source..'/lib/FreeMove.lua'))({require=function(name)
    assert(name=='FirstPerson');return FP
  end})
  local hooks,opts,defaults={},{},{}
  local mod={
    options={define=function(_,rows)for _,r in ipairs(rows)do defaults[r.key]=r.default end end,
      get=function(_,key)if opts[key]~=nil then return opts[key] end;return defaults[key]end},
    hooks={wrap=function(_,name,fn)hooks[name]=fn end},events={on=function()end},
    log={info=function()end},
    find=function(id)if id==renderer then return {id=id,version='test',exports={lib={require=function(name)
      assert(name=='FreeMove');return FM
    end}}}end end,
  }
  assert(loadfile('vendor/jp-mods/running_shoes/main.lua'))()(mod)
  opts.fx='off'
  local function travel(bike,b,boost,locked)
    FM.drop();Game.save.onBike=bike;bHeld=b;opts.bike=boost
    local p=Player.new(Data,4,4,'right');p.inputLocked=locked;p.onBike=bike
    local state={player=p,entities={},map={def={tileset='OVERWORLD'},
      inBounds=function()return true end,isWalkableCell=function()return true end},
      onStepComplete=function()end,onSlopeMap=function()return false end}
    Game.overworld=state
    local start=p.px
    for _=1,16 do
      hooks['input.step'](function()end,Game,1/60)
      FM.tick(state);p:update()
    end
    return p.px-start,p.animClock or 0
  end
  local walk,walkAnim=travel(false,false,false)
  local bike,bikeAnim=travel(true,false,false)
  T.eq(walk,16,renderer..': walking moves 16px in 16 ticks')
  T.eq(bike,32,renderer..': bicycle moves 32px in 16 ticks')
  T.eq(bikeAnim,walkAnim,renderer..': leg animation cadence stays constant while ground speed doubles')
  T.eq(travel(false,true,false),32,renderer..': B run adapter reaches actual free movement')
  T.eq(travel(true,true,false),32,renderer..': explicit boost-off preserves bicycle speed')
  T.eq(travel(true,true,nil),64,renderer..': missing bike choice defaults to B boost')
  T.eq(travel(true,true,true),64,renderer..': enabled bike boost moves 64px in 16 ticks')
  T.eq(travel(true,true,true,true),0,renderer..': locked/scripted movement is never accelerated')
  T.eq(FM.WALK,1,renderer..': walk constant restored after wrapper')
  T.eq(FM.BIKE,2,renderer..': bicycle constant restored after wrapper')
end
T.finish()
