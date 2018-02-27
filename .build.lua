if not howlci then
  howlci = {
    log = print,
    status = print,
    close = function() end
  }
end

if _HOST then howlci.log("info", "Host: " .. _HOST) end
if _CC_VERSION then howlci.log("info", "CC Version" .. _CC_VERSION) end
if _MC_VERSION then howlci.log("info", "MC Version" .. _MC_VERSION) end
if _LUAJ_VERSION then howlci.log("info", "LuaJ Version " .. _LUAJ_VERSION) end

local func, msg = loadfile(shell.resolve("howl.lua"), _ENV)
if not func then
	howlci.status("fail", "Cannot load Howl: " .. (msg or "<no msg>"))
	return
end

local ok, msg = pcall(func, "-v", "build")
if not ok then
	howlci.status("fail", "Failed running task: " .. (msg or "<no msg>"))
else
	howlci.status("ok", "Everything built correctly!")
end

local ok, msg = pcall(func, "-v", "test")
if not ok then
	howlci.status("fail", "Failed running task: " .. (msg or "<no msg>"))
else
	howlci.status("ok", "Tests ran correctly!")
end

sleep(2)
howlci.close()
