local logger = require("uk.extra.logger")
local log = logger.log
local LogType = logger.LogType

local jua = require("uk.dep.pin.jua")
local await = jua.await

local sha256 = require("uk.crypto.sha256")
local kw = require("uk.crypto.wallet.kristwallet")
local jw = require("uk.crypto.wallet.jwalelset")
local mkv2 = require("uk.crypto.address.v2")
local draw = require("uk.ui.draw")
local view = require("uk.views.mainview")

jua.on("terminate", function()
  print("Terminated")
  jua.stop()
end)

jua.go(function()
  local renderTimes = 0
  jua.setInterval(function()
    view:refresh()
    view.window:render(term, 1, 1)
    renderTimes = renderTimes + 1
  end, 0.05)

  jua.setInterval(function()
    view.fps = renderTimes
    renderTimes = 0
  end, 1)
end)
