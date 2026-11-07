return function()
  local function block(tile)local b={};for i=1,16 do b[i]=tile end;return b end
  local data={constants={language='ja',generation=1},strings={},pokemon={},maps={},encounters={},
    tilesets={OVERWORLD={blocks={block(1),block(0x14)}}},
    field={waterTilesets={'OVERWORLD'},superRod={},townMap={locations={},cursorOrder={'ROUTE_1','ROUTE_2','MT_MOON_1F'}}}}
  local function map(id,name,wet)
    data.maps[id]={id=id,width=2,height=2,tileset='OVERWORLD',blocks={0,0,0,wet and 1 or 0}}
    data.field.townMap.locations[id]={name=name,x=name=='MT.MOON' and 7 or 1,y=1}
  end
  map('ROUTE_1','ROUTE 1');map('ROUTE_2','ROUTE 2',true)
  map('MT_MOON_1F','MT.MOON');map('MT_MOON_B1F','MT.MOON')
  map('MT_MOON_B2F','MT.MOON');map('VIRIDIAN_CITY','VIRIDIAN CITY',true)
  map('HOUSE','VIRIDIAN CITY');map('ROUTE_3','ROUTE 3')
  local names={'ポッポ','コラッタ','ピカチュウ','コイキング','トサキント','ニョロモ','ズバット','パラス',
    'ピッピ','イシツブテ','オニスズメ','アーボ','サンド','ニドラン♂','ニドラン♀','プリン','カモネギ','カビゴン'}
  local ids={'PIDGEY','RATTATA','PIKACHU','MAGIKARP','GOLDEEN','POLIWAG','ZUBAT','PARAS',
    'CLEFAIRY','GEODUDE','SPEAROW','EKANS','SANDSHREW','NIDORAN_M','NIDORAN_F','JIGGLYPUFF','FARFETCHD','SNORLAX'}
  for i,id in ipairs(ids)do data.pokemon[id]={id=id,name=names[i],dex=i}end
  data.encounters.ROUTE_1={grass={rate=25,slots={{species='PIDGEY',level=2},{species='RATTATA',level=3},
    {species='PIDGEY',level=5}}},water={rate=0,slots={{species='SNORLAX',level=40}}}}
  data.encounters.ROUTE_2={grass={rate=25,slots={{species='PIKACHU',level=5}}},
    water={rate=10,slots={{species='POLIWAG',level=20}}}}
  data.field.superRod.ROUTE_2={{species='POLIWAG',level=25},{species='GOLDEEN',level=25}}
  data.encounters.MT_MOON_1F={grass={rate=10,slots={{species='ZUBAT',level=7}}}}
  data.encounters.MT_MOON_B1F={grass={rate=10,slots={{species='PARAS',level=10},{species='ZUBAT',level=9}}}}
  data.encounters.MT_MOON_B2F={grass={rate=10,slots={{species='CLEFAIRY',level=10}}}}
  data.encounters.ROUTE_3={grass={rate=25,slots={},buckets={}}}
  for i,id in ipairs(ids)do
    data.encounters.ROUTE_3.grass.slots[i]={species=id,level=i+1}
    data.encounters.ROUTE_3.grass.buckets[i]=math.floor(i/#ids*256)
  end
  local save={options={jpDialogScale=.75},visited={VIRIDIAN_CITY=true},jpHabitatVisited={},
    pokedex={seen={PIDGEY=true,POLIWAG=true},owned={RATTATA=true}}}
  local ow={isOverworld=true,player={},map={id='ROUTE_1',def=data.maps.ROUTE_1}}
  local stack={states={ow}}
  function stack:top()return self.states[#self.states]end
  function stack:pop()return table.remove(self.states)end
  function stack:push(s)self.states[#self.states+1]=s end
  return {data=data,save=save,overworld=ow,stack=stack,input={wasPressed=function()return false end}}
end
