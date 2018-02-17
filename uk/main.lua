local logger = require("uk.extra.logger")
local log = logger.log
local LogType = logger.LogType

local netrequire = require("uk.dep.netrequire")
local jua = netrequire("https://raw.githubusercontent.com/justync7/Jua/master/jua.lua")
local await = jua.await

jua.on("terminate", function()
  print("Terminated")
  jua.stop()
end)

jua.go(function()
  log("Hello", LogType.INFO)
  jua.stop()
end)
