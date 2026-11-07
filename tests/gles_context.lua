-- A requested mobile graphics test must not silently fall back to desktop GL.
return function(check)
  local info={love.graphics.getRendererInfo()}
  local wanted=os.getenv('JP_QA_REQUIRE_GLES')
  if wanted then
    check(info[1]=='OpenGL ES','actual renderer is OpenGL ES: '..table.concat(info,' / '))
    check(info[2]:match('^OpenGL ES '..wanted..'%.')~=nil,
      'actual context has requested ES major version '..wanted)
  end
  return info
end
