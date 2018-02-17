local logger = require("uk.extra.logger")
local log = logger.log
local LogType = logger.LogType

local ghrequire = require("uk.dep.ghrequire")
local jua = ghrequire("justync7","Jua","jua.lua")
local await = jua.await

jua.on("terminate", function()
  print("Terminated")
  jua.stop()
end)

jua.go(function()
  log("Info", LogType.INFO)
  log("Debug", LogType.DEBUG)
  log("Error", LogType.ERROR)
  jua.stop()
end)
