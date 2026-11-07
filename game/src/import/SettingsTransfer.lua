-- SPDX-License-Identifier: GPL-3.0-only
-- Pure, bounded settings JSON codec. No filesystem, MOD execution or defaults.
-- The caller persists the returned candidate before replacing live options.
local Transfer = {
  FORMAT = "kanto-player-jp-settings", VERSION = 1,
  MAX_BYTES = 131072, MAX_DEPTH = 12, MAX_NODES = 8192,
}
local UIScale=require("src.ui.JapaneseUIScale")

local function fail(path, reason) error(path .. ": " .. reason, 0) end
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function validUtf8(s)
  local i=1
  while i<=#s do
    local a=s:byte(i)
    local count,low,high=0,0x80,0xbf
    if a<0x80 then count=0
    elseif a>=0xc2 and a<=0xdf then count=1
    elseif a>=0xe0 and a<=0xef then
      count=2;if a==0xe0 then low=0xa0 elseif a==0xed then high=0x9f end
    elseif a>=0xf0 and a<=0xf4 then
      count=3;if a==0xf0 then low=0x90 elseif a==0xf4 then high=0x8f end
    else return false end
    if count>0 then
      local b=s:byte(i+1);if not b or b<low or b>high then return false end
      for j=2,count do b=s:byte(i+j);if not b or b<0x80 or b>0xbf then return false end end
    end
    i=i+count+1
  end
  return true
end
local function copy(v, seen)
  if type(v)~="table" then return v end
  seen=seen or {}; if seen[v] then return seen[v] end
  local out={};seen[v]=out
  for k,value in pairs(v) do out[k]=copy(value,seen) end
  return out
end
local function object(v,path)
  if type(v)~="table" then fail(path,"expected an object") end
  for k in pairs(v) do if type(k)~="string" then fail(path,"expected object keys") end end
  return v
end
local function identifier(v,path)
  if type(v)~="string" or #v<1 or #v>128 or not v:match("^[%w_.%-]+$") then
    fail(path,"invalid identifier")
  end
  return v
end
local function boolean(v,path)
  if type(v)~="boolean" then fail(path,"expected a boolean") end
  return v
end
local function number(low,high,integer)
  return function(v,path)
    if not finite(v) or v<low or v>high or (integer and v~=math.floor(v)) then
      fail(path,"number outside allowed range")
    end
    return v
  end
end
local function choice(values)
  return function(v,path)
    for _,allowed in ipairs(values) do if v==allowed then return v end end
    fail(path,"unsupported value")
  end
end
local function boundedString(v,path)
  if type(v)~="string" or #v>1024 or not validUtf8(v) or v:find("[%z\1-\8\11\12\14-\31\127]") then
    fail(path,"invalid text")
  end
  return v
end

