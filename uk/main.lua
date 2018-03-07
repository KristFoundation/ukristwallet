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

jua.on("terminate", function()
  print("Terminated")
  jua.stop()
end)

jua.go(function()
  local t = {"0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"}
  local w, h = term.getSize()
  local p = 1
  local d = draw(w, h, colors.black, colors.white)
  local d2 = draw(w - p * 2, h - p * 2, colors.white, colors.black)

  jua.setInterval(function()
    d2:clear(colors.white, t[math.random(#t)])
    d:draw(d2, p + 1, p + 1)
    d:render(term, 1, 1)
  end, 0.05)
end)
