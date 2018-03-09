local draw = require("uk.ui.draw")
local text = require("uk.type.class")("Text", draw)

function text:initialize(text, fg, bg)
  draw.initialize(self, text:len(), 1, fg, bg)
  self:setText(text)
end

function text:setText(text)
  self.width = text:len()
  self.height = 1
  self:text(text, 1, 1)
end

return text
