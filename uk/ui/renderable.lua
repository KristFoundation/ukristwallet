local renderable = {}

function renderable:render(t, x, y)
  local txt, fg, bg = self:_render()

  for i = 1, #bg do
    term.setCursorPos(x, y + i - 1)
    term.blit(txt[i], fg[i], bg[i])
  end
end

return renderable