-- Version 1 is an allow-list, never a serialized copy of options.lua.
local scalar = {
  musicVol=number(0,7,true),sfxVol=number(0,7,true),pikaVol=number(0,7,true),
  musicFilter=number(0,3,true),textSpeed=choice({1,3,5}),
  animations=boolean,pikaCries=boolean,hotbar=boolean,reduceMotion=boolean,
  jpOriginalIntro=boolean,jpSkipIntro=boolean,jpDotMatrix=number(0,3,true),jpDialogScale=number(UIScale.MIN,UIScale.MAX),
  jpLauncherLanguage=choice({"ja","en"}),
  jpStartupScreen=choice({"home","title","continue"}),
  jpBattleSpacing=choice({"normal","wide","wider"}),
  jpBattleBlur=choice({"off","normal","strong"}),
  jpBattleIntro=choice({"focus","original"}),
  jpBattleCameraMotion=boolean,
  jpTopScreen=choice({"off","square","gb"}),
  jpTopScreenSize=number(50,100,true),
  jpTopScreenY=number(0,100,true),
  jpTopScreenX=number(0,100,true),
  jpFxMoveLight=boolean,jpFxHitReaction=boolean,jpFxIdle=boolean,
  jpFxStatus=boolean,jpFxBattleEnvironment=boolean,
  jpFxGrass=boolean,jpFxFootsteps=boolean,jpFxWater=boolean,
  jpFxWind=boolean,jpFxAmbient=boolean,
  jpFxAfterglow=boolean,jpFxCritical=boolean,jpFxTracks=boolean,jpFxLightShafts=boolean,
  jpFxDensity=choice({'low','normal','high'}),
  jpAtmosphere=choice({"soft","gentle","off"}),
  jpPartyExp=boolean,jpForgetHM=boolean,jpReusableTM=boolean,
  jpMoveReminder=boolean,
  jpFollower=boolean,jpRepelRepeat=boolean,
  jpFieldActions=boolean,jpAnalogWalk=boolean,jpAutoSave=boolean,jpTouchStick=boolean,jpTouchOptimized=choice({false,true,'buttons'}),
  battleStyle=choice({"shift","set"}),battleLayout=choice({"og","wide"}),
  battleFit=choice({"fixed","fill"}),battleHud=choice({"standard","extended"}),
  battleBg=choice({"white","black","world"}),uiLayout=choice({"centered","dynamic"}),
  colors=choice({"ogred","gbc","redpp","redpp_soft","og","og_inv","gbc_inv","classic"}),
  palette=function(v,p) if v=="" then return v end return identifier(v,p) end,
  tilt=number(0,3,true),zoom=number(-64,64,true),faithfulRes=number(0,4,true),
  voidFill=choice({"trees","water","black"}),uiLetterbox=choice({"auto","black","white","palette"}),
  videoMode=choice({"windowed","borderless"}),screenPos=choice({"center","upper","top"}),
  fpsCap=choice({0,30,40,50,60,75,90,100,120,144,160}),vsync=choice({"on","off","adaptive"}),
  logicClock=choice({"60","gb"}),performance=choice({"auto","high","balanced","low"}),
  orientation=choice({"auto","portrait","landscape","reverseLandscape"}),
  haptics=choice({"off","light","normal","strong"}),
  dateFormat=choice({"device","dmy","mdy","ymd"}),timeFormat=choice({"device","24h","12h"}),
  ruleset=identifier,
}
for _,key in ipairs({"speedOverworld","speedBattle","speedMenu"}) do
  scalar[key]=choice({1,2,3,4,10,20,30,50,75,100,200})
end

local function map(v,path,validator)
  object(v,path);local out={}
  local count=0
  for key,value in pairs(v) do
    count=count+1;if count>256 then fail(path,"too many entries") end
    identifier(key,path.." key");out[key]=validator(value,path.."."..key)
  end
  return out
end
local function fields(v,path,defs)
  object(v,path);local out={}
  for k,value in pairs(v) do
    if not defs[k] then fail(path.."."..k,"unsupported setting") end
    out[k]=defs[k](value,path.."."..k)
  end
  return out
end
local position=function(v,path)
  return fields(v,path,{x=number(0,1),y=number(0,1)})
end
local touchArea=function(v,path)
  return fields(v,path,{x=number(0,1),y=number(0,1),size=number(.08,.35),enabled=boolean})
end
local touchAreaLayout=function(v,path)
  return fields(v,path,{back=touchArea,menu=touchArea})
end
local positions=function(v,path)
  return fields(v,path,{dpad=position,a=position,b=position,start=position,select=position,
    l=position,r=position})
end
local layout=function(v,path)
  return fields(v,path,{scale=number(0.6,1.6),positions=positions})
end
local function touch(v,path)
  return fields(v,path,{enabled=boolean,skin=identifier,scale=number(0.6,1.6),positions=positions,
    layouts=function(x,p)return fields(x,p,{portrait=layout,landscape=layout})end})
end
local function binding(v,path)
  local function name(x,p)
    if type(x)~="string" or #x<1 or #x>32 or not validUtf8(x) or x:find("[%z\1-\31\127]") then fail(p,"invalid button name") end
    return x
  end
  if v==false then return false end
  if type(v)=="string" then return name(v,path) end
  return fields(v,path,{key=name,pad=name})
end
local function bindings(v,path)
  local defs={}
  for _,key in ipairs({"up","down","left","right","a","b","start","select","l","r","speedUp","speedDown"}) do defs[key]=binding end
  return fields(v,path,defs)
end

local sensitiveWords={"auth","token","secret","password","passwd","credential","cookie",
  "session","account","login","sync","private","endpoint","server","hostname","url","uri",
  "path","directory","folder","file","apikey","accesskey","refreshkey"}
local function sensitive(key)
  local k=key:lower():gsub("[^%w]","")
  if k=="key" or k=="file" or k=="host" then return true end
  for _,word in ipairs(sensitiveWords) do if k:find(word,1,true) then return true end end
  return false
end
local function pathValue(v)
  return v:find("/",1,true) or v:find("\\",1,true)
