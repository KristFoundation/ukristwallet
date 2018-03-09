local renderable = {}

function renderable:render(t, x, y)
  local txt, fg, bg = self:_render()

  for i = 1, #bg do
    if #txt[i] ~= #bg[i] then
      error("Text layer is length "..#txt[i].." when it should be "..#bg[i].." (background)")
    elseif #fg[i] ~= #bg[i] then
      error("Foreground layer is length "..#fg[i].." when it should be "..#bg[i].." (background)")
    end
    term.setCursorPos(x, y + i - 1)
    term.blit(txt[i], fg[i], bg[i])
  end
end

return renderable
