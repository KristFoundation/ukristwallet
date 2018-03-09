local consts = require("uk.extra.consts")
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

local function info(str)
  return log(str, LogType.INFO)
end

local function debug(str)
  return log(str, LogType.DEBUG)
end

local function error(str)
  return log(str, LogType.ERROR)
end

return {
  log = log,
  info = info,
  debug = debug,
  error = error,
  LogType = LogType
}