end
local function generic(v,path,mode,state,depth)
  state.nodes=state.nodes+1
  if state.nodes>Transfer.MAX_NODES or depth>8 then fail(path,"MOD settings exceed size/depth limit") end
  local kind=type(v)
  if kind=="boolean" then return v end
  if kind=="number" then return number(-1000000,1000000)(v,path) end
  if kind=="string" then
    boundedString(v,path)
    if pathValue(v) then
      if mode=="export" then return nil end
      fail(path,"file paths and URLs are not transferable")
    end
    return v
  end
  if kind~="table" or getmetatable(v)~=nil then fail(path,"expected plain JSON data") end
  if state.seen[v] then fail(path,"cyclic MOD settings") end
  state.seen[v]=true
  local out={};local count=0;local array=false;local stringKeys=false
  for key,value in pairs(v) do
    count=count+1
    if count>256 then fail(path,"too many MOD settings") end
    if type(key)=="number" then
      array=true
      if key<1 or key>256 or key~=math.floor(key) then fail(path,"invalid array index") end
      out[key]=generic(value,path.."["..key.."]",mode,state,depth+1)
      if out[key]==nil then fail(path,"path-valued array entries cannot be exported") end
    elseif type(key)=="string" then
      stringKeys=true;identifier(key,path.." key")
      if sensitive(key) then
        if mode~="export" then fail(path.."."..key,"private setting is not transferable") end
      else out[key]=generic(value,path.."."..key,mode,state,depth+1) end
    else fail(path,"invalid JSON key") end
  end
  if array then
    if stringKeys or #out~=count then fail(path,"mixed or sparse array") end
    for i=1,count do if out[i]==nil then fail(path,"sparse array") end end
  end
  state.seen[v]=nil
  return out
end
local function sanitize(options,mode)
  object(options,"options")
  local out={};local state={nodes=0,seen={}}
  local complex={
    touchControls=touch,bindings=bindings,
    jpTouchAreas=function(v,p)return fields(v,p,{portrait=touchAreaLayout,landscape=touchAreaLayout})end,
    pipelines=function(v,p)return map(v,p,number(0,100,true))end,
    mods=function(v,p)return map(v,p,boolean)end,
    modsByVersion=function(v,p)return map(v,p,function(x,q)return map(x,q,boolean)end)end,
    modOptions=function(v,p)
      return map(v,p,function(x,q)
        object(x,q);return generic(x,q,mode,state,0)
      end)
    end,
  }
  for k,v in pairs(options) do
    local validate=scalar[k] or complex[k]
    if validate then out[k]=validate(v,"options."..k)
    elseif mode~="export" then fail("options."..tostring(k),"unsupported or private setting") end
  end
  -- Accept old exported files, but emit/merge one unambiguous option. Do
  -- this before applying the patch so a legacy import overrides live defaults.
  if out.jpSkipIntro == nil and out.jpOriginalIntro ~= nil then out.jpSkipIntro = not out.jpOriginalIntro end
  out.jpOriginalIntro = nil
  return out
end

