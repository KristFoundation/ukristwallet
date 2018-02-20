local enum = require("uk.extra.enum")
local DEBUG = true

local LogType = enum {"INFO", "DEBUG", "ERROR"}

local function log(str, level)
  if level == LogType.INFO then
    print("["..LogType.lookup[level].."] "..str)
  elseif level == LogType.DEBUG and DEBUG then
    print("["..LogType.lookup[level].."] "..str)
  elseif level == LogType.ERROR then
    error(str)
  end
end

return {
  log = log,
  LogType = LogType
}
