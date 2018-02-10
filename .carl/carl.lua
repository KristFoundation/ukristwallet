--#!/bin/lua
--[[
carl version 0.1.0

The MIT License (MIT)
Copyright (c) 2017 CrazedProgrammer

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

local basePath = (shell and shell.dir().."/") or "./"
local args = {...}
local output, traceMap, project, lib = { }, { }

local function resolvePath(path)
	if path:sub(1, 1) == "/" then
		return path
	else
		return basePath..path
	end
end

local function getSrcPath(path)
	if path:sub(1, 1) == "/" then
		return path..".lua"
	else
		return "src/"..path..".lua"
	end
end

local function readLines(path)
	local lines, ok, iter = { }, pcall(io.lines, resolvePath(path))
	if not ok then return end
	for line in iter do
		lines[#lines + 1] = line
	end
	return lines
end

local function writeLines(path, lines)
	local handle = io.open(resolvePath(path), "w")
	if not handle then return false end
	handle:write(table.concat(lines, "\n"))
	handle:close()
	return true
end

local function trimWhitespace(str)
	while str:sub(1, 1) == " " or str:sub(1, 1) == "\t" do
		str = str:sub(2)
	end
	while str:sub(#str, #str) == " " or str:sub(#str, #str) == "\t" do
		str = str:sub(1, #str - 1)
	end
	return str
end

local function splitString(str, separator)
	local strs = { }
	for s in str:gmatch("([^%"..separator.."]+)") do
		strs[#strs + 1] = s
	end
	return strs
end

local function getName(path)
	local strs = splitString(path, "/")
	return strs[#strs]
end

local function addTrace(file, line)
	traceMap[#traceMap + 1] = {file = file, oline = #output + 1, line = line}
end

local function traceLine(line)
	for i = 1, #traceMap do
		if line >= traceMap[i].oline and line < ((traceMap[i + 1] and traceMap[i + 1].oline) or (#output + 1)) then
			return traceMap[i].file, line - traceMap[i].oline + traceMap[i].line
		end
	end
end



local function addSource(file, require)
	local source = readLines(getSrcPath(file))
	if not source then
		print("Error: missing source file \""..file..".lua\".")
		return false
	end
	local ok, err = loadstring(table.concat(source, "\n"), file)
	if not ok then
		local parts = splitString(err, ":")
		local errline = tonumber(parts[4])
		table.remove(parts, 1)
		table.remove(parts, 1)
		table.remove(parts, 1)
		table.remove(parts, 1)
		local error = table.concat(parts, ":")
		print("Syntax error in \""..file..".lua\" at line "..errline..":")
		print(error)
		return false
	end
	if require then
		output[#output + 1] = "local "..getName(file).." = (function ()"
	end
	addTrace(file, 1)
	for i = 1, #source do
		local ln = trimWhitespace(source[i])
		if ln:sub(1, 10) == "--#include" then
			if not addSource(trimWhitespace(ln:sub(12))) then
				return false
			end
			addTrace(file, i + 1)
		elseif ln:sub(1, 10) == "--#require" then
			if not addSource(trimWhitespace(ln:sub(12)), true) then
				return false
			end
			addTrace(file, i + 1)
		else
			output[#output + 1] = source[i]
		end
	end
	if require then
		output[#output + 1] = "end)()"
	end
	return true
end

local function newProject(name, library)
	print("Creating new project \""..name.."\"...")
	if not writeLines(name.."/Carl.cf", {"name = "..name, "version = 0.1.0", "author = <author>"}) then
		print("Could not write to \""..resolvePath(name.."/Carl.cf").."\".")
		return false
	elseif not writeLines(name.."/src/"..(library and "lib.lua" or "main.lua"), {"print(\"Hello, world!\")"}) then
		print("Could not write to \""..resolvePath(name.."/src/"..(library and "lib.lua" or "main.lua")).."\".")
		return false
	end
	print("Done.")
	return true
end

local function loadProject()
	local source = readLines("src/main.lua")
	if not source then
		source = readLines("src/lib.lua")
		if source then
			lib = true
		else
			print("Error: missing main source file \"src/main.lua\" or \"src/lib.lua\".")
			return false
		end
	end

	local cfg = readLines("Carl.cf")
	if not cfg then
		print("Warning: Carl.cf missing, using defaults.")
		project = {name = "prg", author = "<author>", version = "0.1.0"}
	else
		project = { }
		for i = 1, #cfg do
			cfg[i] = trimWhitespace(cfg[i])
			if cfg[i]:find("#") then
				cfg[i] = cfg[i]:sub(1, (cfg[i]:find("#")) - 1)
			end
			if cfg[i] ~= "" then
				local key = trimWhitespace(cfg[i]:sub(1, (cfg[i]:find("=")) - 1))
				local value = trimWhitespace(cfg[i]:sub((cfg[i]:find("=")) + 1))
				project[key] = value
			end
		end
		if not (project.name and project.author and project.version) then
			print("Error: missing project name, author or version.")
			return false
		end
	end

	return true
end

local function compressProject()
	print("Compressing...")
	for i = 1, #output do
		output[i] = trimWhitespace(output[i])
		local cpos = output[i]:find("--", 1, true)
		if cpos then
			if cpos <= 0 and not output[i] == "--[[" then
				output[i] = ""
			else
				if not output[i]:sub(cpos, cpos + 3) == "--[[" then
					output[i] = output[i]:sub(1, cpos - 1)
				end
			end
		end
	end

	local function lzwCompress(str)
		local result, dict, w, dsize, char = { }, { }, "", 255
		for i = 0, 255 do
			dict[string.char(i)] = i
		end
		for i = 1, #str do
			char = str:sub(i, i)
			if dict[w..char] then
				w = w..char
			else
				result[#result + 1] = dict[w]
				dsize = dsize + 1
				dict[w..char] = dsize
				w = char
			end
		end
		if w ~= "" then
			result[#result + 1] = dict[w]
		end
		return result
	end

	local compresslist = lzwCompress(table.concat(output, "\n"))
	local maxnum = 0
	for i = 1, #compresslist do
		if compresslist[i] > maxnum then
			maxnum = compresslist[i]
		end
	end

	local basestr = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789~`!@#$%^&*()_+-=[]{}|:;'<,>.?/ "
	local base = #basestr
	local basechars = { }
	for i = 1, base do
		basechars[i] = basestr:sub(i, i)
	end

	local nchars = math.ceil(math.log(maxnum) / math.log(base))
	local complist = { }
	for i = 1, #compresslist do
		for j = 0, nchars - 1 do
			complist[#complist + 1] = basechars[math.floor(compresslist[i] / (base ^ j)) % base + 1]
		end
	end
	local compstr = table.concat(complist)

	output = { }
	output[#output + 1] = (lib and "local "..project.name.." " or "").."do"
	output[#output + 1] = "\tlocal data = \""..compstr.."\""
	output[#output + 1] = "\tlocal basestr = \""..basestr.."\""
	output[#output + 1] = "\tlocal nchars = \""..nchars.."\""
	output[#output + 1] = [[
	local base = #basestr
	local basenums = { }
	for i = 1, base do
		basenums[basestr:sub(i, i)] = i - 1
	end
	local function lzwDecompress(tab)
		local result, dict, dsize, e, w, k = { }, { }, 255, "", "", ""
		for i = 0, 255 do
			dict[i] = string.char(i)
		end
		for i = 1, #tab do
			k = tab[i]
			if dict[k] then
				e = dict[k]
			elseif k == dsize then
				e = w..w:sub(1, 1)
			end
			result[#result + 1] = e
			dict[dsize] = w..e:sub(1, 1)
			dsize = dsize + 1
			w = e
		end
		return table.concat(result)
	end
	local datatab = { }
	for i = 1, #data, nchars do
		datatab[#datatab + 1] = 0
		for j = 0, nchars - 1 do
			datatab[#datatab] = datatab[#datatab] + basenums[data:sub(i + j, i + j)] * base ^ j
		end
	end
	local exestr = lzwDecompress(datatab)]]
	output[#output + 1] = "\tif load then"
	output[#output + 1] = "\t\t"..(lib and (project.name.." = ") or "").."(load(exestr, \""..project.name.."\", nil, _ENV))()"
	output[#output + 1] = "\telse"
	output[#output + 1] = "\t\tlocal f = loadstring(exestr, \""..project.name.."\")"
	output[#output + 1] = "\t\tsetfenv(f, getfenv(1))"
	output[#output + 1] = "\t\t"..(lib and (project.name.." = ") or "").."f()"
	output[#output + 1] = "\tend"
	output[#output + 1] = "end"..(lib and " return "..project.name or "")
end

local function buildProject(compress, trace)
	if not loadProject() then
		return false
	end
	print("Building "..project.name.."...")
	if lib then
		output[#output + 1] = "local "..project.name.." = { } do"
	end
	if not addSource(lib and "lib" or "main") then
		return false
	end
	if lib then
		output[#output + 1] = "end return "..project.name
	end

	local originalsize
	if compress then
		originalsize = #table.concat(output, "\n")
		compressProject()
	end

	if lib and trace and textutils then
		output[#output] = "end"
		output[#output + 1] = "local line = (...)"
		output[#output + 1] = "if line then"
		output[#output + 1] = "\tlocal traceMap = "..textutils.serialise(traceMap)
		output[#output + 1] = [[
	local function traceLine(line)
		for i = 1, #traceMap do
			if line >= traceMap[i].oline and line < ((traceMap[i + 1] and traceMap[i + 1].oline) or (#output + 1)) then
				return traceMap[i].file, line - traceMap[i].oline + traceMap[i].line
			end
		end
	end]]
		output[#output + 1] = "\tlocal file, line = traceLine(tonumber(line))"
		output[#output + 1] = [[	print("\""..file..".lua\" at line "..line..".")]]
		output[#output + 1] = "end"
		output[#output + 1] = "return "..project.name
	end

	if compress then
		local newsize = #table.concat(output, "\n")
		print(originalsize.." -> "..newsize.." bytes")
		if newsize > originalsize then
			print("Warning: new size is bigger, consider removing \"--compress\".")
		end
	end

	if not writeLines("target/"..project.name, output) then
		print("Error: failed to write to output file.")
		return false
	end
	print("Done.")
	return true
end

local function runProject()
	local func
	if load then
		func = load(table.concat(readLines("target/"..project.name), "\n"), project.name, nil, _ENV)
	else
		func = loadstring(table.concat(readLines("target/"..project.name), "\n"), project.name)
		setfenv(func, getfenv(1))
	end

	local prgargs = { }
	for i = 2, #args do
		prgargs[i - 1] = args[i]
	end
	local cdir, crunning
	if shell then
		cdir = shell.dir()
		shell.setDir(resolvePath("target"))
		crunning = shell.getRunningProgram
		shell.getRunningProgram = function () return resolvePath("target/"..project.name) end
	end
	local ok, err = pcall(func, unpack(prgargs))
	if shell then
		shell.setDir(cdir)
		shell.getRunningProgram = crunning
	end

	if not ok then
		if err then
			local parts = splitString(err, ":")
			local errline = tonumber(parts[2])
			table.remove(parts, 1)
			table.remove(parts, 1)
			local error = table.concat(parts, ":")
			local file, line = traceLine(errline)
			print("Runtime error in \""..file..".lua\" at line "..line..": ")
			print(error)
		else
			print("Runtime error: unknown (returned nil).")
		end
	end
end

if #args == 0 then
	print("carl new <name>")
	print("carl build")
	print("carl run [...]")
	print("carl trace <line>")
	return
end

local largs = { }
for i = 1, #args do
	largs[args[i]] = true
end

if args[1] == "new" then
	if not newProject(args[2], largs["--lib"]) then
		print("Failed to create new project.")
	end
elseif args[1] == "build" then
	if not buildProject(largs["--compress"], largs["--trace"]) then
		print("Failed to build project.")
	end
elseif args[1] == "run" then
	if not buildProject() then
		print("Failed to build project.")
	else
		runProject()
	end
elseif args[1] == "trace" then
	if #args < 2 then
		print("carl trace <line>")
	elseif not buildProject() then
		print("Failed to build project.")
	else
		local oline = tonumber(args[2])
		if oline < 1 or oline > #output then
			print("Line outside range (1-"..#output..").")
		else
			local file, line = traceLine(tonumber(args[2]))
			print("\""..file..".lua\" at line "..line..".")
		end
	end
else
	print("invalid subcommand \""..args[1].."\"")
end
