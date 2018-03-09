local draw = require("uk.ui.draw")

local w, h = term.getSize()
local mainWindow = draw(w, h, colors.black, colors.white)
local paneDivison = 4
local paneW = math.floor(w/4)
local leftPane = draw(paneW, h, colors.white, colors.gray)
local padding = 1
leftPane:hline(padding + 1, padding + 1, paneW - (padding * 2), colors.white)
local mainPane = draw(paneW*(paneDivison - 1), h)
mainPane:text("Hello, world!", 2, 2)
mainWindow:child(leftPane, 1, 1)
mainWindow:child(mainPane, 1+paneW, 1)
local i = 1

return {
  window = mainWindow,
  refresh = function(self)
    local t = {"0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"}
    local f, b = t[math.random(#t)], t[math.random(#t)]
    mainPane:clear(f, b)
    mainPane:text("Times rendered: "..i, 2, 2)
    mainPane:text("FPS: "..self.fps, 2, 3)
    i = i + 1
  end,
  fps = 0
}
