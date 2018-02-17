local log = require("uk.extra.log")
local LogType = log.LogType
local jua = require("jua")
local await = jua.await

jua.on("terminate", function()
  print("Terminated")
  jua.stop()
end)

jua.go(function()
  log("Hello", LogType.INFO)
  jua.stop()
end)
