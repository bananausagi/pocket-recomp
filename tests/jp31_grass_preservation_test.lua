-- Runs the real battle scene through a recording graphics boundary. The
-- meshes stand for grass under both battlers and in the translated neighbour.
-- No GPU/ROM is needed; this verifies the uniforms sent for those draw calls.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('jp31 battle grass preservation')
local Json=require('src.link.Json')
local folder='vendor/jp-mods/DRAMALESS_SHAPE/lib/'
local scenePath=os.getenv('JP_GRASS_SCENE') or folder..'VoxelBattleScene.lua'
local useAddon=os.getenv('JP_GRASS_ADDON')=='1'
local w,h=800,480
local g=love.graphics
for _,name in ipairs({'push','pop','origin','setScissor','setStencilTest',
  'setCanvas','setShader','setDepthMode','setBlendMode','setColor'})do g[name]=function()end end
g.getScissor=function()end;g.getCanvas=function()end;g.getShader=function()end
g.getDepthMode=function()return 'less',true end
g.getBlendMode=function()return 'alpha','alphamultiply' end
g.getColor=function()return 1,1,1,1 end
package.loaded['src.render.Renderer']={frameRects=function()return {pw=w,ph=h,Up=h/144}end}
package.loaded['src.battle.BattlePresentation']={metrics=function()return {}end,filmOffset=function()return 0,0 end}
package.loaded['src.render.PaletteFX']={pal=function()return {}end}
package.loaded['src.world.Map']={isOutdoor=function()return true end}
package.loaded['src.core.Game']={data={}}

