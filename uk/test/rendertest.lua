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

return {
  name = "render",
  run = function()
    jua.on("terminate", function()
      print("Terminated")
      jua.stop()
    end)

    jua.go(function()
      local w, h = term.getSize()
      local d = draw(w, h, colors.black, colors.white)
      local d2 = draw(10, 10, colors.white, colors.black)
      d:draw(d2, 1, 1)
      d:render(term, 1, 1)
      jua.setTimeout(function()
        term.clear()
        term.setCursorPos(1, 1)
        jua.stop()
      end, 1)
    end)
  end
}
