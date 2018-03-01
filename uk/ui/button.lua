local align = require("uk.ui.align")
local c2h = require("uk.ui.color2hex")

local button = require("uk.type.class")("Button", require("uk.ui.draw"))

function button:initialize(text, margin, fg, bg)
  self.super.initialize(self, margin * 2 + #test, margin * 2 + 1, fg, bg)
  self.text = text or "Button"
  self.margin = margin or 0
end