local host={id='host',def={},texture={}}
local nextMap={id='neighbor',def={},texture={}}
local maps={host,nextMap}
local floor={kind='floor'}
local grassA,grassB={kind='grass',map=host},{kind='grass',map=nextMap}
local flower={kind='flower'}
local water={kind='water'}
local lowered,decorated,clip=false,false,false
local draws,clearCalls,failGrass={},0,false
local canvas={}
local v3={vp={},nearPlane=.1,farPlane=1000,fovY=.9,
 available=function()return true end,
 beginScene=function()
  lowered,decorated,clip=false,false,false
  return true
 end,
 canvas=function()return canvas end,depthTexture=function()return {}end,
 endWater=function()end,endScene=function()return canvas end,
 grassClearance=function(a,b)
  lowered=a~=nil or b~=nil;decorated=lowered
  if lowered then clearCalls=clearCalls+1 end
 end,
 battleDecoration=function(enabled)decorated=enabled==true end,
 battleLowObjects=function()end,
 foliage=function()end,effects=function()end,
 battleOcclusion=function(spots,stage)clip=spots~=nil and stage==true end,
 draw=function(mesh,texture,model)
  if not mesh then return end
  if failGrass and mesh.kind=='grass' then error('fixture grass draw failure')end
  draws[#draws+1]={kind=mesh.kind,map=mesh.map,lowered=lowered,decorated=decorated,clip=clip,model=model}
 end}
v3.eye={0,35,60};v3.focus={0,0,0}
local mods={Mat4=dofile(folder..'Mat4.lua'),Voxel3D=v3,
 SceneEffects={bind=function()end,draw=function()end},
 ChunkMesher={grass=function(map)return map==host and grassA or grassB end,flowers=function()return flower end},
 TerrainAtlas={forMap=function(map)return map.texture end},
 VoxelScene={prefetch=function()return floor,{floor},water,{water}end,
  groundAt=function(_,x)return x and x<0 and 4 or 0 end,
  _modeColors=function()return {}end,skyColor=function()return {0,0,0,1}end,
  pull=function()return 3 end,castBattleShadows=function()end},
 BattleCam={frameH=function()return 144 end},
 DayNight={applyRig=function()end,tint=function()return {1,1,1}end,isCanopy=function()return false end,windowLight=function()return 0 end},
 GlassMask={texture=function()return {}end},
 AntiAlias={expand=function(a,b)return a,b end,resolve=function(c)return c end},
 TiltShift={battleBackground=function()end},
 Structures={forMap=function()return {shapeAt={}}end},
 VoxelBattleCardProvider={presentationBounds=function()return {width=40,height=56,worldYOffset=4}end},
 BattleIntroFocus={pose=function(_,c)return c end},
 BattleActionCamera={pose=function(_,c)return c end,finish=function()end},
 BattleCameraBlend={copy=function(c)return c end}}
local V={require=function(name)return assert(mods[name],name)end}
local scene=assert(loadfile(scenePath))(V)
local addonEnabled=true
local event
if useAddon then
 local mod={id='JP_GRASS_PRESERVE',exports={},
  find=function(id)
   if id=='DRAMALESS_SHAPE' then return {exports={lib=V}}end
   if id=='JP_GRASS_PRESERVE' and addonEnabled then return {}end
  end,
  events={on=function(_,name,fn)T.eq(name,'mods.loaded','hotfix uses the public load event');event=fn end},
  log={info=function()end}}
 assert(loadfile('mods-local/JP_GRASS_PRESERVE/main.lua'))(mod)
 event();local wrapped=v3.grassClearance;event()
 T.eq(v3.grassClearance,wrapped,'repeated load notification does not stack wrappers')
 T.eq(mod.exports.applied,true,'host export accepted')
end
local state={map=host,neighbors={{map=nextMap,ox=64,oy=-32}},paletteNameFor=function()return 'TEST'end}
local arena={map=host,encounter=true,player={-16,8},enemy={16,-8},playerCell={-1,0},enemyCell={1,-1},mid={0,0}}
local function render()
 return scene.render(state,arena,function()draws[#draws+1]={kind='actor',lowered=lowered,decorated=decorated,clip=clip}end,
  {pose={eye=v3.eye,focus=v3.focus,fov=.9},pitch=.4})
end
for _,size in ipairs({{800,480},{480,800}})do
 w,h=size[1],size[2]
 for _,fallback in ipairs({false,true})do
  arena.backgroundOnly=fallback;draws={};clearCalls=0
  T.eq(render(),canvas,'scene succeeds with live actor bounds')
  local grassCount=0
  for _,draw in ipairs(draws)do
   if draw.kind=='grass' then
    grassCount=grassCount+1
    T.check(not draw.lowered,'grass under both battlers keeps its original height')
    T.check(draw.decorated,'grass still bypasses lens-near tall-object clipping')
    if draw.map==nextMap then T.check(draw.model~=nil,'translated adjacent-map grass is included')end
   elseif draw.kind=='floor' then T.check(draw.clip,'tall scenery clearance remains enabled for terrain')
   elseif draw.kind=='actor' then T.check(not draw.lowered and not draw.decorated and not draw.clip,'actor pass receives clean state')
   else T.check(draw.decorated and not draw.lowered,'water and flowers retain their geometry')end
  end
  T.eq(grassCount,2,'host and adjacent grass passes both execute')
  T.eq(clearCalls,0,'no grass-lowering operation is requested')
  T.eq(v3.camera,nil,'scene releases camera ownership')
 end
end
arena.backgroundOnly=false;failGrass=true
local ok=pcall(render)
T.check(not ok,'failed grass drawing is propagated')
T.check(not lowered and not clip,'failed drawing clears transient grass and clipping state')
T.eq(v3.camera,nil,'failed drawing releases camera ownership')
if useAddon then
 addonEnabled=false;v3.grassClearance({0,0,0},{1,0,0},16)
 T.check(lowered,'disabling the hotfix restores the original operation')
 addonEnabled=true;v3.grassClearance({0,0,0},{1,0,0},16)
 T.check(not lowered and decorated,'reenabling preserves grass and its clipping protection')
 v3.grassClearance()
 T.check(not lowered and not decorated,'explicit cleanup keeps original reset semantics')
end
local out=os.getenv('JP_GRASS_RESULT')
if out then local f=assert(io.open(out,'w'));f:write(Json.encode({checks=T.checks,failures=T.failures,messages=T.messages,actualGL=false,addon=useAddon}));f:close()end
T.finish()
