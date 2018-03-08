local draw = require("uk.ui.draw")

local w, h = term.getSize()
local mainWindow = draw(w, h, colors.black, colors.white)
local paneDivison = 4
local paneW = math.floor(w/4)
local leftPane = draw(paneW, h, colors.white, colors.gray)
local padding = 1
leftPane:text(tostring(paneW - (padding * 2)), 1, 1, colors.black)
--leftPane:hline(padding + 1, padding + 1, paneW - (padding * 2), colors.white)
local mainPane = draw(paneW*(paneDivison - 1), h, colors.black, colors.white)
mainPane:text("Hello, world!", 2, 2)
mainWindow:child(leftPane, 1, 1)
mainWindow:child(mainPane, 1+paneW, 1)

return mainWindow
