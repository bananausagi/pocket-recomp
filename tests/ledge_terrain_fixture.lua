-- Original synthetic map/art only. No ROM, map dump or copyrighted image.
local F={}
function F.key(x,y)return (y+64)*4096+x+64 end
function F.new()
  local root=os.getenv('JP_QA_ROOT') or '.'
  local dir=root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/'
  local f={ticks=0,queries=0,modules={}}
  local m=f.modules
  m.BuildBudget={tick=function()f.ticks=f.ticks+1 end,check=function()end,begin=function()end,finish=function()end}
  m.ModSetting={new=function(_,_,values)return {get=function()return values[1]end}end}
  m.VoxelState={angle=.8,FOCAL=1}
  m.WorldCurve={k=function()return 0 end}
  m.ThirdPerson={place=function(eye,_,_,_,focus)return eye,focus end}
  m.BattleCameraBlend={active=function()return false end,applyReturn=function(p)return p end}
  m.Structures={forMap=function(map)return map.S end}
  m.TileShape={forMap=function(map)return map.shapes end}
  package.loaded['src.render.Assets']={register=function()end}
  package.loaded['src.render.PaletteFX']={}
  package.loaded['src.core.Game']={data={field={}}}
  local real={NeighborVisibility=true,CliffTerrain=true,ChunkMesher=true,Voxel3D=true,VoxelScene=true,Mat4=true,FirstPerson=true}
  local V={}
  function V.require(name)
    if m[name] then return m[name] end
    if real[name] then m[name]=assert(loadfile(dir..name..'.lua'))(V)
    else m[name]={} end
    return m[name]
  end
  f.V=V
  f.T=V.require('CliffTerrain')
  f.Mesher=V.require('ChunkMesher')
  f.Scene=V.require('VoxelScene')
  f.Camera=V.require('Voxel3D')
  f.FP=V.require('FirstPerson')
  function f:map(id,w,h)
    local map={id=id,widthCells=w,heightCells=h,
      def={id=id,width=w/2,height=h/2,tileset='OVERWORLD'},
      tileset={id='OVERWORLD',image='synthetic-atlas',tilesPerRow=16,imageWidth=128,imageHeight=64,blocks={}},
      cells={},doorTiles={},warps={}}
    map.shapes={
      [44]={class='ground',h=0,art='flat',flat=true},
      [55]={class='ledge',h=6,art='top',authored=true},
      [39]={class='ledge',h=6,art='top',authored=true},
      [13]={class='ledge',h=6,art='top',authored=true},
      [99]={class='wall',h=16,art='upright',authored=true},
      [20]={class='water',h=-2,art='flat',flat=true},
      [82]={class='grass',h=0,art='grass',flat=true},
    }
    function map:inBounds(x,y)return x>=0 and y>=0 and x<w and y<h end
    function map:cellTile(x,y)f.queries=f.queries+1;return self.cells[F.key(x,y)] or (self:inBounds(x,y) and 44 or 99)end
    function map:tileAt(tx,ty)
      local id=self:cellTile(math.floor(tx/2),math.floor(ty/2))
      if (id==55 or id==39 or id==13) and ty%2==0 then return 44 end
      return id
    end
    function map:isWalkableCell(x,y)local t=self:cellTile(x,y);return t==44 or t==82 end
    function map:isWaterCell(x,y)return self:cellTile(x,y)==20 end
    function map:warpAtCell(x,y)return self.warps[F.key(x,y)] end
    function map:isWarpTileCell()return false end
    function map:resolve()
      local S={shapeAt={},tileAt={},runs={},skip={},ground={},objectQuads={},grassQuads={},flowerQuads={},roundStamps={}}
      for ty=0,h*2-1 do for tx=0,w*2-1 do
        local tile=self:tileAt(tx,ty);local k=F.key(tx,ty)
        S.tileAt[k]=tile;S.shapeAt[k]=self.shapes[tile]
      end end
      self.S=S;return S
    end
    map:resolve()
    return map
  end
  f.rules={{input='down',facing='down',standingTile=44,ledgeTile=55},
           {input='left',facing='left',standingTile=44,ledgeTile=39},
           {input='right',facing='right',standingTile=44,ledgeTile=13}}
  function f:data(maps)
    local ts={id='OVERWORLD',walkable={44,82},waterTiles={20},shoreTiles={},blocks={}}
    local blockIDs={}
    local data={maps={},tilesets={OVERWORLD=ts},field={ledges=self.rules}}
    for _,map in ipairs(maps)do
      map.def.blocks={}
      for by=0,map.def.height-1 do for bx=0,map.def.width-1 do
        local block={}
        for y=0,3 do for x=0,3 do block[#block+1]=map:tileAt(bx*4+x,by*4+y)end end
        local signature=table.concat(block,',');local id=blockIDs[signature]
        if id==nil then id=#ts.blocks;blockIDs[signature]=id;ts.blocks[id+1]=block end
        map.def.blocks[#map.def.blocks+1]=id
      end end
      data.maps[map.id]=map.def
    end
    return data
  end
  function f:build(map,data)
    map:resolve();map.S.terrain=self.T.build(map,map.S,self.rules,data)
    return map.S.terrain
  end
  return f
end
return F