-- Strict decoder: reject trailing bytes, duplicate names, null (no deletion
-- semantics), non-JSON numbers, invalid escapes and excessive structure.
local function decode(text)
  if type(text)~="string" or #text>Transfer.MAX_BYTES then fail("JSON","invalid input size") end
  local i,nodes=1,0
  local function ws() local _,e=text:find("^[ \t\r\n]*",i);i=(e or i-1)+1 end
  local function utf8(n)
    if n<128 then return string.char(n) end
    if n<2048 then return string.char(192+math.floor(n/64),128+n%64) end
    if n<65536 then return string.char(224+math.floor(n/4096),128+math.floor(n/64)%64,128+n%64) end
    return string.char(240+math.floor(n/262144),128+math.floor(n/4096)%64,128+math.floor(n/64)%64,128+n%64)
  end
  local function stringValue()
    if text:sub(i,i)~='"' then fail("JSON","object key must be quoted") end
    i=i+1;local out={}
    while i<=#text do
      local c=text:sub(i,i);i=i+1
      if c=='"' then
        local result=table.concat(out);if not validUtf8(result) then fail("JSON","invalid UTF-8") end
        return result
      end
      if c=='\\' then
        local e=text:sub(i,i);i=i+1
        local escapes={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
        if escapes[e] then out[#out+1]=escapes[e]
        elseif e=='u' then
          local h=text:sub(i,i+3);if not h:match('^%x%x%x%x$') then fail("JSON","invalid unicode escape") end
          local cp=tonumber(h,16);i=i+4
          if cp>=0xd800 and cp<=0xdbff then
            local low=text:sub(i+2,i+5)
            if text:sub(i,i+1)~='\\u' or not low:match('^%x%x%x%x$') then fail("JSON","missing unicode low surrogate") end
            low=tonumber(low,16);if low<0xdc00 or low>0xdfff then fail("JSON","invalid unicode surrogate") end
            cp=65536+(cp-0xd800)*1024+low-0xdc00;i=i+6
          elseif cp>=0xdc00 and cp<=0xdfff then fail("JSON","unexpected unicode surrogate") end
          out[#out+1]=utf8(cp)
        else fail("JSON","invalid escape") end
      else
        if c:byte()<32 then fail("JSON","unescaped control character") end
        out[#out+1]=c
      end
    end
    fail("JSON","unterminated string")
  end
  local value
  value=function(depth)
    nodes=nodes+1;if depth>Transfer.MAX_DEPTH or nodes>Transfer.MAX_NODES then fail("JSON","too large or deeply nested") end
    ws();local c=text:sub(i,i)
    if c=='"' then return stringValue() end
    if c=='{' or c=='[' then
      local obj,isObj={},c=='{';i=i+1;ws()
      local close=isObj and '}' or ']'
      if text:sub(i,i)==close then i=i+1;return obj end
      local names={}
      while true do
        ws();local key
        if isObj then
          key=stringValue();if names[key] then fail("JSON","duplicate object key") end;names[key]=true
          ws();if text:sub(i,i)~=':' then fail("JSON","expected colon") end;i=i+1
        else key=#obj+1 end
        obj[key]=value(depth+1);ws();local delimiter=text:sub(i,i);i=i+1
        if delimiter==close then return obj end
        if delimiter~=',' then fail("JSON","expected comma or closing bracket") end
      end
    end
    for literal,result in pairs({["true"]=true,["false"]=false}) do
      if text:sub(i,i+#literal-1)==literal then i=i+#literal;return result end
    end
    local raw=text:match('^[^,%]%}%s]+',i)
    if not raw then fail("JSON","expected value") end
    local mantissa,exp=raw:match('^([^eE]+)[eE]([+-]?%d+)$')
    if not mantissa then mantissa=raw;if raw:find('[eE]') then fail("JSON","invalid number") end end
    local integer,fraction=mantissa:match('^(-?%d+)%.(%d+)$')
    if not integer then integer=mantissa end
    local digits=integer:gsub('^-','')
    if not integer:match('^-?%d+$') or (#digits>1 and digits:sub(1,1)=='0') then fail("JSON","invalid number or null") end
    local result=tonumber(raw);if not finite(result) then fail("JSON","non-finite number") end
    i=i+#raw;return result
  end
  local result=value(0);ws();if i<=#text then fail("JSON","trailing content") end
  return result
end

local function encode(v)
  if type(v)~="table" then return require("src.link.Json").encode(v) end
  local array=#v>0;local pieces={}
  if array then
    for i=1,#v do pieces[i]=encode(v[i]) end
    return '['..table.concat(pieces,',')..']'
  end
  local keys={};for k in pairs(v) do keys[#keys+1]=k end;table.sort(keys)
  for _,k in ipairs(keys) do pieces[#pieces+1]=encode(k)..':'..encode(v[k]) end
  return '{'..table.concat(pieces,',')..'}'
end
local function merge(target,patch)
  for k,v in pairs(patch) do
    if type(v)=="table" and #v==0 and type(target[k])=="table" and #target[k]==0 then
      merge(target[k],v)
    else target[k]=copy(v) end
  end
  return target
end
function Transfer.export(options)
  local ok,result=pcall(function()
    local text=encode({format=Transfer.FORMAT,version=Transfer.VERSION,options=sanitize(options,"export")})
    if #text+1>Transfer.MAX_BYTES then fail("JSON","export exceeds size limit") end
    return text.."\n"
  end)
  if ok then return result end
  return nil,tostring(result)
end
function Transfer.import(text,current)
  local ok,result=pcall(function()
    object(current,"current options")
    local document=object(decode(text),"JSON")
    for key in pairs(document) do
      if key~="format" and key~="version" and key~="options" then fail("JSON","unsupported envelope field") end
    end
    if document.format~=Transfer.FORMAT or document.version~=Transfer.VERSION then fail("JSON","unsupported settings format/version") end
    local patch=sanitize(document.options,"import")
    return merge(copy(current),patch)
  end)
  if ok then return result end
  return nil,tostring(result)
end

return Transfer
