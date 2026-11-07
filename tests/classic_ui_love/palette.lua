-- Real GPU pixels: palette mapping is local to the session canvas, including
-- alpha, and never inherits or changes the world's transient shade registers.
return function(UI, check, write)
  local g = love.graphics
  local FX = require("src.render.PaletteFX")
  local Palette = require("src.render.Palette")
  local oldMode, oldRamp, oldMap = FX.mode, FX.customRamp, FX.shadeMap()
  local sentinelMap = { [0]=3, [1]=3, [2]=3, [3]=3 }
  local sentinelRamp = { {2,3,4}, {5,6,7}, {8,9,10}, {11,12,13} }
  FX.mode, FX.customRamp = "og_inv", sentinelRamp
  FX.setShadeMap(sentinelMap)
  local base = { {240,224,208}, {160,144,128}, {80,64,48}, {16,8,0} }
  local game = { data={palettes={palettes={MEWMON=base}}}, save={options={}} }
  local background = { 0.2, 0.3, 0.4, 1 }
  local function pixel(data,x,y,expected)
    local got={data:getPixel(x,y)}
    for i=1,4 do if math.abs(got[i]-expected[i])>0.009 then return false end end
    return true
  end
  local function rgba(rgb,alpha)
    return {rgb[1]/255,rgb[2]/255,rgb[3]/255,alpha or 1}
  end
  local function draw(options, transparent, home)
    game.save.options=options
    local target=g.newCanvas(200,180,{dpiscale=1})
    g.setCanvas(target);g.clear(unpack(transparent and {0,0,0,0} or background))
    UI.begin(not home and game or nil,{rect={0,0,160,144},paper={0,0,0,0}})
    for i,shade in ipairs({1,0,0.7})do
      g.setColor(shade,shade,shade,1);g.rectangle("fill",i*8,8,4,4)
    end
    g.setColor(1,1,1,0.5);g.rectangle("fill",32,8,4,4)
    UI.finish();g.setCanvas()
    return target:newImageData()
  end
  for _,case in ipairs({
    {"white-black",{colors="og"},FX.GRAYS},
    {"classic",{colors="classic"},FX.CLASSIC},
    {"custom",{colors="classic",palette="m:4080c0"},Palette.ramp("m:4080c0")},
    {"sgb",{colors="gbc"},base},
    {"inverted",{colors="og_inv"},{FX.GRAYS[4],FX.GRAYS[3],FX.GRAYS[2],FX.GRAYS[1]}},
  })do
    local name,options,colors=unpack(case)
    local data=draw(options)
    check(pixel(data,9,9,rgba(colors[1])),name.." session paper follows saved palette")
    check(pixel(data,17,9,rgba(colors[4])),name.." session ink follows saved palette")
    check(pixel(data,25,9,rgba(colors[2])),name.." intermediate font shades preserve palette ramp")
    check(pixel(data,40,40,background),name.." transparent canvas does not tint world")
    check(pixel(data,180,160,background),name.." outer letterbox is unchanged")
    local mixed={0,0,0,1}
    for i=1,3 do mixed[i]=colors[1][i]/255*0.5+background[i]*0.5 end
    check(pixel(data,33,9,mixed),name.." translucent pixels use premultiplied palette colors")
    if name=="classic" then write("session-classic-palette.png",data:encode("png"):getString())end
  end
  local alpha=draw({colors="classic"},true)
  check(pixel(alpha,40,40,{0,0,0,0}),"transparent output carries zero RGB and alpha")
  check(pixel(alpha,33,9,{155/255*0.5,188/255*0.5,15/255*0.5,0.5}),
    "half-alpha output remains correctly premultiplied")
  local home=draw({colors="classic",palette="m:4080c0"},false,true)
  check(pixel(home,9,9,{1,1,1,1}) and pixel(home,17,9,{0,0,0,1}),
    "home remains white and black independently of active game palette")
  check(FX.mode=="og_inv" and FX.customRamp==sentinelRamp and FX.shadeMap()==sentinelMap,
    "session palette leaves live mode custom ramp and world fade registers intact")
  -- State restoration includes a pre-existing shader and nondefault blending.
  local sentinel=g.newShader([[vec4 effect(vec4 c,Image t,vec2 p,vec2 s){return Texel(t,p)*c;}]])
  local target=g.newCanvas(200,180,{dpiscale=1})
  g.setCanvas(target);g.setShader(sentinel);g.setColor(0.1,0.2,0.3,0.4)
  g.setScissor(1,2,3,4);g.setBlendMode("add","premultiplied")
  UI.begin(game,{rect={0,0,160,144}});UI.finish()
  local r,b,c,a=g.getColor();local x,y,w,h=g.getScissor();local blend,alphaMode=g.getBlendMode()
  check(g.getCanvas()==target and g.getShader()==sentinel and math.abs(r-0.1)<0.001
    and math.abs(b-0.2)<0.001 and math.abs(c-0.3)<0.001 and math.abs(a-0.4)<0.001
    and x==1 and y==2 and w==3 and h==4 and blend=="add" and alphaMode=="premultiplied",
    "session palette restores caller canvas shader color scissor and blend mode")
  g.setCanvas();g.setShader();g.setScissor();g.setBlendMode("alpha");g.setColor(1,1,1,1)
  sentinel:release()
  local ClassicPalette=require("src.ui.ClassicPalette")
  local rampCalls,oldRampFn=0,Palette.ramp
  Palette.ramp=function(...)rampCalls=rampCalls+1;return oldRampFn(...)end
  game.save.options={colors="classic",palette="m:8090a0"}
  local first=ClassicPalette.colors(game)
  check(first==ClassicPalette.colors(game) and rampCalls==1,
    "unchanged session settings reuse resolved custom colors")
  check(ClassicPalette.shader(first)==ClassicPalette.shader(first),
    "palette shader is reused across draws")
  Palette.ramp=oldRampFn
  FX.mode,FX.customRamp=oldMode,oldRamp;FX.setShadeMap(oldMap)
end
