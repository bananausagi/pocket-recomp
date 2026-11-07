package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local Game=require('src.core.Game')
local count=0
require('tests.jp50_system_back_cases')(Game,{
 back=function()Game:keypressed('acback');Game:keyreleased('acback')end,
 repeatBack=function()Game:keypressed('acback',true);Game:keyreleased('acback')end,
 focus=function(v)Game:focus(v)end,visible=function(v)Game:visible(v)end,
 resume=function()Game:onResume()end,
},function(ok,label)assert(ok,label);count=count+1;print('PASS '..label)end)
print(count..' JP50 BACK CHECKS PASSED')
