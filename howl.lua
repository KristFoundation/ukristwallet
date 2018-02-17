--[[
The MIT License (MIT)

Copyright (c) 2015-2016 SquidDev

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]--

local loading = {}
local oldRequire, preload, loaded = require, {}, { startup = loading }

local function require(name)
	local result = loaded[name]

	if result ~= nil then
		if result == loading then
			error("loop or previous error loading module '" .. name .. "'", 2)
		end

		return result
	end

	loaded[name] = loading
	local contents = preload[name]
	if contents then
		result = contents(name)
	elseif oldRequire then
		result = oldRequire(name)
	else
		error("cannot load '" .. name .. "'", 2)
	end

	if result == nil then result = true end
	loaded[name] = result
	return result
end
preload["howl.tasks.Task"] = function(...)
--- The main task class
-- @classmod howl.tasks.Task

local assert = require "howl.lib.assert"
local class = require "howl.class"
local colored = require "howl.lib.colored"
local mixin = require "howl.class.mixin"
local os = require "howl.platform".os
local utils = require "howl.lib.utils"

local insert = table.insert

--- Convert a pattern
local function parsePattern(from, to)
	local fromParsed = utils.parsePattern(from, true)
	local toParsed = utils.parsePattern(to)

	local newType = fromParsed.Type
	assert(newType == toParsed.Type, "Both from and to must be the same type " .. newType .. " and " .. fromParsed.Type)

	return { Type = newType, From = fromParsed.Text, To = toParsed.Text }
end

local Task = class("howl.tasks.Task")
	:include(mixin.configurable)
	:include(mixin.optionGroup)
	:addOptions { "description" }

--- Create a task
-- @tparam string name The name of the task
-- @tparam table dependencies A list of tasks this task requires
-- @tparam function action The action to run
-- @treturn Task The created task
function Task:initialize(name, dependencies, action)
	assert.argType(name, "string", "Task", 1)

	-- Check calling with no dependencies
	if type(dependencies) == "function" then
		action = dependencies
		dependencies = {}
	end

	self.options = {}
	self.name = name -- The name of the function
	self.action = action -- The action to call
	self.dependencies = {} -- Task dependencies
	self.maps = {} -- Reads and produces list
	self.produces = {} -- Files this task produces

	if dependencies then self:depends(dependencies) end
end

function Task.static:addDependency(class, name)
	local function apply(self, ...)
		if select('#', ...) == 1 and type(...) == "table" and (#(...) > 0 or next(...) == nil) then
			local first = ...
			for i = 1, #first do
				insert(self.dependencies, class(self, first[i]))
			end
		else
			insert(self.dependencies, class(self, ...))
		end

		return self
	end

	self[name] = apply
	self[name:gsub("^%l", string.upper)] = apply

	return self
end

function Task:setup(context, runner) end

--- Sets a file this task produces
-- @tparam string|table file The path of the file
-- @treturn Task The current object (allows chaining)
function Task:Produces(file)
	if type(file) == "table" then
		local produces = self.produces
		for _, file in ipairs(file) do
			table.insert(produces, file)
		end
	else
		table.insert(self.produces, file)
	end
	return self
end

--- Sets a file mapping
-- @tparam string from The file to map form
-- @tparam string to The file to map to
-- @treturn Task The current object (allows chaining)
function Task:Maps(from, to)
	table.insert(self.maps, parsePattern(from, to))
	return self
end

--- Set the action for this task
-- @tparam function action The action to run
-- @treturn Task The current object (allows chaining)
function Task:Action(action)
	self.action = action
	return self
end

--- Run the action with no bells or whistles
function Task:runAction(context, ...)
	if self.action then
		return self.action(self, context, ...)
	else
		return true
	end
end

--- Execute the task
-- @tparam Context.Context context The task context
-- @param ... The arguments to pass to task
-- @tparam boolean Success
function Task:Run(context, ...)
	local shouldRun = false
	if #self.dependencies == 0 then
		shouldRun = true
	else
		for _, depends in ipairs(self.dependencies) do
			if depends:resolve(context.env, context) then
				shouldRun = true
			end
		end
	end

	if not shouldRun then return false end

	for _, file in ipairs(self.produces) do
		context.filesProduced[file] = true
	end

	-- Technically we don't need to specify an action
	local args = { ... }
	local description = ""

	-- Get a list of arguments
	if #args > 0 then
		local newArgs = {}
		for _, arg in ipairs(args) do
			table.insert(newArgs, tostring(arg))
		end
		description = " (" .. table.concat(newArgs, ", ") .. ")"
	end
	context.env.logger:info("Running %s", self.name .. description)

	local oldTime = os.clock()
	local s, err = true, nil
	if context.Traceback then
		xpcall(function() self:runAction(context.env, unpack(args)) end, function(msg)
			for i = 5, 15 do
				local _, err = pcall(function() error("", i) end)
				if msg:match("Howlfile") then break end
				msg = msg .. "\n  " .. err
			end

			err = msg
			s = false
		end)
	else
		s, err = pcall(self.runAction, self, context.env, ...)
	end

	if s then
		context.env.logger:success("%s finished", self.name)
	else
		context.env.logger:error("%s: %s", self.name, err or "no message")
		error("Error running tasks", 0)
	end

	if context.ShowTime then
		print(" ", "Took " .. os.clock() - oldTime .. "s")
	end

	return true
end

return Task
end
preload["howl.tasks.Runner"] = function(...)
--- Handles tasks and dependencies
-- @classmod howl.tasks.Runner

local class = require "howl.class"
local colored = require "howl.lib.colored"
local Context = require "howl.tasks.Context"
local mixin = require "howl.class.mixin"
local os = require "howl.platform".os
local Task = require "howl.tasks.Task"

--- Handles a collection of tasks and running them
-- @type Runner
local Runner = class("howl.tasks.Runner"):include(mixin.sealed)

--- Create a @{Runner} object
-- @tparam env env The current environment
-- @treturn Runner The created runner object
function Runner:initialize(env)
	self.tasks = {}
	self.default = nil
	self.env = env
end

function Runner:setup()
	for _, task in pairs(self.tasks) do
		task:setup(self.env, self)
	end

	if self.env.logger.hasError then return false end

	for _, task in pairs(self.tasks) do
		for _, dependency in ipairs(task.dependencies) do
			dependency:setup(self.env, self)
		end
	end

	if self.env.logger.hasError then return false end
	return true
end

--- Create a task
-- @tparam string name The name of the task to create
-- @treturn function A builder for tasks
function Runner:Task(name)
	return function(dependencies, action) return self:addTask(name, dependencies, action) end
end

--- Add a task to the collection
-- @tparam string name The name of the task to add
-- @tparam table dependencies A list of tasks this task requires
-- @tparam function action The action to run
-- @treturn Task The created task
function Runner:addTask(name, dependencies, action)
	return self:injectTask(Task(name, dependencies, action))
end

--- Add a Task object to the collection
-- @tparam Task task The task to insert
-- @tparam string name The name of the task (optional)
-- @treturn Task The current task
function Runner:injectTask(task, name)
	self.tasks[name or task.name] = task
	return task
end

--- Set the default task
-- @tparam ?|string|function task The task to run or the name of the task
-- @treturn Runner The current object for chaining
function Runner:Default(task)
	local defaultTask
	if task == nil then
		self.default = nil
	elseif type(task) == "string" then
		self.default = self.tasks[task]
		if not self.default then
			error("Cannot find task " .. task)
		end
	else
		self.default = Task("<default>", {}, task)
	end

	return self
end

--- Run a task, and all its dependencies
-- @tparam string name Name of the task to run
-- @treturn Runner The current object for chaining
function Runner:Run(name)
	return self:RunMany({ name })
end

--- Run a task, and all its dependencies
-- @tparam table names Names of the tasks to run
-- @return The result of the last task
function Runner:RunMany(names)
	local oldTime = os.clock()
	local value = true

	local context = Context(self)
	if #names == 0 then
		context:Start()
	else
		for _, name in ipairs(names) do
			value = context:Start(name)
		end
	end

	if context.ShowTime then
		colored.printColor("orange", "Took " .. os.clock() - oldTime .. "s in total")
	end

	return value
end

return Runner
end
preload["howl.tasks.OptionTask"] = function(...)
--- A Task that can store options
-- @classmod howl.tasks.OptionTask

local assert = require "howl.lib.assert"
local mixin = require "howl.class.mixin"
local rawset = rawset

local Task = require "howl.tasks.Task"

local OptionTask = Task:subclass("howl.tasks.OptionTask")
	:include(mixin.configurable)

function OptionTask:initialize(name, dependencies, keys, action)
	Task.initialize(self, name, dependencies, action)

	self.options = {}
	self.optionKeys = {}
	for _, key in ipairs(keys or {}) do
		self:addOption(key)
	end
end

function OptionTask:addOption(key)
	local options = self.options
	local func = function(self, value)
		if value == nil then value = true end
		options[key] = value
		return self
	end

	self[key:gsub("^%l", string.upper)] = func
	self[key] = func
	self.optionKeys[key] = true
end

function OptionTask:configure(item)
	assert.argType(item, "table", "configure", 1)

	for k, v in pairs(item) do
		if self.optionKeys[k] then
			self.options[k] = v
		else
			-- TODO: Configure filtering
			-- error("Unknown option " .. tostring(k), 2)
		end
	end
end

return OptionTask
end
preload["howl.tasks.Dependency"] = function(...)
--- An abstract class dependency
-- @classmod howl.tasks.Dependency

local class = require "howl.class"

local Dependency = class("howl.tasks.Dependency")

--- Create a new dependency
function Dependency:initialize(task)
	if self.class == Dependency then
		error("Cannot create instance of abstract class " .. tostring(Dependency), 2)
	end

	self.task = task
end

--- Setup the dependency, checking if it cannot be resolved
function Dependency:setup(context, runner)
	error("setup has not been overridden in " .. self.class, 2)
end

--- Execute the dependency
-- @treturn boolean If the task was run
function Dependency:resolve(context, runner)
	error("resolve has not been overridden in " .. self.class, 2)
end

return Dependency
end
preload["howl.tasks.Context"] = function(...)
--- Manages the running of tasks
-- @classmod howl.tasks.Context

local class = require "howl.class"
local fs = require "howl.platform".fs
local mixin = require "howl.class.mixin"
local platform = require "howl.platform"

--- Holds task contexts
local Context = class("howl.tasks.Context"):include(mixin.sealed)

--- Create a new task context
-- @tparam Runner.Runner runner The task runner to run tasks from
-- @treturn Context The resulting context
function Context:initialize(runner)
	self.ran = {} -- List of task already run
	self.filesProduced = {}
	self.tasks = runner.tasks
	self.default = runner.default

	self.Traceback = runner.Traceback
	self.ShowTime = runner.ShowTime
	self.env = runner.env
	self:BuildCache()
end

function Context:DoRequire(path, quite)
	if self.filesProduced[path] then return true end

	-- Check for normal files
	local task = self.producesCache[path]
	if task then
		self.filesProduced[path] = true
		return self:Run(task)
	end

	-- Check for file mapping
	task = self.normalMapsCache[path]
	local from, name
	local to = path
	if task then
		self.filesProduced[path] = true

		-- Convert task.Pattern.From to path
		-- (which should be task.Pattern.To)
		name = task.Name
		from = task.Pattern.From
	end

	for match, data in pairs(self.patternMapsCache) do
		if path:match(match) then
			self.filesProduced[path] = true

			-- Run task, replacing match with the replacement pattern
			name = data.Name
			from = path:gsub(match, data.Pattern.From)
			break
		end
	end

	if name then
		local canCreate = self:DoRequire(from, true)
		if not canCreate then
			if not quite then
				self.env.logger:error("Cannot find '" .. from .. "'")
			end
			return false
		end

		return self:Run(name, from, to)
	end

	if fs.exists(fs.combine(self.env.root, path)) then
		self.filesProduced[path] = true
		return true
	end

	if not quite then
		self.env.logger:error("Cannot find a task matching '" .. path .. "'")
	end
	return false
end

local function arrayEquals(x, y)
	local len = #x
	if #x ~= #y then return false end

	for i = 1, len do
		if x[i] ~= y[i] then return false end
	end
	return true
end

--- Run a task
-- @tparam string|Task.Task name The name of the task or a Task object
-- @param ... The arguments to pass to it
-- @treturn boolean Success in running the task?
function Context:Run(name, ...)
	local task = name
	if type(name) == "string" then
		task = self.tasks[name]

		if not task then
			error("Cannot find a task called '" .. name .. "'")
			return false
		end
	elseif not task or not task.Run then
		error("Cannot call task " .. tostring(task) .. " as it has no 'Run' method")
		return false
	end

	-- Search if this task has been run with the given arguments
	local args = { ... }
	local ran = self.ran[task]
	if not ran then
		ran = { args }
		self.ran[task] = ran
	else
		for i = 1, #ran do
			if arrayEquals(args, ran[i]) then return false end
		end
		ran[#ran + 1] = args
	end

	-- Sleep before every task just in case
	platform.refreshYield()

	return task:Run(self, ...)
end

Context.run = Context.Run

--- Start the task process
-- @tparam string name The name of the task (Optional)
-- @treturn boolean Success in running the task?
function Context:Start(name)
	local task
	if name then
		task = self.tasks[name]
	else
		task = self.default
		name = "<default>"
	end

	if not task then
		self.env.logger:error("Cannot find a task called '" .. name .. "'")
		return false
	end

	return self:Run(task)
end

--- Build a cache of tasks
-- This is used to speed up finding file based tasks
-- @treturn Context The current context
function Context:BuildCache()
	local producesCache = {}
	local patternMapsCache = {}
	local normalMapsCache = {}

	self.producesCache = producesCache
	self.patternMapsCache = patternMapsCache
	self.normalMapsCache = normalMapsCache

	for name, task in pairs(self.tasks) do
		local produces = task.produces
		if produces then
			for _, file in ipairs(produces) do
				local existing = producesCache[file]
				if existing then
					error(string.format("Both '%s' and '%s' produces '%s'", existing, name, file))
				end
				producesCache[file] = name
			end
		end

		local maps = task.maps
		if maps then
			for _, pattern in ipairs(maps) do
				-- We store two separate caches for each of them
				local toMap = (pattern.Type == "Pattern" and patternMapsCache or normalMapsCache)
				local match = pattern.To
				local existing = toMap[match]
				if existing then
					error(string.format("Both '%s' and '%s' match '%s'", existing, name, match))
				end
				toMap[match] = { Name = name, Pattern = pattern }
			end
		end
	end

	return self
end

return Context
end
preload["howl.scratchpad"] = function(...)
local utils = require "howl.lib.utils"
local dump = require "howl.lib.dump".dump
local printColor = require "howl.lib.colored".printColor

local parsePattern = utils.parsePattern
local createLookup = utils.createLookup

local tasks = {
	{
		name = "input",
		provides = createLookup { "foo.un.lua" },
	},

	{
		name = "output",
		requires = createLookup { "foo.min.lua" },
	},

	{
		name = "minify",
		maps = {
			{
				from = parsePattern("wild:*.lua", true),
				to = parsePattern("wild:*.min.lua")
			}
		},
	},

	{
		name = "licence",
		maps = {
			{
				from = parsePattern("wild:*.un.lua", true),
				to = parsePattern("wild:*.lua")
			}
		},
	},
}

for k, v in pairs(tasks) do
	tasks[v.name] = v
	if not v.maps then v.maps = {} end
	v.mapper = #v.maps > 0
	if not v.provides then v.provides = {} end
	if not v.requires then v.requires = {} end
end

local function matching(name)
	local out = {}

	for _, task in ipairs(tasks) do
		if task.provides[name] then
			out[#out + 1] = { task = task.name }
		end

		for _, mapping in ipairs(task.maps) do
			if mapping.to.Type == "Text" then
				if mapping.to.Text == name then
					out[#out + 1] = {
						task = task.name,
						mapping.from.Text,
						name
					}
				end
			else
				if name:find(mapping.to.Text) then
					out[#out + 1] = {
						task = task.name,
						name:gsub(mapping.to.Text, mapping.from.Text),
						name
					}
				end
			end
		end
	end

	return out
end

local function resolveTasks(...)
	local out = {}

	local queue = {}

	local depCache = {}
	local function addDep(dependency, depth)
		local hash = dependency.task .. "|"..table.concat(dependency, "|")

		local existing = depCache[hash]
		if existing then
			existing.depth = math.min(existing.depth, depth)
			return existing
		else
			dependency.depth = depth
			dependency.needed = {}
			dependency.solutions = {}
			dependency.name = dependency.task .. ": " .. table.concat(dependency, " \26 ")
			depCache[hash] = dependency
			queue[#queue + 1] = dependency
			return dependency
		end
	end

	local function addSolution(solution, dependency)
		local solution = addDep(solution, dependency.depth + 1)
		solution.needed[#solution.needed + 1] = dependency

		return solution
	end

	for i = 1, select('#', ...) do
		addDep({ task = select(i, ...)}, 1)
	end

	while #queue > 0 do
		local dependency = table.remove(queue, 1)
		local task = tasks[dependency.task]

		print("Task '" .. dependency.name)
		if #dependency.needed > 0 then
			print("  Needed for")
			for i = 1, #dependency.needed do
				printColor("lightGrey", "    " .. dependency.needed[i].name)
			end
		end

		if dependency.depth > 4 then
			printColor("red", "  Too deep")
		elseif #dependency.solutions > 0 or (#task.requires == 0 and not task.mapper) then
			printColor("green", "  Endpoint")
			out[#out + 1] = dependency

			for i = 1, #dependency.needed do
				local needed = dependency.needed[i]
				needed.solutions[#needed.solutions + 1] = dependency

				-- This should only happen once everything has happened
				if #needed.solutions == 1 then
					queue[#queue + 1] = needed
				end
			end
		else
			for i = 1, #task.requires do
				local requirement = task.requires[i]
				print("  Depends on '" .. requirement .. "'")

				local matching = matching(requirement)
				for i = 1, #matching do
					local solution = addSolution(matching[i], dependency)

					printColor("yellow", "    Maybe: " .. solution.name)
				end
			end

			if task.mapper then
				local requirement = dependency[1]
				print("  Depends on '" .. requirement .. "'")

				local matching = matching(requirement)
				for i = 1, #matching do
					local solution = addSolution(matching[i], dependency)

					printColor("yellow", "    Maybe: " .. solution.name)
				end
			end
		end
	end

	return out
end

-- print(dump(tasks))
-- print("Resolved", dump(matching("foo.min.lua")))


local resolved = resolveTasks("output")
for i = 1, #resolved do
	print(resolved[i].name)
end
end
preload["howl.platform.oc"] = function(...)
--- OpenComputers's platform table
-- @module howl.platform.oc

local filesystem = require("filesystem")
local term = require("term")
local component = require("component")
local hasInternet = pcall(function() return component.internet end)
local internet = require("internet")
local gpu = component.gpu

local function read(filename)
	local size = getSize(filename)
	local fh = filesystem.open(filename)
	local contents = fh:read(size)
	fh:close()
	return contents
end

--readDir and writeDir copied semi-verbatim from CC platform (with a slight modification)
local function readDir(directory)
	local offset = #directory + 2
	local stack, n = { directory }, 1

	local files = {}

	while n > 0 do
		local top = stack[n]
		n = n - 1

		if fs.isDir(top) then
			for _, file in ipairs(filesystem.list(top)) do
				n = n + 1
				stack[n] = filesystem.combine(top, file)
			end
		else
			files[top:sub(offset)] = read(top)
		end
	end

	return files
end

local function writeDir(dir, files)
	for file, contents in pairs(files) do
		write(filesystem.combine(dir, file), contents)
	end
end

local function write(filename,contents)
	local fh = filesystem.open(filename,"w")
	local ok, err = fh:write(contents)
	if not ok then io.stderr:write(err) end
	fh:close()
end

local function assertExists(file,name,level)
	if not filesystem.exists(file) then
		error("Cannot find "..name.." (looking for "..file..")",level or 1)
	end
end

local function getSize(file)
	local fh = filesystem.open(file)
	local size = fh:seek("end")
	fh:close()
	return size
end

local function request(url,post,headers)
	if not hasInternet then error("No internet card found",0) end
		local resp = ""
	for chunk in internet.request(url,post,headers) do
		resp = resp..chunk
	end
	return resp
end

local function notImplemented(name)
	return function() error(name.." has not been implemented for OpenComputers!",2) end
end

return {
	os = {
		clock = os.clock,
		time = os.time,
		getEnv = os.getEnv,
	},
	fs = {
		-- Path manipulation
		combine = filesystem.concat,
		normalise = filesystem.canonical,
		getDir = filesystem.path,
		getName = filesystem.name,
		currentDir = shell.getWorkingDirectory,
		currentProgram = function() return process.info().command end,

		-- File access
		read = read,
		write = write,
		readDir = readDir,
		writeDir = writeDir,
		getSize = getSize,

		-- Type checking
		assertExists = assertExists,
		exists = filesystem.exists,
		isDir = filesystem.isDir,

		-- Other
		list = filesystem.list,
		makeDir = filesystem.makeDir,
		delete = filesystem.delete,
		move = filesystem.move,
		copy = filesystem.copy,
	},
	term = {
		setColor = gpu.setForeground,
		resetColor = function() gpu.setForeground(colors.white) end,

		print = print,
		write = io.write,
	},
	http = {
		request = request,
	},
	log = function() return end,

	refreshYield = function() os.sleep(0) end,
}
end
preload["howl.platform.native"] = function(...)
--- Platform implementation for vanilla Lua
-- @module howl.platform.native

local escapeBegin = string.char(27) .. '['
local colorMappings = {
	white     = 97,
	orange    = 33,
	magenta   = 95,
	lightBlue = 94,
	yellow    = 93,
	lime      = 92,
	pink      = 95, -- No pink
	gray      = 90, grey = 90,
	lightGray = 37, lightGrey = 37,
	cyan      = 96,
	purple    = 35, -- Dark magenta
	blue      = 36,
	brown     = 31,
	green     = 32,
	red       = 91,
	black     = 30,
}

local function notImplemented(name)
	return function() error(name .. " is not implemented", 2) end
end

local path = require('pl.path')
local dir = require('pl.dir')
local file = require('pl.file')
return {
	fs = {
		combine = path.join,
		normalise = path.normpath,
		getDir = path.dirname,
		getName = path.basename,
		currentDir = function() return path.currentdir end,

		read = file.read,
		write = file.write,
		readDir = notImplemented("fs.readDir"),
		writeDir = notImplemented("fs.writeDir"),
		getSize = function(n)
			local file = io:open(n,"r")
			local size = file:seek("end")
			file:close()
			return size
		end,

		assertExists = function(file)
			if not path.exists(file) then
				error("File does not exist")
			end
		end,
		exists = path.exists,
		isDir = path.isdir,

		-- Other
		list = function(dir)
			local result = {}
			for path in path.dir(dir) do
				result[#result + 1] = path
			end

			return result
		end,
		makeDir = dir.makepath,
		delete = function(pa)
			if path.isdir(pa) then
				dir.rmtree(pa)
			else
				file.delete(pa)
			end
		end,
		move = file.move,
		copy = file.copy,
	},

	http = {
		request = notImplemented("http.request"),
	},

	term = {
		setColor = function(color)
			local col = colorMappings[color]
			if not col then error("Cannot find color " .. tostring(color), 2) end
			io.write(escapeBegin .. col .. "m")
			io.flush()
		end,
		resetColor = function()
			io.write(escapeBegin .. "0m")
			io.flush()
		end
	},
	refreshYield = function() end
}
end
preload["howl.platform"] = function(...)
--- The native loader for platforms
-- @module howl.platform

if fs and term then
	return require "howl.platform.cc"
elseif _G.component then
	return require "howl.platform.oc"
else
	return require "howl.platform.native"
end
end
preload["howl.platform.cc"] = function(...)
--- CC's platform table
-- @module howl.platform.cc

local default = term.getTextColor and term.getTextColor() or colors.white

local function read(file)
	local handle = fs.open(file, "r")
	local contents = handle.readAll()
	handle.close()
	return contents
end

local function write(file, contents)
	local handle = fs.open(file, "w")
	handle.write(contents)
	handle.close()
end

local function assertExists(file, name, level)
	if not fs.exists(file) then
		error("Cannot find " .. name .. " (Looking for " .. file .. ")", level or 1)
	end
end

local push, pull = os.queueEvent, coroutine.yield

local function refreshYield()
	push("sleep")
	if pull() == "terminate" then error("Terminated") end
end

local function readDir(directory)
	local offset = #directory + 2
	local stack, n = { directory }, 1

	local files = {}

	while n > 0 do
		local top = stack[n]
		n = n - 1

		if fs.isDir(top) then
			for _, file in ipairs(fs.list(top)) do
				n = n + 1
				stack[n] = fs.combine(top, file)
			end
		else
			files[top:sub(offset)] = read(top)
		end
	end

	return files
end

local function writeDir(dir, files)
	for file, contents in pairs(files) do
		write(fs.combine(dir, file), contents)
	end
end

local request
if http.fetch then
	request = function(url, post, headers)
		local ok, err = http.fetch(url, post, headers)
		if ok then
			while true do
				local event, param1, param2, param3 = os.pullEvent(e)
				if event == "http_success" and param1 == url then
					return true, param2
				elseif event == "http_failure" and param1 == url then
					return false, param3, param2
				end
			end
		end
		return false, nil, err
	end
else
	request = function(...)
		local ok, result = http.post(...)
		if ok then
			return true, result
		else
			return false, nil, result
		end
	end
end

local getEnv
if settings and fs.exists(".settings") then
	settings.load(".settings")
end

if settings and shell.getEnv then
	getEnv = function(name, default)
		local value = shell.getEnv(name)
		if value ~= nil then return value end

		return settings.get(name, default)
	end
elseif settings then
	getEnv = settings.get
elseif shell.getEnv then
	getEnv = function(name, default)
		local value = shell.getEnv(name)
		if value ~= nil then return value end
		return default
	end
else
	getEnv = function(name, default) return default end
end

local time
if profiler and profiler.milliTime then
	time = function() return profiler.milliTime() * 1e-3 end
else
	time = os.time
end

local log
if howlci then
	log = howlci.log
else
	log = function() end
end

return {
	os = {
		clock = os.clock,
		time = time,
		getEnv = getEnv,
	},
	fs = {
		-- Path manipulation
		combine = fs.combine,
		normalise = function(path) return fs.combine(path, "") end,
		getDir = fs.getDir,
		getName = fs.getName,
		currentDir = shell.dir,
		currentProgram = shell.getRunningProgram,

		-- File access
		read = read,
		write = write,
		readDir = readDir,
		writeDir = writeDir,
		getSize = fs.getSize,

		-- Type checking
		assertExists = assertExists,
		exists = fs.exists,
		isDir = fs.isDir,

		-- Other
		list = fs.list,
		makeDir = fs.makeDir,
		delete = fs.delete,
		move = fs.move,
		copy = fs.copy,
	},
	term = {
		setColor = function(color)
			local col = colours[color] or colors[color]
			if not col then error("Unknown color " .. color, 2) end

			term.setTextColor(col)
		end,
		resetColor = function() term.setTextColor(default) end,

		print = print,
		write = io.write,
	},
	http = {
		request = request,
	},
	log = log,

	refreshYield = refreshYield,
}
end
preload["howl.packages.Proxy"] = function(...)
--- A proxy to a package
-- @classmod howl.packages.Proxy

local class = require "howl.class"
local fs = require "howl.platform".fs
local mixin = require "howl.class.mixin"

local Proxy = class("howl.packages.Proxy")

--- Create a new package
function Proxy:initialize(manager, name, package)
	self.name = name
	self.manager = manager
	self.package = package
end

--- Get a unique name for this package
-- @treturn string The unique name
function Proxy:getName()
	return self.name
end

--- Get the files for a set of metadata
-- @treturn table Lookup of provided files to actual path. They should not have a leading '/'.
function Proxy:files()
	local cache = self.manager:getCache(self.name)
	return self.package:files(cache)
end

--- Resolve this package, fetching if required
-- @tparam [string] files List of required files
-- @tparam boolean force Force a refresh of dependencies
-- @return The list of files within the package
function Proxy:require(files, force)
	return self.manager:require(self.package, files, force)
end

return Proxy
end
preload["howl.packages.Package"] = function(...)
--- An abstract package
-- @classmod howl.packages.Package

local class = require "howl.class"
local fs = require "howl.platform".fs
local mixin = require "howl.class.mixin"

local Package = class("howl.packages.Package")
	:include(mixin.configurable)
	:include(mixin.optionGroup)

--- Create a new package
function Package:initialize(context, root)
	if self.class == Package then
		error("Cannot create instance of abstract class " .. tostring(Package), 2)
	end

	self.context = context
	self.root = root
	self.options = {}
end

--- Setup the package, checking if it is well formed
function Package:setup()
	error("setup has not been overridden in " .. tostring(self.class), 2)
end

--- Get a unique name for this package
-- @treturn string The unique name
function Package:getName()
	error("name has not been overridden in " .. tostring(self.class), 2)
end

--- Get the files for a set of metadata
-- @param cache The previous cache metadata
-- @treturn table Lookup of provided files to actual path. They should not have a leading '/'.
function Package:files(cache)
	error("files has not been overridden in " .. tostring(self.class), 2)
end

--- Resolve this package, fetching if required
-- @param previous The previous cache metadata
-- @tparam boolean refresh Force a refresh of dependencies
-- @return The new cache metadata
function Package:require(previous, refresh)
	error("require has not been overrriden in " .. tostring(self.class), 2)
end

return Package
end
preload["howl.packages.Manager"] = function(...)
--- Handles external packages
-- @module howl.packages.Manager

local class = require "howl.class"
local fs = require "howl.platform".fs
local dump = require "howl.lib.dump"
local mixin = require "howl.class.mixin"

local Proxy = require "howl.packages.Proxy"

local emptyCache = {}

local Manager = class("howl.packages.Manager")
Manager.providers = {}

function Manager:initialize(context)
	self.context = context

	self.packages = {}
	self.packageLookup = {}
	self.cache = {}
	self.root = ".howl/packages"
	self.alwaysRefresh = false
end

function Manager.static:addProvider(class, name)
	self.providers[name] = class
end

function Manager:addPackage(type, details)
	local provider = Manager.providers[type]
	if not provider then error("No such package provider " .. type, 2) end

	local package = provider(self.context, self.root)
	package:configure(details)
	local name = type .. "-" .. package:getName()
	package.installDir = fs.combine(self.root, name)

	self.packages[name] = package
	self.packageLookup[package] = name

	package:setup(self.context)
	if self.context.logger.hasError then
		error("Error setting up " .. name, 2)
	end

	return Proxy(self, name, package)
end

function Manager:getCache(name)
	if not self.packages[name] then
		error("No such package " .. name, 2)
	end

	local cache = self.cache[name]
	local path = fs.combine(self.root, name .. ".lua")
	if cache == nil and fs.exists(path) then
		cache = dump.unserialise(fs.read(path))
	end

	if cache == emptyCache then cache = nil end

	return cache
end

function Manager:require(package, files, force)
	local name = self.packageLookup[package]
	if not name then error("No such package " .. package:getName(), 2) end

	force = force or self.alwaysRefresh

	local cache = self:getCache(name)

	if cache and files and not force then
		local existing = package:files(cache)
		for _, file in ipairs(files) do
			if not existing[file] then
				force = true
				break
			end
		end
	end

	local newData = package:require(cache, force)

	-- TODO: Decent equality checking
	if newData ~= cache then
		self.context.logger:verbose("Package " .. name .. " updated")
		if newData == nil then
			self.cache[name] = emptyCache
		else
			self.cache[name] = newData
			fs.write(fs.combine(self.root, name .. ".lua"), dump.serialise(newData))
		end
	end

	local newFiles = package:files(newData)
	if files then
		for _, file in ipairs(files) do
			if not newFiles[file] then
				error("Cannot resolve " .. file .. " for " .. name)
			end
		end
	end

	return newFiles
end

return Manager
end
preload["howl.modules.tasks.require"] = function(...)
--- A task that combines files that can be loaded using `require`.
-- @module howl.modules.tasks.require

local assert = require "howl.lib.assert"
local fs = require "howl.platform".fs
local mixin = require "howl.class.mixin"

local Buffer = require "howl.lib.Buffer"
local CopySource = require "howl.files.CopySource"
local Runner = require "howl.tasks.Runner"
local Task = require "howl.tasks.Task"

local header = require "howl.modules.tasks.require.header"
local envSetup = "local env = setmetatable({ require = require, preload = preload, }, { __index = getfenv() })\n"

local function toModule(file)
	if file:find("%.lua$") then
		return file:gsub("%.lua$", ""):gsub("/", "."):gsub("^(.*)%.init$", "%1")
	end
end

local function handleRes(file)
	if file.relative:find("%.res%.") then
		file.name = file.name:gsub("%.res%.", ".")
		return ("return %q"):format(file.contents)
	end
end

local RequireTask = Task:subclass("howl.modules.require.RequireTask")
	:include(mixin.filterable)
	:include(mixin.delegate("sources", {"from", "include", "exclude"}))
	:addOptions { "link", "startup", "output", "api" }

function RequireTask:initialize(context, name, dependencies)
	Task.initialize(self, name, dependencies)

	self.sources = CopySource()
	self.sources:rename(function(file) return toModule(file.name) end)
	self.sources:modify(handleRes)

	self:exclude { ".git", ".svn", ".gitignore", context.out }

	self:description("Packages files together to allow require")
end

function RequireTask:configure(item)
	Task.configure(self, item)
	self.sources:configure(item)
end

function RequireTask:output(value)
	assert.argType(value, "string", "output", 1)
	if self.options.output then error("Cannot set output multiple times") end

	self.options.output = value
	self:Produces(value)
end

function RequireTask:setup(context, runner)
	Task.setup(self, context, runner)
	if not self.options.startup then
		context.logger:error("Task '%s': No startup file", self.name)
	end
	self:requires(self.options.startup)

	if not self.options.output then
		context.logger:error("Task '%s': No output file", self.name)
 	end
end

function RequireTask:runAction(context)
	local files = self.sources:gatherFiles(context.root)
	local startup = self.options.startup
	local output = self.options.output
	local link = self.options.link

	local result = Buffer()
	result:append(header):append("\n")

	if link then result:append(envSetup) end

	for _, file in pairs(files) do
		context.logger:verbose("Including " .. file.relative)
		result:append("preload[\"" .. file.name .. "\"] = ")
		if link then
			assert(fs.exists(file.path), "Cannot find " .. file.relative)
			result:append("setfenv(assert(loadfile(\"" .. file.path .. "\")), env)\n")
		else
			result:append("function(...)\n" .. file.contents .. "\nend\n")
		end
	end

	if self.options.api then
		result:append("if not shell or type(... or nil) == 'table' then\n")
		result:append("local tbl = ... or {}\n")
		result:append("tbl.require = require tbl.preload = preload\n")
		result:append("return tbl\n")
		result:append("else\n")
	end
	result:append("return preload[\"" .. toModule(startup) .. "\"](...)\n")
	if self.options.api then
		result:append("end\n")
	end

	fs.write(fs.combine(context.root, output), result:toString())
end

local RequireExtensions = { }

function RequireExtensions:require(name, taskDepends)
	return self:injectTask(RequireTask(self.env, name, taskDepends))
end

local function apply()
	Runner:include(RequireExtensions)
end

return {
	name = "require task",
	description = "A task that combines files that can be loaded using `require`.",
	apply = apply,

	RequireTask = RequireTask,
}
end
preload["howl.modules.tasks.require.header"] = function(...)
return "local loading = {}\
local oldRequire, preload, loaded = require, {}, { startup = loading }\
\
local function require(name)\
	local result = loaded[name]\
\
	if result ~= nil then\
		if result == loading then\
			error(\"loop or previous error loading module '\" .. name .. \"'\", 2)\
		end\
\
		return result\
	end\
\
	loaded[name] = loading\
	local contents = preload[name]\
	if contents then\
		result = contents(name)\
	elseif oldRequire then\
		result = oldRequire(name)\
	else\
		error(\"cannot load '\" .. name .. \"'\", 2)\
	end\
\
	if result == nil then result = true end\
	loaded[name] = result\
	return result\
end"
end
preload["howl.modules.tasks.pack.vfs"] = function(...)
return "local fs = fs\
\
local matches = {\
	[\"^\"] = \"%^\",\
	[\"$\"] = \"%$\",\
	[\"(\"] = \"%(\",\
	[\")\"] = \"%)\",\
	[\"%\"] = \"%%\",\
	[\".\"] = \"%.\",\
	[\"[\"] = \"%[\",\
	[\"]\"] = \"%]\",\
	[\"*\"] = \"%*\",\
	[\"+\"] = \"%+\",\
	[\"-\"] = \"%-\",\
	[\"?\"] = \"%?\",\
	[\"\\0\"] = \"%z\",\
}\
\
--- Escape a string for using in a pattern\
-- @tparam string pattern The string to escape\
-- @treturn string The escaped pattern\
local function escapePattern(pattern)\
	return (pattern:gsub(\".\", matches))\
end\
\
local function matchesLocal(root, path)\
	return root == \"\" or path == root or path:sub(1, #root + 1) == root .. \"/\"\
end\
\
local function extractLocal(root, path)\
	if root == \"\" then\
		return path\
	else\
		return path:sub(#root + 2)\
	end\
end\
\
\
local function copy(old)\
	local new = {}\
	for k, v in pairs(old) do new[k] = v end\
	return new\
end\
\
--[[\
	Emulates a basic file system.\
	This doesn't have to be too advanced as it is only for Howl's use\
	The files is a list of paths to file contents, or true if the file\
	is a directory.\
	TODO: Override IO\
]]\
local function makeEnv(root, files)\
	-- Emulated filesystem (partially based of Oeed's)\
	files = copy(files)\
	local env\
	env = {\
		fs = {\
			list = function(path)\
				path = fs.combine(path, \"\")\
				local list = fs.isDir(path) and fs.list(path) or {}\
\
				if matchesLocal(root, path) then\
					local pattern = \"^\" .. escapePattern(extractLocal(root, path))\
					if pattern ~= \"^\" then pattern = pattern .. '/' end\
					pattern = pattern .. '([^/]+)$'\
\
					for file, _ in pairs(files) do\
						local name = file:match(pattern)\
						if name then list[#list + 1] = name end\
					end\
				end\
\
				return list\
			end,\
\
			exists = function(path)\
				path = fs.combine(path, \"\")\
				if fs.exists(path) then\
					return true\
				elseif matchesLocal(root, path) then\
					return files[extractLocal(root, path)] ~= nil\
				end\
			end,\
\
			isDir = function(path)\
				path = fs.combine(path, \"\")\
				if fs.isDir(path) then\
					return true\
				elseif matchesLocal(root, path) then\
					return files[extractLocal(root, path)] == true\
				end\
			end,\
\
			isReadOnly = function(path)\
				path = fs.combine(path, \"\")\
				if fs.exists(path) then\
					return fs.isReadOnly(path)\
				elseif matchesLocal(root, path) and files[extractLocal(root, path)] ~= nil then\
					return true\
				else\
					return false\
				end\
			end,\
\
			getName = fs.getName,\
			getDir = fs.getDir,\
			getSize = fs.getSize,\
			getFreeSpace = fs.getFreeSpace,\
			combine = fs.combine,\
\
			-- TODO: This should be implemented\
			move = fs.move,\
			copy = fs.copy,\
			makeDir = function(dir)\
\
			end,\
			delete = fs.delete,\
\
			open = function(path, mode)\
				path = fs.combine(path, \"\")\
				if matchesLocal(root, path) then\
					local localPath = extractLocal(root, path)\
					if type(files[localPath]) == 'string' then\
						local handle = {close = function()end}\
						if mode == 'r' then\
							local content = files[localPath]\
							handle.readAll = function()\
								return content\
							end\
\
							local line = 1\
							local lines\
							handle.readLine = function()\
								if not lines then -- Lazy load lines\
									lines = {content:match((content:gsub(\"[^\\n]+\\n?\", \"([^\\n]+)\\n?\")))}\
								end\
								if line > #lines then\
									return nil\
								else\
									return lines[line]\
								end\
								line = line + 1\
							end\
\
							return handle\
						else\
							error('Cannot write to read-only file.', 2)\
						end\
					end\
				end\
\
				return fs.open(path, mode)\
			end\
		},\
\
		loadfile = function(name)\
			local file = env.fs.open(name, \"r\")\
			if file then\
				local func, err = load(file.readAll(), fs.getName(name), nil, env)\
				file.close()\
				return func, err\
			end\
			return nil, \"File not found: \"..name\
		end,\
\
		dofile = function(name)\
			local file, e = env.loadfile(name, env)\
			if file then\
				return file()\
			else\
				error(e, 2)\
			end\
		end,\
	}\
\
	env._G = env\
	env._ENV = env\
	return setmetatable(env, {__index = _ENV or getfenv()})\
end\
\
local function extract(root, files, from, to)\
	local pattern = \"^\" .. escapePattern(extractLocal(root, from))\
	if pattern ~= \"^\" then pattern = pattern .. '/' end\
	pattern = pattern .. '(.*)$'\
\
	for file, contents in pairs(files) do\
		local name = file:match(pattern)\
		if name then\
			print(\"Extracting \" .. name)\
			local handle = fs.open(fs.combine(to, name), \"w\")\
			handle.write(contents)\
			handle.close()\
		end\
	end\
end"
end
preload["howl.modules.tasks.pack.template"] = function(...)
return "local files = ${files}\
\
${vfs}\
\
local root = \"\"\
local args = {...}\
if #args == 1 and args[1] == '--extract' then\
	extract(root, files, \"\", root)\
else\
	local env = makeEnv(root, files)\
	local func, err = env.loadfile(${startup})\
	if not func then error(err, 0) end\
	return func(...)\
end"
end
preload["howl.modules.tasks.pack"] = function(...)
--- A task to combine multiple files into one which are then executed within a virtual file system.
-- @module howl.modules.tasks.Pack

local assert = require "howl.lib.assert"
local dump = require "howl.lib.dump"
local fs = require "howl.platform".fs
local mixin = require "howl.class.mixin"
local rebuild = require "howl.lexer.rebuild"

local CopySource = require "howl.files.CopySource"
local Runner = require "howl.tasks.Runner"
local Task = require "howl.tasks.Task"

local formatTemplate = require "howl.lib.utils".formatTemplate

local template = require "howl.modules.tasks.pack.template"
local vfs = require "howl.modules.tasks.pack.vfs"

local PackTask = Task:subclass("howl.modules.tasks.pack.PackTask")
	:include(mixin.filterable)
	:include(mixin.delegate("sources", {"from", "include", "exclude"}))
	:addOptions { "minify", "startup", "output" }

function PackTask:initialize(context, name, dependencies)
	Task.initialize(self, name, dependencies)

	self.root = context.root
	self.sources = CopySource()
	self.sources:modify(function(file)
		local contents = file.contents
		if self.options.minify and loadstring(contents) then
			return rebuild.minifyString(contents)
		end
	end)

	self:exclude { ".git", ".svn", ".gitignore", context.out }

	self:description("Combines multiple files using Pack")
end

function PackTask:configure(item)
	Task.configure(self, item)
	self.sources:configure(item)
end

-- TODO: Add a custom "ouput" mixin
function PackTask:output(value)
	assert.argType(value, "string", "output", 1)
	if self.options.output then error("Cannot set output multiple times") end

	self.options.output = value
	self:Produces(value)
end

function PackTask:setup(context, runner)
	Task.setup(self, context, runner)

	if not self.options.startup then
		context.logger:error("Task '%s': No startup file", self.name)
	end
	self:requires(self.options.startup)

	if not self.options.output then
		context.logger:error("Task '%s': No output file", self.name)
 	end
end

function PackTask:runAction(context)
	local files = self.sources:gatherFiles(self.root)
	local startup = self.options.startup
	local output = self.options.output
	local minify = self.options.minify

	local resultFiles = {}
	for _, file in pairs(files) do
		context.logger:verbose("Including " .. file.relative)
		resultFiles[file.name] = file.contents
	end

	local result = formatTemplate(template, {
		files = dump.serialise(resultFiles),
		startup = ("%q"):format(startup),
		vfs = vfs,
	})

	if minify then
		result = rebuild.minifyString(result)
	end

	fs.write(fs.combine(context.root, output), result)
end


local PackExtensions = { }

function PackExtensions:pack(name, taskDepends)
	return self:injectTask(PackTask(self.env, name, taskDepends))
end

local function apply()
	Runner:include(PackExtensions)
end

return {
	name = "pack task",
	description = "A task to combine multiple files into one which are then executed within a virtual file system.",
	apply = apply,

	PackTask = PackTask,
}
end
preload["howl.modules.tasks.minify"] = function(...)
--- Adds various tasks to minify files.
-- @module howl.modules.tasks.minify

local assert = require "howl.lib.assert"
local rebuild = require "howl.lexer.rebuild"


local Runner = require "howl.tasks.Runner"
local Task = require "howl.tasks.Task"

local minifyFile = rebuild.minifyFile
local minifyDiscard = function(self, env, i, o)
	return minifyFile(env.root, i, o)
end

local MinifyTask = Task:subclass("howl.modules.minify.tasks.MinifyTask")
	:addOptions { "input", "output" }

function MinifyTask:initialize(context, name, dependencies)
	Task.initialize(self, name, dependencies)

	self:description "Minify a file"
end

function MinifyTask:input(value)
	assert.argType(value, "string", "input", 1)
	if self.options.input then error("Cannot set input multiple times") end

	self.options.input = value
	self:requires(value)
end

function MinifyTask:output(value)
	assert.argType(value, "string", "output", 1)
	if self.options.output then error("Cannot set output multiple times") end

	self.options.output = value
	self:Produces(value)
end

function MinifyTask:setup(context, runner)
	Task.setup(self, context, runner)

	if not self.options.input then
		context.logger:error("Task '%s': No input file specified", self.name)
	end

	if not self.options.output then
		context.logger:error("Task '%s': No output file specified", self.name)
	end
end

function MinifyTask:runAction(context)
	local oldSize, newSize = minifyFile(context.root, self.options.input, self.options.output)
	local percentDecreased = (oldSize - newSize) / oldSize * 100

	-- Ugly hack as length specifiers don't work on %f under LuaJ.
	percentDecreased = math.floor(percentDecreased * 100) / 100
	context.logger:verbose(("%.20f%% decrease in file size"):format(percentDecreased))
end

local MinifyExtensions = {}

function MinifyExtensions:minify(name, taskDepends)
	return self:injectTask(MinifyTask(self.env, name, taskDepends))
end

--- A task that minifies to a pattern instead
-- @tparam string name Name of the task
-- @tparam string inputPattern The pattern to read in
-- @tparam string outputPattern The pattern to produce
-- @treturn howl.tasks.Task The created task
function MinifyExtensions:addMinifier(name, inputPattern, outputPattern)
	name = name or "_minify"
	return self:addTask(name, {}, minifyDiscard)
		:Description("Minifies files")
		:Maps(inputPattern or "wild:*.lua", outputPattern or "wild:*.min.lua")
end

local function apply()
	Runner:include(MinifyExtensions)
end

local function setup(context)
	context.mediator:subscribe({ "HowlFile", "env" }, function(env)
		env.minify = minifyFile
	end)
end

return {
	name = "minify task",
	description = "Adds various tasks to minify files.",
	apply = apply,
	setup = setup,
}
end
preload["howl.modules.tasks.gist"] = function(...)
--- A task that uploads files to a Gist.
-- @module howl.modules.tasks.gist

local assert = require "howl.lib.assert"
local mixin = require "howl.class.mixin"
local settings = require "howl.lib.settings"
local json = require "howl.lib.json"
local platform = require "howl.platform"

local http = platform.http

local Buffer = require "howl.lib.Buffer"
local Task = require "howl.tasks.Task"
local Runner = require "howl.tasks.Runner"
local CopySource = require "howl.files.CopySource"

local GistTask = Task:subclass("howl.modules.tasks.gist.GistTask")
	:include(mixin.filterable)
	:include(mixin.delegate("sources", {"from", "include", "exclude"}))
	:addOptions { "gist", "summary" }

function GistTask:initialize(context, name, dependencies)
	Task.initialize(self, name, dependencies)

	self.root = context.root
	self.sources = CopySource()
	self:exclude { ".git", ".svn", ".gitignore" }

	self:description "Uploads files to a gist"
end

function GistTask:configure(item)
	Task.configure(self, context, runner)
	self.sources:configure(item)
end

function GistTask:setup(context, runner)
	Task.setup(self, context, runner)
	if not self.options.gist then
		context.logger:error("Task '%s': No gist ID specified", self.name)
	end
	if not settings.githubKey then
		context.logger:error("Task '%s': No GitHub API key specified. Goto https://github.com/settings/tokens/new to create one.", self.name)
	end
end

function GistTask:runAction(context)
	local files = self.sources:gatherFiles(self.root)
	local gist = self.options.gist
	local token = settings.githubKey

	local out = {}

	for _, file in pairs(files) do
		context.logger:verbose("Including " .. file.relative)
		out[file.name] = { content = file.contents }
	end

	local url = "https://api.github.com/gists/" .. gist .. "?access_token=" .. token
	local headers = { Accept = "application/vnd.github.v3+json", ["X-HTTP-Method-Override"] = "PATCH" }
	local data = json.encodePretty({ files = out, description = self.options.summary })

	local ok, handle, message = http.request(url, data, headers)
	if not ok then
		if handle then
			context.logger:error(handle.readAll())
		end

		error(result, 0)
	end
end

local GistExtensions = { }

function GistExtensions:gist(name, taskDepends)
	return self:injectTask(GistTask(self.env, name, taskDepends))
end

local function apply()
	Runner:include(GistExtensions)
end

return {
	name = "gist task",
	description = "A task that uploads files to a Gist.",
	apply = apply,

	GistTask = GistTask,
}
end
preload["howl.modules.tasks.clean"] = function(...)
--- A task that deletes all specified files
-- @module howl.modules.tasks.clean

local mixin = require "howl.class.mixin"
local fs = require "howl.platform".fs

local Task = require "howl.tasks.Task"
local Runner = require "howl.tasks.Runner"
local Source = require "howl.files.Source"

local CleanTask = Task:subclass("howl.modules.tasks.clean.CleanTask")
	:include(mixin.configurable)
	:include(mixin.filterable)
	:include(mixin.delegate("sources", {"from", "include", "exclude"}))

function CleanTask:initialize(context, name, dependencies)
	Task.initialize(self, name, dependencies)

	self.root = context.root
	self.sources = Source()
	self:exclude { ".git", ".svn", ".gitignore" }

	self:description "Deletes all files matching a pattern"
end

function CleanTask:configure(item)
	self.sources:configure(item)
end

function CleanTask:setup(context, runner)
	Task.setup(self, context, runner)

	local root = self.sources
	if root.allowEmpty and #root.includes == 0 then
		-- Include the build directory if nothing is set
		root:include(fs.combine(context.out, "*"))
	end
end

function CleanTask:runAction(context)
	for _, file in ipairs(self.sources:gatherFiles(self.root, true)) do
		context.logger:verbose("Deleting " .. file.path)
		fs.delete(file.path)
	end
end

local CleanExtensions = {}

function CleanExtensions:clean(name, taskDepends)
	return self:injectTask(CleanTask(self.env, name or "clean", taskDepends))
end

local function apply()
	Runner:include(CleanExtensions)
end

return {
	name = "clean task",
	description = "A task that deletes all specified files.",
	apply = apply,

	CleanTask = CleanTask,
}
end
preload["howl.modules.plugins"] = function(...)
--- A way of injecting plugins via the Howl DSL
-- @module howl.modules.plugins

local class = require "howl.class"
local mixin = require "howl.class.mixin"

local fs = require "howl.platform".fs

local Plugins = class("howl.modules.plugins")
	:include(mixin.configurable)

function Plugins:initialize(context)
	self.context = context
end

function Plugins:configure(data)
	if #data == 0 then
		self:addPlugin(data, data)
	else
		for i = 1, #data do
			self:addPlugin(data[i])
		end
	end
end

local function toModule(root, file)
	local name = file:gsub("%.lua$", ""):gsub("/", "."):gsub("^(.*)%.init$", "%1")
	if name == "" or name == "init" then
		return root
	else
		return root .. "." .. name
	end
end

function Plugins:addPlugin(data)
	if not data.type then error("No plugin type specified") end

	local type = data.type
	data.type = nil

	local file
	if data.file then
		file = data.file
		data.file = nil
	end

	local manager = self.context.packageManager
	local package = manager:addPackage(type, data)
	self.context.logger:verbose("Using plugin from package " .. package:getName())
	local fetchedFiles = package:require(file and {file})

	local root = "external." .. package:getName()

	local count = 0
	for file, loc in pairs(fetchedFiles) do
		if file:find("%.lua$") then
			count = count + 1

			local func, msg = loadfile(fetchedFiles[file], _ENV)
			if func then
				local name = toModule(root, file)
				preload[name] = func
				self.context.logger:verbose("Including plugin file " .. file .. " as " .. name)
			else
				self.context.logger:warning("Cannot load plugin file " .. file .. ": " .. msg)
			end
		end
	end

	if not file then
		if fetchedFiles["init.lua"] then
			file = "init.lua"
		elseif count == 1 then
			file = next(fetchedFiles)
		elseif count == 0 then
			self.context.logger:error(package:getName() .. " does not export any files")
			error("Error adding plugin")
		else
			self.context.logger:error("Cannot guess a file for " .. package:getName())
			error("Error adding plugin")
		end
	end

	self.context.logger:verbose("Using package " .. package:getName() .. " with " .. file)
	local name = toModule(root, file)
	if not preload[name] then
		self.context.logger:error("Cannot load plugin as " .. name .. " could not be loaded")
		error("Error adding plugin")
	end

	self.context:include(require(name))
	return self
end

return {
	name = "plugins",
	description = "Inject plugins into Howl at runtime.",

	setup = function(context)
		context.mediator:subscribe({ "HowlFile", "env" }, function(env)
			env.plugins = Plugins(context)
		end)
	end
}
end
preload["howl.modules.packages.pastebin"] = function(...)
--- A package provider that installs pastebins.
-- @module howl.modules.packages.pastebin

local class = require "howl.class"
local platform = require "howl.platform"

local Manager = require "howl.packages.Manager"
local Package = require "howl.packages.Package"

local PastebinPackage = Package:subclass("howl.modules.packages.pastebin.PastebinPackage")
	:addOptions { "id" }

--- Setup the dependency, checking if it cannot be resolved
function PastebinPackage:setup(runner)
	if not self.options.id then
		self.context.logger:error("Pastebin has no ID")
	end
end

function PastebinPackage:getName()
	return self.options.id
end

function PastebinPackage:files(previous)
	if previous then
		return {}
	else
		return { ["init.lua"] = platform.fs.combine(self.installDir, "init.lua") }
	end
end

function PastebinPackage:require(previous, refresh)
	local id = self.options.id
	local dir = self.installDir

	if not refresh and previous then
		return previous
	end

	local success, request = platform.http.request("http://pastebin.com/raw/" .. id)
	if not success or not request then
		self.context.logger:error("Cannot find pastebin " .. id)
		return previous
	end

	local contents = request.readAll()
	request.close()

	platform.fs.write(platform.fs.combine(dir, "init.lua"), contents)

	return { }
end


return {
	name = "pastebin package",
	description = "Allows downloading a pastebin dependency.",

	apply = function()
		Manager:addProvider(PastebinPackage, "pastebin")
	end,

	PastebinPackage = PastebinPackage,
}
end
preload["howl.modules.packages.gist"] = function(...)
--- A package provider that installs gists.
-- @module howl.modules.packages.gist

local class = require "howl.class"
local json = require "howl.lib.json"
local platform = require "howl.platform"

local Manager = require "howl.packages.Manager"
local Package = require "howl.packages.Package"

local GistPackage = Package:subclass("howl.modules.packages.gist.GistPackage")
	:addOptions { "id" }

--- Setup the dependency, checking if it cannot be resolved
function GistPackage:setup(runner)
	if not self.options.id then
		self.context.logger:error("Gist has no ID")
	end
end

function GistPackage:getName()
	return self.options.id
end

function GistPackage:files(previous)
	if previous then
		local files = {}
		for k, _ in pairs(previous.files) do
			files[k] = platform.fs.combine(self.installDir, k)
		end
		return files
	else
		return {}
	end
end

function GistPackage:require(previous, refresh)
	local id = self.options.id
	local dir = self.installDir

	if not refresh and previous then
		return previous
	end

	-- TODO: Fetch gists/:id/commits [1].version first if we have a hash
	-- TODO: Worth storing individual versions?
	local success, request = platform.http.request("https://api.github.com/gists/" .. id)
	if not success or not request then
		self.context.logger:error("Cannot find gist " .. id)
		return false
	end

	local contents = request.readAll()
	request.close()

	local data = json.decode(contents)
	local hash = data.history[1].version
	local current

	if previous and hash == previous.hash then
		current = previous
	else
		current = { hash = hash, files = {} }
		for path, file in pairs(data.files) do
			if file.truncated then
				self.context.logger:error("Skipping " .. path .. " as it is truncated")
			else
				platform.fs.write(platform.fs.combine(dir, path), file.content)
				current.files[path] = true
			end
		end
	end

	return current
end


return {
	name = "gist package",
	description = "Allows downloading a gist dependency.",

	apply = function()
		Manager:addProvider(GistPackage, "gist")
	end,

	GistPackage = GistPackage,
}
end
preload["howl.modules.packages.file"] = function(...)
--- A package provider that uses a local file.
-- @module howl.modules.packages.file

local class = require "howl.class"
local mixin = require "howl.class.mixin"
local fs = require "howl.platform".fs

local Manager = require "howl.packages.Manager"
local Package = require "howl.packages.Package"
local Source = require "howl.files.Source"

local FilePackage = Package:subclass("howl.modules.packages.file.FilePackage")
	:include(mixin.filterable)
	:include(mixin.delegate("sources", {"from", "include", "exclude"}))

function FilePackage:initialize(context, root)
	Package.initialize(self, context, root)

	self.sources = Source(false)
	self.name = tostring({}):sub(8)
	self:exclude { ".git", ".svn", ".gitignore", context.out }
end

--- Setup the dependency, checking if it cannot be resolved
function FilePackage:setup(runner)
	if not self.sources:hasFiles() then
		self.context.logger:error("No files specified")
	end
end

function FilePackage:configure(item)
	Package.configure(self, item)
	self.sources:configure(item)
end

function FilePackage:getName()
	return self.name
end

function FilePackage:files(previous)
	local files = {}
	for _, v in pairs(self.sources:gatherFiles(self.context.root)) do
		files[v.name] = v.path
	end
	return files
end

function FilePackage:require(previous, refresh)
end


return {
	name = "file package",
	description = "Allows using a local file as a dependency",

	apply = function()
		Manager:addProvider(FilePackage, "file")
	end,

	FilePackage = FilePackage,
}
end
preload["howl.modules.list"] = function(...)
--- Lists all tasks on a runner.
-- @module howl.modules.list

local assert = require "howl.lib.assert"
local colored = require "howl.lib.colored"

local Runner = require "howl.tasks.Runner"

local ListTasksExtensions = { }

function ListTasksExtensions:listTasks(indent, all)
	local taskNames = {}
	local maxLength = 0
	for name, task in pairs(self.tasks) do
		local start = name:sub(1, 1)
		if all or (start ~= "_" and start ~= ".") then
			local description = task.options.description or ""
			local length = #name
			if length > maxLength then
				maxLength = length
			end

			taskNames[name] = description
		end
	end

	maxLength = maxLength + 2
	indent = indent or ""
	for name, description in pairs(taskNames) do
		colored.writeColor("white", indent .. name)
		colored.printColor("lightGray", string.rep(" ", maxLength - #name) .. description)
	end

	return self
end

local function apply()
	Runner:include(ListTasksExtensions)
end

return {
	name = "list",
	description = "List all tasks on a runner.",
	apply = apply,
}
end
preload["howl.modules.dependencies.task"] = function(...)
--- Allows depending on a task.
-- @module howl.modules.dependencies.task

local assert = require "howl.lib.assert"
local Task = require "howl.tasks.Task"
local Dependency = require "howl.tasks.Dependency"

local TaskDependency = Dependency:subclass("howl.modules.dependencies.task.TaskDependency")

--- Create a new task dependency
function TaskDependency:initialize(task, name)
	Dependency.initialize(self, task)

	assert.argType(name, "string", "initialize", 1)
	self.name = name
end

function TaskDependency:setup(context, runner)
	if not runner.tasks[self.name] then
		context.logger:error("Task '%s': cannot resolve dependency '%s'", self.task.name, self.name)
	end
end

function TaskDependency:resolve(context, runner)
	return runner:run(self.name)
end

return {
	name = "task dependency",
	description = "Allows depending on a task.",

	apply = function()
		Task:addDependency(TaskDependency, "depends")
	end,

	TaskDependency = TaskDependency,
}
end
preload["howl.modules.dependencies.file"] = function(...)
--- Allows depending on a file.
-- @module howl.modules.dependencies.file

local assert = require "howl.lib.assert"
local Task = require "howl.tasks.Task"
local Dependency = require "howl.tasks.Dependency"

local FileDependency = Dependency:subclass("howl.modules.dependencies.file.FileDependency")

--- Create a new task dependency
function FileDependency:initialize(task, path)
	Dependency.initialize(self, task)

	assert.argType(path, "string", "initialize", 1)
	self.path = path
end

function FileDependency:setup(context, runner)
	-- TODO: Check that this can be resolved
end

function FileDependency:resolve(context, runner)
	return runner:DoRequire(self.path)
end

return {
	name = "file dependency",
	description = "Allows depending on a file.",

	apply = function()
		Task:addDependency(FileDependency, "requires")
	end,

	FileDependency = FileDependency,
}
end
preload["howl.loader"] = function(...)
--- Handles loading and creation of HowlFiles
-- @module howl.loader

local fs = require "howl.platform".fs
local Runner = require "howl.tasks.Runner"
local Utils = require "howl.lib.utils"

--- Names to test when searching for Howlfiles
local Names = { "Howlfile", "Howlfile.lua" }

--- Finds the howl file
-- @treturn string The name of the howl file or nil if not found
-- @treturn string The path of the howl file or the error message if not found
local function FindHowl()
	local currentDirectory = fs.currentDir()

	while true do
		for _, file in ipairs(Names) do
			local howlFile = fs.combine(currentDirectory, file)
			if fs.exists(howlFile) and not fs.isDir(howlFile) then
				return file, currentDirectory
			end
		end

		if currentDirectory == "/" or currentDirectory == "" then
			break
		end
		currentDirectory = fs.getDir(currentDirectory)
	end


	return nil, "Cannot find HowlFile. Looking for '" .. table.concat(Names, "', '") .. "'."
end

--- Create an environment for running howl files
-- @tparam table variables A list of variables to include in the environment
-- @treturn table The created environment
local function SetupEnvironment(variables)
	local env = setmetatable(variables or {}, { __index = _ENV })

	function env.loadfile(path)
		return assert(loadfile(path, env))
	end

	function env.dofile(path)
		return env.loadfile(path)()
	end

	return env
end

--- Setup tasks
-- @tparam howl.Context context The current environment
-- @tparam string howlFile location of Howlfile relative to current directory
-- @treturn Runner The task runner
local function SetupTasks(context, howlFile)
	local tasks = Runner(context)

	context.mediator:subscribe({ "ArgParse", "changed" }, function(options)
		tasks.ShowTime = options:Get "time"
		tasks.Traceback = options:Get "trace"
	end)

	-- Setup an environment
	local environment = SetupEnvironment({
		-- Core globals
		require = require,
		CurrentDirectory = context.root,
		Tasks = tasks,
		Options = context.arguments,
		-- Helper functions
		Verbose = context.logger/"verbose",
		Log = context.logger/"dump",
		File = function(...) return fs.combine(context.root, ...) end,
	})

	context.mediator:publish({ "HowlFile", "env" }, environment, context)

	return tasks, environment
end


--- @export
return {
	FindHowl = FindHowl,
	SetupEnvironment = SetupEnvironment,
	SetupTasks = SetupTasks,
	Names = Names,
}
end
preload["howl.lib.utils"] = function(...)
--- Useful little helpers for things
-- @module howl.lib.utils

local assert = require "howl.lib.assert"

local matches = {
	["^"] = "%^",
	["$"] = "%$",
	["("] = "%(",
	[")"] = "%)",
	["%"] = "%%",
	["."] = "%.",
	["["] = "%[",
	["]"] = "%]",
	["*"] = "%*",
	["+"] = "%+",
	["-"] = "%-",
	["?"] = "%?",
	["\0"] = "%z",
}

--- Escape a string for using in a pattern
-- @tparam string pattern The string to escape
-- @treturn string The escaped pattern
local function escapePattern(pattern)
	return (pattern:gsub(".", matches))
end

local basicMatches = {
	["^"] = "%^",
	["$"] = "%$",
	["("] = "%(",
	[")"] = "%)",
	["%"] = "%%",
	["."] = "%.",
	["["] = "%[",
	["]"] = "%]",
	["+"] = "%+",
	["-"] = "%-",
	["?"] = "%?",
	["\0"] = "%z",
}

--- A resulting pattern
-- @table Pattern
-- @tfield string Type `Pattern` or `Normal`
-- @tfield string Text The resulting pattern

--- Parse a series of patterns
-- @tparam string text Pattern to parse
-- @tparam boolean invert If using a wildcard, invert it
-- @treturn Pattern
local function parsePattern(text, invert)
	local beginning = text:sub(1, 5)
	if beginning == "ptrn:" or beginning == "wild:" then

		local text = text:sub(6)
		if beginning == "wild:" then
			if invert then
				local counter = 0
				-- Escape the pattern and then replace wildcards with the results of the capture %1, %2, etc...
				text = ((text:gsub(".", basicMatches)):gsub("(%*)", function()
					counter = counter + 1
					return "%" .. counter
				end))
			else
				-- Escape the pattern and replace wildcards with (.*) capture
				text = "^" .. ((text:gsub(".", basicMatches)):gsub("(%*)", "(.*)")) .. "$"
			end
		end

		return { Type = "Pattern", Text = text }
	else
		return { Type = "Normal", Text = text }
	end
end

--- Create a lookup table from a list of values
-- @tparam table tbl The table of values
-- @treturn The same table, with lookups as well
local function createLookup(tbl)
	for _, v in ipairs(tbl) do
		tbl[v] = true
	end
	return tbl
end

--- Checks if two tables are equal
-- @tparam table a
-- @tparam table b
-- @treturn boolean If they match
local function matchTables(a, b)
	local length = #a
	if length ~= #b then return false end

	for i = 1, length do
		if a[i] ~= b[i] then return false end
	end
	return true
end

local function startsWith(string, text)
	if string:sub(1, #text) == text then
		return string:sub(#text + 1)
	else
		return false
	end
end

--- Format a template string with data.
-- Anything of the form `${var}` will be replaced with the appropriate variable in the table.
-- @tparam string template The template to format
-- @tparam table data The data to replace with
-- @treturn string The formatted template
local function formatTemplate(template, data)
	return (template:gsub("${([^}]+)}", function(str)
		local res = data[str]
		if res == nil then
			return "${" .. str .. "}"
		else
			return tostring(res)
		end
	end))
end

--- Mark a function as deprecated
-- @tparam string name The name of the function
-- @tparam function function The function to delegate to
-- @tparam string|nil msg Additional message to print
local function deprecated(name, func, msg)
	assert.argType(name, "string", "deprecated", 1)
	assert.argType(func, "function", "deprecated", 2)

	if msg ~= nil then
		assert.argType(msg, "string", "msg", 4)
		msg = " " .. msg
	else
		msg = ""
	end

	local doneDeprc = false
	return function(...)
		if not doneDeprc then
			local _, callee = pcall(error, "", 3)
			callee = callee:gsub(":%s*$", "")
			print(name .. " is deprecated (called at " .. callee .. ")." .. msg)
			doneDeprc = true
		end

		return func(...)
	end
end

--- @export
return {
	escapePattern = escapePattern,
	parsePattern = parsePattern,
	createLookup = createLookup,
	matchTables = matchTables,
	startsWith = startsWith,
	formatTemplate = formatTemplate,
	deprecated = deprecated,
}
end
preload["howl.lib.settings"] = function(...)
local platform = require "howl.platform"
local fs = platform.fs
local dump = require "howl.lib.dump"

local currentSettings = {
}

if fs.exists(".howl.settings.lua") then
	local contents = fs.read(".howl.settings.lua")

	for k, v in pairs(dump.unserialise(contents)) do
		currentSettings[k] = v
	end
end

if fs.exists(".howl/settings.lua") then
	local contents = fs.read(".howl/settings.lua")

	for k, v in pairs(dump.unserialise(contents)) do
		currentSettings[k] = v
	end
end

-- Things have to be defined in currentSettings for this to work. We need to improve this.
for k, v in pairs(currentSettings) do
	currentSettings[k] = platform.os.getEnv("howl." .. k, v)
end

return currentSettings
end
preload["howl.lib.mediator"] = function(...)
--- Mediator pattern implementation for pub-sub management
--
-- [Adapted from Olivine Labs' Mediator](http://olivinelabs.com/mediator_lua/)
-- @module howl.lib.mediator

local class = require "howl.class"
local mixin = require "howl.class.mixin"

local function getUniqueId()
	return tonumber(tostring({}):match(':%s*[0xX]*(%x+)'), 16)
end

--- A subscriber to a channel
-- @type Subscriber
local Subscriber = class("howl.lib.mediator.Subscriber"):include(mixin.sealed)

--- Create a new subscriber
-- @tparam function fn The function to execute
-- @tparam table options Options to use
-- @constructor
function Subscriber:initialize(fn, options)
	self.id = getUniqueId()
	self.options = options or {}
	self.fn = fn
end

--- Update the subscriber with new options
-- @tparam table options Options to use
function Subscriber:update(options)
	self.fn = options.fn or self.fn
	self.options = options.options or self.options
end


--- Channel class and functions
-- @type Channel
local Channel = class("howl.lib.mediator.Channel"):include(mixin.sealed)

function Channel:initialize(namespace, parent)
	self.stopped = false
	self.namespace = namespace
	self.callbacks = {}
	self.channels = {}
	self.parent = parent
end

function Channel:addSubscriber(fn, options)
	local callback = Subscriber(fn, options)
	local priority = (#self.callbacks + 1)

	options = options or {}

	if options.priority and
		options.priority >= 0 and
		options.priority < priority
	then
		priority = options.priority
	end

	table.insert(self.callbacks, priority, callback)

	return callback
end

function Channel:getSubscriber(id)
	for i = 1, #self.callbacks do
		local callback = self.callbacks[i]
		if callback.id == id then return { index = i, value = callback } end
	end
	local sub
	for _, channel in pairs(self.channels) do
		sub = channel:getSubscriber(id)
		if sub then break end
	end
	return sub
end

function Channel:setPriority(id, priority)
	local callback = self:getSubscriber(id)

	if callback.value then
		table.remove(self.callbacks, callback.index)
		table.insert(self.callbacks, priority, callback.value)
	end
end

function Channel:addChannel(namespace)
	self.channels[namespace] = Channel(namespace, self)
	return self.channels[namespace]
end

function Channel:hasChannel(namespace)
	return namespace and self.channels[namespace] and true
end

function Channel:getChannel(namespace)
	return self.channels[namespace] or self:addChannel(namespace)
end

function Channel:removeSubscriber(id)
	local callback = self:getSubscriber(id)

	if callback and callback.value then
		for _, channel in pairs(self.channels) do
			channel:removeSubscriber(id)
		end

		return table.remove(self.callbacks, callback.index)
	end
end

function Channel:publish(result, ...)
	for i = 1, #self.callbacks do
		local callback = self.callbacks[i]

		-- if it doesn't have a predicate, or it does and it's true then run it
		if not callback.options.predicate or callback.options.predicate(...) then
			-- just take the first result and insert it into the result table
			local continue, value = callback.fn(...)

			if value ~= nil then table.insert(result, value) end
			if continue == false then return false, result end
		end
	end

	if self.parent then
		return self.parent:publish(result, ...)
	else
		return true, result
	end
end

--- Mediator class and functions
local Mediator = setmetatable(
	{
		Channel = Channel,
		Subscriber = Subscriber
	},
	{
		__call = function(fn, options)
			return {
				channel = Channel('root'),

				getChannel = function(self, channelNamespace)
					local channel = self.channel

					for i=1, #channelNamespace do
						channel = channel:getChannel(channelNamespace[i])
					end

					return channel
				end,

				subscribe = function(self, channelNamespace, fn, options)
					return self:getChannel(channelNamespace):addSubscriber(fn, options)
				end,

				getSubscriber = function(self, id, channelNamespace)
					return self:getChannel(channelNamespace):getSubscriber(id)
				end,

				removeSubscriber = function(self, id, channelNamespace)
					return self:getChannel(channelNamespace):removeSubscriber(id)
				end,

				publish = function(self, channelNamespace, ...)
					return self:getChannel(channelNamespace):publish({}, ...)
				end
			}
		end
	}
)
return Mediator()
end
preload["howl.lib.json"] = function(...)
local controls = {["\n"]="\\n", ["\r"]="\\r", ["\t"]="\\t", ["\b"]="\\b", ["\f"]="\\f", ["\""]="\\\"", ["\\"]="\\\\"}
local function isArray(t)
	local max = 0
	for k,v in pairs(t) do
		if type(k) ~= "number" then
			return false
		elseif k > max then
			max = k
		end
	end
	return max == #t
end


local function encodeCommon(val, pretty, tabLevel, tTracking, ctx)
	local str = ""

	-- Tabbing util
	local function tab(s)
		str = str .. ("\t"):rep(tabLevel) .. s
	end

	local function arrEncoding(val, bracket, closeBracket, iterator, loopFunc)
		str = str .. bracket
		if pretty then
			str = str .. "\n"
			tabLevel = tabLevel + 1
		end
		for k,v in iterator(val) do
			tab("")
			loopFunc(k,v)
			str = str .. ","
			if pretty then str = str .. "\n" end
		end
		if pretty then
			tabLevel = tabLevel - 1
		end
		if str:sub(-2) == ",\n" then
			str = str:sub(1, -3) .. "\n"
		elseif str:sub(-1) == "," then
			str = str:sub(1, -2)
		end
		tab(closeBracket)
	end

	-- Table encoding
	if type(val) == "table" then
		assert(not tTracking[val], "Cannot encode a table holding itself recursively")
		tTracking[val] = true
		if isArray(val) then
			arrEncoding(val, "[", "]", ipairs, function(k,v)
				str = str .. encodeCommon(v, pretty, tabLevel, tTracking)
			end)
		else
			arrEncoding(val, "{", "}", pairs, function(k,v)
				assert(type(k) == "string", "JSON object keys must be strings", 2)
				str = str .. encodeCommon(k, pretty, tabLevel, tTracking)
				str = str .. (pretty and ": " or ":") .. encodeCommon(v, pretty, tabLevel, tTracking, k)
			end)
		end
	-- String encoding
	elseif type(val) == "string" then
		str = '"' .. val:gsub("[%c\"\\]", controls) .. '"'
	-- Number encoding
	elseif type(val) == "number" or type(val) == "boolean" then
		str = tostring(val)
	else
		error("JSON only supports arrays, objects, numbers, booleans, and strings, got " .. type(val) .. " in " .. tostring(ctx), 2)
	end
	return str
end

local function encode(val)
	return encodeCommon(val, false, 0, {})
end

local function encodePretty(val)
	return encodeCommon(val, true, 0, {})
end

-- Decoding
local whites = {['\n']=true; ['\r']=true; ['\t']=true; [' ']=true; [',']=true; [':']=true}
local function removeWhite(str)
	while whites[str:sub(1, 1)] do
		str = str:sub(2)
	end
	return str
end

local decodeControls = {}
for k,v in pairs(controls) do
	decodeControls[v] = k
end

local function parseBoolean(str)
	if str:sub(1, 4) == "true" then
		return true, removeWhite(str:sub(5))
	else
		return false, removeWhite(str:sub(6))
	end
end

local function parseNull(str)
	return nil, removeWhite(str:sub(5))
end

local numChars = {['e']=true; ['E']=true; ['+']=true; ['-']=true; ['.']=true}
local function parseNumber(str)
	local i = 1
	while numChars[str:sub(i, i)] or tonumber(str:sub(i, i)) do
		i = i + 1
	end
	local val = tonumber(str:sub(1, i - 1))
	str = removeWhite(str:sub(i))
	return val, str
end

local function parseString(str)
	str = str:sub(2)
	local s = ""
	while str:sub(1,1) ~= "\"" do
		local next = str:sub(1,1)
		str = str:sub(2)
		assert(next ~= "\n", "Unclosed string")

		if next == "\\" then
			local escape = str:sub(1,1)
			str = str:sub(2)

			next = assert(decodeControls[next..escape], "Invalid escape character")
		end

		s = s .. next
	end
	return s, removeWhite(str:sub(2))
end

local parseValue
local function parseArray(str)
	str = removeWhite(str:sub(2))

	local val = {}
	local i = 1
	while str:sub(1, 1) ~= "]" do
		local v = nil
		v, str = parseValue(str)
		val[i] = v
		i = i + 1
		str = removeWhite(str)
	end
	str = removeWhite(str:sub(2))
	return val, str
end

local function parseMember(str)
	local k = nil
	k, str = parseValue(str)
	local val = nil
	val, str = parseValue(str)
	return k, val, str
end

local function parseObject(str)
	str = removeWhite(str:sub(2))

	local val = {}
	while str:sub(1, 1) ~= "}" do
		local k, v = nil, nil
		k, v, str = parseMember(str)
		val[k] = v
		str = removeWhite(str)
	end
	str = removeWhite(str:sub(2))
	return val, str
end

function parseValue(str)
	local fchar = str:sub(1, 1)
	if fchar == "{" then
		return parseObject(str)
	elseif fchar == "[" then
		return parseArray(str)
	elseif tonumber(fchar) ~= nil or numChars[fchar] then
		return parseNumber(str)
	elseif str:sub(1, 4) == "true" or str:sub(1, 5) == "false" then
		return parseBoolean(str)
	elseif fchar == "\"" then
		return parseString(str)
	elseif str:sub(1, 4) == "null" then
		return parseNull(str)
	end
	return nil
end

local function decode(str)
	str = removeWhite(str)
	return parseValue(str)
end

return {
	encode = encode,
	encodePretty = encodePretty,
	decode = decode,
}
end
preload["howl.lib.dump"] = function(...)
--- Allows formatting tables for logging and storing
-- @module howl.lib.dump

local Buffer = require("howl.lib.Buffer")
local createLookup = require("howl.lib.utils").createLookup

local type, tostring, format = type, tostring, string.format
local getmetatable, error = getmetatable, error

-- TODO: Switch to LuaCP's pprint
local function dumpImpl(t, tracking, indent, tupleLength)
	local objType = type(t)
	if objType == "table" and not tracking[t] then
		tracking[t] = true

		if next(t) == nil then
			return "{}"
		else
			local shouldNewLine = false
			local length = #t

			local builder = 0
			for k,v in pairs(t) do
				if type(k) == "table" or type(v) == "table" then
					shouldNewLine = true
					break
				elseif type(k) == "number" and k >= 1 and k <= length and k % 1 == 0 then
					builder = builder + #tostring(v) + 2
				else
					builder = builder + #tostring(v) + #tostring(k) + 2
				end

				if builder > 40 then
					shouldNewLine = true
					break
				end
			end

			local newLine, nextNewLine, subIndent = "", ", ", " "
			if shouldNewLine then
				newLine = "\n"
				nextNewLine = ",\n"
				subIndent = indent .. " "
			end

			local result, n = {(tupleLength and "(" or "{") .. newLine}, 1

			local seen = {}
			local first = true
			for k = 1, length do
				seen[k] = true
				n = n + 1
				local entry = subIndent .. dumpImpl(t[k], tracking, subIndent)

				if not first then
					entry = nextNewLine .. entry
				else
					first = false
				end

				result[n] = entry
			end

			for k,v in pairs(t) do
				if not seen[k] then
					local entry
					if type(k) == "string" and string.match( k, "^[%a_][%a%d_]*$" ) then
						entry = k .. " = " .. dumpImpl(v, tracking, subIndent)
					else
						entry = "[" .. dumpImpl(k, tracking, subIndent) .. "] = " .. dumpImpl(v, tracking, subIndent)
					end

					entry = subIndent .. entry

					if not first then
						entry = nextNewLine .. entry
					else
						first = false
					end

					n = n + 1
					result[n] = entry
				end
			end

			n = n + 1
			result[n] = newLine .. indent .. (tupleLength and ")" or "}")
			return table.concat(result)
		end

	elseif objType == "string" then
		return (string.format("%q", t):gsub("\\\n", "\\n"))
	else
		return tostring(t)
	end
end

local function dump(t, n)
	return dumpImpl(t, {}, "", n)
end

local keywords = createLookup {
	"and", "break", "do", "else", "elseif", "end", "false",
	"for", "function", "if", "in", "local", "nil", "not", "or",
	"repeat", "return", "then", "true", "until", "while",
}

--- Internal serialiser
-- @param object The object being serialised
-- @tparam table tracking List of items being tracked
-- @tparam Buffer buffer Buffer to append to
-- @treturn Buffer The buffer passed
local function internalSerialise(object, tracking, buffer)
	local sType = type(object)
	if sType == "table" then
		if tracking[object] then
			error("Cannot serialise table with recursive entries", 1)
		end
		tracking[object] = true

		if next(object) == nil then
			buffer:append("{}")
		else
			-- Other tables take more work
			buffer:append("{")

			local seen = {}
			-- Attempt array only method
			for k, v in ipairs(object) do
				seen[k] = true
				internalSerialise(v, tracking, buffer)
				buffer:append(",")
			end
			for k, v in pairs(object) do
				if not seen[k] then
					if type(k) == "string" and not keywords[k] and k:match("^[%a_][%a%d_]*$") then
						buffer:append(k .. "=")
					else
						buffer:append("[")
						internalSerialise(k, tracking, buffer)
						buffer:append("]=")
					end

					internalSerialise(v, tracking, buffer)
					buffer:append(",")
				end
			end
			buffer:append("}")
		end
	elseif sType == "string" then
		buffer:append(format("%q", object))
	elseif sType == "number" or sType == "boolean" or sType == "nil" then
		buffer:append(tostring(object))
	else
		error("Cannot serialise type " .. sType)
	end

	return buffer
end

--- Used for serialising a data structure.
--
-- This does not handle recursive structures or functions.
-- @param object The object to dump
-- @treturn string The serialised string
local function serialise(object)
	return internalSerialise(object, {}, Buffer()):toString()
end

local function unserialise(msg)
	local func = loadstring("return " .. msg, "unserialise-temp", nil, {})
	if not func then return nil end

	local ok, res = pcall(func)
	return ok and res
end
--- @export
return {
	serialise = serialise,
	unserialise = unserialise,
	deserialise = unserialise,
	dump = dump,
}
end
preload["howl.lib.colored"] = function(...)
--- Print coloured strings
-- @module howl.lib.utils

local term = require "howl.platform".term

--- Prints a string in a colour if colour is supported
-- @tparam int color The colour to print
-- @param ... Values to print
local function printColor(color, ...)
	term.setColor(color)
	term.print(...)
	term.resetColor(color)
end

--- Writes a string in a colour if colour is supported
-- @tparam int color The colour to print
-- @tparam string text Values to print
local function writeColor(color, text)
	term.setColor(color)
	term.write(text)
	term.resetColor(color)
end

return {
	printColor = printColor,
	writeColor = writeColor,
}
end
preload["howl.lib.assert"] = function(...)
--- Assertion helpers
-- @module howl.lib.assert

local type, error, floor, select = type, error, select, math.floor

local nativeAssert = assert
local assert = setmetatable(
	{ assert = nativeAssert },
	{ __call = function(self, ...) return nativeAssert(...) end }
)

local function typeError(type, expected, message)
	if message then
		return error(message:format(type))
	else
		return error(expected .. " expected, got " .. type)
	end
end

function assert.type(value, expected, message)
	local t = type(value)
	if t ~= expected then
		return typeError(t, expected, message)
	end
end

local function argError(type, expected, func, index)
	return error("bad argument #" .. index .. " for " .. func .. " (expected " .. expected .. ", got " .. type .. ")")
end

function assert.argType(value, expected, func, index)
	local t = type(value)
	if t ~= expected then
		return argError(t, expected, func, index)
	end
end

function assert.args(func, ...)
	local len = select('#', ...)
	local args = {...}

	for k = 1, len, 2 do
		local t = type(args[i])
		local expected = args[i + 1]
		if t ~= expected then
			return argError(t, expected, func, math.floor(k / 2))
		end
	end
end

assert.typeError = typeError
assert.argError = argError

function assert.class(value, expected, message)
	local t = type(value)
	if t ~= "table" or not value.isInstanceOf then
		return typeError(t, expected, message)
	elseif not value:isInstanceOf(expected) then
		return typeError(value.class.name, expected, message)
	end
end

return assert
end
preload["howl.lib.argparse"] = function(...)
--- Parses command line arguments
-- @module howl.lib.argparse

local colored = require "howl.lib.colored"

--- Simple wrapper for Options
-- @type Option
local Option = {
	__index = function(self, func)
		return function(self, ...)
			local parser = self.parser
			local value = parser[func](parser, self.name, ...)

			if value == parser then return self end -- Allow chaining
			return value
		end
	end
}

--- Parses command line arguments
-- @type Parser
local Parser = {}

--- Returns the value of a option
-- @tparam string name The name of the option
-- @tparam string|boolean default The default value (optional)
-- @treturn string|boolean The value of the option
function Parser:Get(name, default)
	local options = self.options

	local value = options[name]
	if value ~= nil then return value end

	local settings = self.settings[name]
	if settings then
		local aliases = settings.aliases
		if aliases then
			for _, alias in ipairs(aliases) do
				value = options[alias]
				if value ~= nil then return value end
			end
		end

		value = settings.default
		if value ~= nil then return value end
	end


	return default
end

--- Ensure a option exists, throw an error otherwise
-- @tparam string name The name of the option
-- @treturn string|boolean The resulting value
function Parser:Ensure(name)
	local value = self:Get(name)
	if value == nil then
		error(name .. " must be set")
	end
	return value
end

--- Set the default value for an option
-- @tparam string name The name of the options
-- @tparam string|boolean value The default value
-- @treturn Parser The current object
function Parser:Default(name, value)
	if value == nil then value = true end
	self:_SetSetting(name, "default", value)

	self:_Changed()
	return self
end

--- Sets an alias for an option
-- @tparam string name The name of the option
-- @tparam string alias The alias of the option
-- @treturn Parser The current object
function Parser:Alias(name, alias)
	local settings = self.settings
	local currentSettings = settings[name]
	if currentSettings then
		local currentAliases = currentSettings.aliases
		if currentAliases == nil then
			currentSettings.aliases = { alias }
		else
			table.insert(currentAliases, alias)
		end
	else
		settings[name] = { aliases = { alias } }
	end

	self:_Changed()
	return self
end

--- Sets the description, and type for an option
-- @tparam string name The name of the option
-- @tparam string description The description of the option
-- @treturn Parser The current object
function Parser:Description(name, description)
	return self:_SetSetting(name, "description", description)
end

--- Sets if this option takes a value
-- @tparam string name The name of the option
-- @tparam boolean takesValue If the option takes a value
-- @treturn Parser The current object
function Parser:TakesValue(name, takesValue)
	if takesValue == nil then
		takesValue = true
	end
	return self:_SetSetting(name, "takesValue", takesValue)
end

--- Sets a setting for an option
-- @tparam string name The name of the option
-- @tparam string key The key of the setting
-- @tparam boolean|string value The value of the setting
-- @treturn Parser The current object
-- @local
function Parser:_SetSetting(name, key, value)
	local settings = self.settings
	local thisSettings = settings[name]

	if thisSettings then
		thisSettings[key] = value
	else
		settings[name] = { [key] = value }
	end

	return self
end

--- Creates a useful option helper object
-- @tparam string name The name of the option
-- @treturn Option The created option
function Parser:Option(name)
	return setmetatable({
		name = name,
		parser = self
	}, Option)
end

--- Returns a list of arguments
-- @treturn table The argument list
function Parser:Arguments()
	return self.arguments
end

--- Fires the on changed event
-- @local
function Parser:_Changed()
	self.mediator:publish({ "ArgParse", "changed" }, self)
end

--- Generates a help string
-- @tparam string indent The indent to print it at
function Parser:Help(indent)
	for name, settings in pairs(self.settings) do
		local prefix = '-'

		-- If we take a value then we should say so
		if settings.takesValue then
			prefix = "--"
			name = name .. "=value"
		end

		-- If length is more than one then we should set
		-- the prefix to be --
		if #name > 1 then
			prefix = '--'
		end

		colored.writeColor("white", indent .. prefix .. name)

		local aliasStr = ""
		local aliases = settings.aliases
		if aliases and #aliases > 0 then
			local aliasLength = #aliases
			aliasStr = aliasStr .. " ("

			for i = 1, aliasLength do
				local alias = "-" .. aliases[i]

				if #alias > 2 then -- "-" and another character
					alias = "-" .. alias
				end

				if i < aliasLength then
					alias = alias .. ', '
				end

				aliasStr = aliasStr .. alias
			end
			aliasStr = aliasStr .. ")"
		end

		colored.writeColor("brown", aliasStr)
		local description = settings.description
		if description and description ~= "" then
			colored.printColor("lightGray", " " .. description)
		end
	end
end

--- Parse the options
-- @treturn Parser The current object
function Parser:Parse(args)
	local options = self.options
	local arguments = self.arguments
	for _, arg in ipairs(args) do
		if arg:sub(1, 1) == "-" then -- Match `-`
			if arg:sub(2, 2) == "-" then -- Match `--`
				local key, value = arg:match("([%w_%-]+)=([%w_%-]+)", 3) -- Match [a-zA-Z0-9_-] in form key=value
				if key then
					options[key] = value
				else
					-- If it starts with not- or not_ then negate it
					arg = arg:sub(3)
					local beginning = arg:sub(1, 4)
					local value = true
					if beginning == "not-" or beginning == "not_" then
						value = false
						arg = arg:sub(5)
					end
					options[arg] = value
				end
			else -- Handle switches
				for i = 2, #arg do
					options[arg:sub(i, i)] = true
				end
			end
		else
			table.insert(arguments, arg)
		end
	end

	return self
end

--- Create a new options parser
-- @tparam table mediator The mediator instance
-- @tparam table args The command line arguments passed
-- @treturn Parser The resulting parser
local function Options(mediator, args)
	return setmetatable({
		options = {}, -- The resulting values
		arguments = {}, -- Spare arguments
		mediator = mediator,

		settings = {}, -- Settings for options
	}, { __index = Parser }):Parse(args)
end

--- @export
return {
	Parser = Parser,
	Options = Options,
}
end
preload["howl.lib.Logger"] = function(...)
--- The main logger for Lua
-- @classmod howl.lib.Logger

local class = require "howl.class"
local mixin = require "howl.class.mixin"
local dump = require "howl.lib.dump".dump
local colored = require "howl.lib.colored"
local platformLog = require "howl.platform".log

local select, tostring = select, tostring
local function concat(...)
	local buffer = {}
	for i = 1, select('#', ...) do
		buffer[i] = tostring(select(i, ...))
	end
	return table.concat(buffer, " ")
end

local Logger = class("howl.lib.Logger")
	:include(mixin.sealed)
	:include(mixin.curry)

function Logger:initialize(context)
	self.isVerbose = false
	context.mediator:subscribe({ "ArgParse", "changed" }, function(options)
		self.isVerbose = options:Get "verbose" or false
	end)
end

--- Print a series of objects if verbose mode is enabled
function Logger:verbose(...)
	if self.isVerbose then
		local _, m = pcall(function() error("", 4) end)
		colored.writeColor("gray", m)
		colored.printColor("lightGray", ...)
		platformLog("verbose", m .. concat(...))
	end
end

--- Dump a series of objects if verbose mode is enabled
function Logger:dump(...)
	if self.isVerbose then
		local _, m = pcall(function() error("", 4) end)
		colored.writeColor("gray", m)

		local len = select('#', ...)
		local args = {...}
		for i = 1, len do
			local value = args[i]
			local t = type(value)
			if t == "table" then
				value = dump(value)
			else
				value = tostring(value)
			end

			if i > 1 then value = " " .. value end
			-- TODO: use platformLog too.
			colored.writeColor("lightGray", value)
		end
		print()
	end
end

local types = {
	{ "success", "ok", "green" },
	{ "error", "error", "red" },
	{ "info", "info", "cyan" },
	{ "warning", "warn", "yellow" },
}

local max = 0
for _, v in ipairs(types) do
	max = math.max(max, #v[2])
end

for _, v in ipairs(types) do
	local color = v[3]
	local format = '[' .. v[2] .. ']' .. (' '):rep(max - #v[2] + 1)
	local field = "has" .. v[2]:gsub("^%l", string.upper)
	local name = v[1]

	Logger[name] = function(self, fmt, ...)
		self[field] = true
		colored.writeColor(color, format)

		local text
		if type(fmt) == "string" then
			text = fmt:format(...)
		else

		end

		colored.printColor(color, text)
		platformLog(name, text)
	end
end

return Logger
end
preload["howl.lib.Buffer"] = function(...)
--- An optimised class for appending strings
-- @classmod howl.lib.Buffer

local concat = table.concat

--- Append to this buffer
-- @tparam string text
-- @treturn Buffer The current buffer to allow chaining
local function append(self, text)
	local n = self.n + 1
	self[n] = text
	self.n = n
	return self
end

--- Convert this buffer to a string
-- @treturn string String representation of the buffer
local function toString(self)
	return concat(self)
end

--- Create a new buffer
-- @treturn Buffer The buffer
return function()
	return {
		n = 0, append = append, toString = toString
	}
end
end
preload["howl.lexer.walk"] = function(...)
local function terminate() end
local function callExpr(node, visitor)
	visitor(node.Base)
	for _, v in ipairs(node.Arguments) do visitor(v) end
end

local function indexExpr(node, visitor)
	visitor(node.Base)
	visitor(node.Index)
end

local visitors

local function visit(node, visitor)
	local traverse = visitors[node.AstType]
	if not traverse then
		error("No visitor for " .. node.AstType)
	end
	traverse(node, visitor)
end

visitors = {
	VarExpr = terminate,
	NumberExpr = terminate,
	StringExpr = terminate,
	BooleanExpr = terminate,
	NilExpr = terminate,
	DotsExpr = terminate,
	Eof = terminate,

	BinopExpr = function(node, visitor)
		visitor(node.Lhs)
		visitor(node.Rhs)
	end,

	UnopExpr = function(node, visitor)
		visitor(node.Rhs)
	end,

	CallExpr = callExpr,
	TableCallExpr = callExpr,
	StringCallExpr = callExpr,

	IndexExpr = indexExpr,
	MemberExpr = indexExpr,
	Function = function(node, visitor)
		if node.Name and not node.IsLocal then visitor(node.Name) end
		visitor(node.Body)
	end,

	ConstructorExpr = function(node, visitor)
		for _, v in ipairs(node.EntryList) do
			if v.Type == "Key" then visitor(v.Key) end
			visitor(v.Value)
		end
	end,

	Parentheses = function(node, visitor)
		visitor(v.Inner)
	end,

	Statlist = function(node, visitor)
		for _, v in ipairs(node.Body) do
			visitor(v)
		end
	end,

	ReturnStatement = function(node, visitor)
		for _, v in ipairs(node.Arguments) do visitor(v) end
	end,

	AssignmentStatement = function(node, visitor)
		for _, v in ipairs(node.Lhs) do visitor(v) end
		for _, v in ipairs(node.Rhs) do visitor(v) end
	end,

	LocalStatement = function(node, visitor)
		for _, v in ipairs(node.InitList) do visitor(v) end
	end,

	CallStatement = function(node, visitor)
		visitor(v.Expression)
	end,

	IfStatement = function(node, visitor)
		for _, v in ipairs(node.Clauses) do
			if v.Condition then visitor(v.Condition) end
			visitor(v.Body)
		end
	end,

	WhileStatement = function(node, visitor)
		visitor(node.Condition)
		visitor(node.Body)
	end,
	DoStatement = function(node, visitor) visitor(node.Body) end,
	BreakStatement = terminate,
	LabelStatement = terminate,
	GotoStatement = terminate,
	RepeatStatement = function(node, visitor)
		visitor(node.Body)
		visitor(node.Condition)
	end,

	GenericForStatement = function(node, visitor)
		for _, v in ipairs(node.Generators) do visitor(v) end
		visitor(node.Body)
	end,

	NumericForStatement = function(node, visitor)
		visitor(node.Start)
		visitor(node.End)
		if node.Step then visitor(node.Step) end
		visitor(node.Body)
	end
}

return visit
end
preload["howl.lexer.rebuild"] = function(...)
--- Rebuild source code from an AST
-- Does not preserve whitespace
-- @module howl.lexer.rebuild

local constants = require "howl.lexer.constants"
local parse = require "howl.lexer.parse"
local platform = require "howl.platform"

local lowerChars = constants.LowerChars
local upperChars = constants.UpperChars
local digits = constants.Digits
local symbols = constants.Symbols

--- Join two statements together
-- @tparam string left The left statement
-- @tparam string right The right statement
-- @tparam string sep The string used to separate the characters
-- @treturn string The joined strings
local function doJoinStatements(left, right, sep)
	sep = sep or ' '
	local leftEnd, rightStart = left:sub(-1, -1), right:sub(1, 1)
	if upperChars[leftEnd] or lowerChars[leftEnd] or leftEnd == '_' then
		if not (rightStart == '_' or upperChars[rightStart] or lowerChars[rightStart] or digits[rightStart]) then
			--rightStart is left symbol, can join without seperation
			return left .. right
		else
			return left .. sep .. right
		end
	elseif digits[leftEnd] then
		if rightStart == '(' then
			--can join statements directly
			return left .. right
		elseif symbols[rightStart] then
			return left .. right
		else
			return left .. sep .. right
		end
	elseif leftEnd == '' then
		return left .. right
	else
		if rightStart == '(' then
			--don't want to accidentally call last statement, can't join directly
			return left .. sep .. right
		else
			return left .. right
		end
	end
end

--- Returns the minified version of an AST. Operations which are performed:
--  - All comments and whitespace are ignored
--  - All local variables are renamed
-- @tparam Node ast The AST tree
-- @treturn string The minified string
-- @todo Ability to control minification level
-- @todo Convert to a buffer
local function minify(ast)
	local formatStatlist, formatExpr
	local count = 0
	local function joinStatements(left, right, sep)
		if count > 150 then
			count = 0
			return left .. "\n" .. right
		else
			return doJoinStatements(left, right, sep)
		end
	end

	formatExpr = function(expr, precedence)
		local precedence = precedence or 0
		local currentPrecedence = 0
		local skipParens = false
		local out = ""
		if expr.AstType == 'VarExpr' then
			if expr.Variable then
				out = out .. expr.Variable.Name
			else
				out = out .. expr.Name
			end

		elseif expr.AstType == 'NumberExpr' then
			out = out .. expr.Value.Data

		elseif expr.AstType == 'StringExpr' then
			out = out .. expr.Value.Data

		elseif expr.AstType == 'BooleanExpr' then
			out = out .. tostring(expr.Value)

		elseif expr.AstType == 'NilExpr' then
			out = joinStatements(out, "nil")

		elseif expr.AstType == 'BinopExpr' then
			currentPrecedence = expr.OperatorPrecedence
			out = joinStatements(out, formatExpr(expr.Lhs, currentPrecedence))
			out = joinStatements(out, expr.Op)
			out = joinStatements(out, formatExpr(expr.Rhs))
			if expr.Op == '^' or expr.Op == '..' then
				currentPrecedence = currentPrecedence - 1
			end

			if currentPrecedence < precedence then
				skipParens = false
			else
				skipParens = true
			end
		elseif expr.AstType == 'UnopExpr' then
			out = joinStatements(out, expr.Op)
			out = joinStatements(out, formatExpr(expr.Rhs))

		elseif expr.AstType == 'DotsExpr' then
			out = out .. "..."

		elseif expr.AstType == 'CallExpr' then
			out = out .. formatExpr(expr.Base)
			out = out .. "("
			for i = 1, #expr.Arguments do
				out = out .. formatExpr(expr.Arguments[i])
				if i ~= #expr.Arguments then
					out = out .. ","
				end
			end
			out = out .. ")"

		elseif expr.AstType == 'TableCallExpr' then
			out = out .. formatExpr(expr.Base)
			out = out .. formatExpr(expr.Arguments[1])

		elseif expr.AstType == 'StringCallExpr' then
			out = out .. formatExpr(expr.Base)
			out = out .. expr.Arguments[1].Data

		elseif expr.AstType == 'IndexExpr' then
			out = out .. formatExpr(expr.Base) .. "[" .. formatExpr(expr.Index) .. "]"

		elseif expr.AstType == 'MemberExpr' then
			out = out .. formatExpr(expr.Base) .. expr.Indexer .. expr.Ident.Data

		elseif expr.AstType == 'Function' then
			expr.Scope:ObfuscateLocals()
			out = out .. "function("
			if #expr.Arguments > 0 then
				for i = 1, #expr.Arguments do
					out = out .. expr.Arguments[i].Name
					if i ~= #expr.Arguments then
						out = out .. ","
					elseif expr.VarArg then
						out = out .. ",..."
					end
				end
			elseif expr.VarArg then
				out = out .. "..."
			end
			out = out .. ")"
			out = joinStatements(out, formatStatlist(expr.Body))
			out = joinStatements(out, "end")

		elseif expr.AstType == 'ConstructorExpr' then
			out = out .. "{"
			for i = 1, #expr.EntryList do
				local entry = expr.EntryList[i]
				if entry.Type == 'Key' then
					out = out .. "[" .. formatExpr(entry.Key) .. "]=" .. formatExpr(entry.Value)
				elseif entry.Type == 'Value' then
					out = out .. formatExpr(entry.Value)
				elseif entry.Type == 'KeyString' then
					out = out .. entry.Key .. "=" .. formatExpr(entry.Value)
				end
				if i ~= #expr.EntryList then
					out = out .. ","
				end
			end
			out = out .. "}"

		elseif expr.AstType == 'Parentheses' then
			out = out .. "(" .. formatExpr(expr.Inner) .. ")"
		end
		if not skipParens then
			out = string.rep('(', expr.ParenCount or 0) .. out
			out = out .. string.rep(')', expr.ParenCount or 0)
		end
		count = count + #out
		return out
	end

	local formatStatement = function(statement)
		local out = ''
		if statement.AstType == 'AssignmentStatement' then
			for i = 1, #statement.Lhs do
				out = out .. formatExpr(statement.Lhs[i])
				if i ~= #statement.Lhs then
					out = out .. ","
				end
			end
			if #statement.Rhs > 0 then
				out = out .. "="
				for i = 1, #statement.Rhs do
					out = out .. formatExpr(statement.Rhs[i])
					if i ~= #statement.Rhs then
						out = out .. ","
					end
				end
			end

		elseif statement.AstType == 'CallStatement' then
			out = formatExpr(statement.Expression)

		elseif statement.AstType == 'LocalStatement' then
			out = out .. "local "
			for i = 1, #statement.LocalList do
				out = out .. statement.LocalList[i].Name
				if i ~= #statement.LocalList then
					out = out .. ","
				end
			end
			if #statement.InitList > 0 then
				out = out .. "="
				for i = 1, #statement.InitList do
					out = out .. formatExpr(statement.InitList[i])
					if i ~= #statement.InitList then
						out = out .. ","
					end
				end
			end

		elseif statement.AstType == 'IfStatement' then
			out = joinStatements("if", formatExpr(statement.Clauses[1].Condition))
			out = joinStatements(out, "then")
			out = joinStatements(out, formatStatlist(statement.Clauses[1].Body))
			for i = 2, #statement.Clauses do
				local st = statement.Clauses[i]
				if st.Condition then
					out = joinStatements(out, "elseif")
					out = joinStatements(out, formatExpr(st.Condition))
					out = joinStatements(out, "then")
				else
					out = joinStatements(out, "else")
				end
				out = joinStatements(out, formatStatlist(st.Body))
			end
			out = joinStatements(out, "end")

		elseif statement.AstType == 'WhileStatement' then
			out = joinStatements("while", formatExpr(statement.Condition))
			out = joinStatements(out, "do")
			out = joinStatements(out, formatStatlist(statement.Body))
			out = joinStatements(out, "end")

		elseif statement.AstType == 'DoStatement' then
			out = joinStatements(out, "do")
			out = joinStatements(out, formatStatlist(statement.Body))
			out = joinStatements(out, "end")

		elseif statement.AstType == 'ReturnStatement' then
			out = "return"
			for i = 1, #statement.Arguments do
				out = joinStatements(out, formatExpr(statement.Arguments[i]))
				if i ~= #statement.Arguments then
					out = out .. ","
				end
			end

		elseif statement.AstType == 'BreakStatement' then
			out = "break"

		elseif statement.AstType == 'RepeatStatement' then
			out = "repeat"
			out = joinStatements(out, formatStatlist(statement.Body))
			out = joinStatements(out, "until")
			out = joinStatements(out, formatExpr(statement.Condition))

		elseif statement.AstType == 'Function' then
			statement.Scope:ObfuscateLocals()
			if statement.IsLocal then
				out = "local"
			end
			out = joinStatements(out, "function ")
			if statement.IsLocal then
				out = out .. statement.Name.Name
			else
				out = out .. formatExpr(statement.Name)
			end
			out = out .. "("
			if #statement.Arguments > 0 then
				for i = 1, #statement.Arguments do
					out = out .. statement.Arguments[i].Name
					if i ~= #statement.Arguments then
						out = out .. ","
					elseif statement.VarArg then
						out = out .. ",..."
					end
				end
			elseif statement.VarArg then
				out = out .. "..."
			end
			out = out .. ")"
			out = joinStatements(out, formatStatlist(statement.Body))
			out = joinStatements(out, "end")

		elseif statement.AstType == 'GenericForStatement' then
			statement.Scope:ObfuscateLocals()
			out = "for "
			for i = 1, #statement.VariableList do
				out = out .. statement.VariableList[i].Name
				if i ~= #statement.VariableList then
					out = out .. ","
				end
			end
			out = out .. " in"
			for i = 1, #statement.Generators do
				out = joinStatements(out, formatExpr(statement.Generators[i]))
				if i ~= #statement.Generators then
					out = joinStatements(out, ',')
				end
			end
			out = joinStatements(out, "do")
			out = joinStatements(out, formatStatlist(statement.Body))
			out = joinStatements(out, "end")

		elseif statement.AstType == 'NumericForStatement' then
			statement.Scope:ObfuscateLocals()
			out = "for "
			out = out .. statement.Variable.Name .. "="
			out = out .. formatExpr(statement.Start) .. "," .. formatExpr(statement.End)
			if statement.Step then
				out = out .. "," .. formatExpr(statement.Step)
			end
			out = joinStatements(out, "do")
			out = joinStatements(out, formatStatlist(statement.Body))
			out = joinStatements(out, "end")
		elseif statement.AstType == 'LabelStatement' then
			out = "::" .. statement.Label .. "::"
		elseif statement.AstType == 'GotoStatement' then
			out = "goto " .. statement.Label
		elseif statement.AstType == 'Comment' then
			-- ignore
		elseif statement.AstType == 'Eof' then
			-- ignore
		else
			error("Unknown AST Type: " .. statement.AstType)
		end
		count = count + #out
		return out
	end

	formatStatlist = function(statList)
		local out = ''
		statList.Scope:ObfuscateLocals()
		for _, stat in pairs(statList.Body) do
			out = joinStatements(out, formatStatement(stat), ';')
		end
		return out
	end

	return formatStatlist(ast)
end

--- Minify a string
-- @tparam string input The input string
-- @treturn string The minifyied string
local function minifyString(input)
	local lex = parse.LexLua(input)
	platform.refreshYield()

	local tree = parse.ParseLua(lex)
	platform.refreshYield()

	local min = minify(tree)
	platform.refreshYield()
	return min
end

--- Minify a file
-- @tparam string cd Current directory
-- @tparam string inputFile File to read from
-- @tparam string outputFile File to write to (Defaults to inputFile)
local function minifyFile(cd, inputFile, outputFile)
	outputFile = outputFile or inputFile

	local oldContents = platform.fs.read(platform.fs.combine(cd, inputFile))
	local newContents = minifyString(oldContents)

	platform.fs.write(platform.fs.combine(cd, outputFile), newContents)
	return #oldContents, #newContents
end

--- @export
return {
	minify = minify,
	minifyString = minifyString,
	minifyFile = minifyFile,
}
end
preload["howl.lexer.parse"] = function(...)
--- The main lua parser and lexer.
-- LexLua returns a Lua token stream, with tokens that preserve
-- all whitespace formatting information.
-- ParseLua returns an AST, internally relying on LexLua.
-- @module howl.lexer.parse

local Constants = require "howl.lexer.constants"
local Scope = require "howl.lexer.Scope"
local TokenList = require "howl.lexer.TokenList"

local lowerChars = Constants.LowerChars
local upperChars = Constants.UpperChars
local digits = Constants.Digits
local symbols = Constants.Symbols
local hexDigits = Constants.HexDigits
local keywords = Constants.Keywords
local statListCloseKeywords = Constants.StatListCloseKeywords
local unops = Constants.UnOps
local insert, setmeta = table.insert, setmetatable

--- One token
-- @table Token
-- @tparam string Type The token type
-- @param Data Data about the token
-- @tparam string CommentType The type of comment  (Optional)
-- @tparam number Line Line number (Optional)
-- @tparam number Char Character number (Optional)
local Token = {}

--- Creates a string representation of the token
-- @treturn string The resulting string
function Token:Print()
	return "<"..(self.Type .. string.rep(' ', math.max(3, 12-#self.Type))).."  "..(self.Data or '').." >"
end

local tokenMeta = { __index = Token }

--- Create a list of @{Token|tokens} from a Lua source
-- @tparam string src Lua source code
-- @treturn TokenList The list of @{Token|tokens}
local function LexLua(src)
	--token dump
	local tokens = {}

	do -- Main bulk of the work
		local sub = string.sub

		--line / char / pointer tracking
		local pointer = 1
		local line = 1
		local char = 1

		--get / peek functions
		local function get()
			local c = sub(src, pointer,pointer)
			if c == '\n' then
				char = 1
				line = line + 1
			else
				char = char + 1
			end
			pointer = pointer + 1
			return c
		end

		local function peek(n)
			n = n or 0
			return sub(src, pointer+n,pointer+n)
		end
		local function consume(chars)
			local c = peek()
			for i = 1, #chars do
				if c == chars:sub(i,i) then return get() end
			end
		end

		--shared stuff
		local function generateError(err)
			error(">> :"..line..":"..char..": "..err, 0)
		end

		local function tryGetLongString()
			local start = pointer
			if peek() == '[' then
				local equalsCount = 0
				local depth = 1
				while peek(equalsCount+1) == '=' do
					equalsCount = equalsCount + 1
				end
				if peek(equalsCount+1) == '[' then
					--start parsing the string. Strip the starting bit
					for _ = 0, equalsCount+1 do get() end

					--get the contents
					local contentStart = pointer
					while true do
						--check for eof
						if peek() == '' then
							generateError("Expected `]"..string.rep('=', equalsCount).."]` near <eof>.", 3)
						end

						--check for the end
						local foundEnd = true
						if peek() == ']' then
							for i = 1, equalsCount do
								if peek(i) ~= '=' then foundEnd = false end
							end
							if peek(equalsCount+1) ~= ']' then
								foundEnd = false
							end
						else
							if peek() == '[' then
								-- is there an embedded long string?
								local embedded = true
								for i = 1, equalsCount do
									if peek(i) ~= '=' then
										embedded = false
										break
									end
								end
								if peek(equalsCount + 1) == '[' and embedded then
									-- oh look, there was
									depth = depth + 1
									for i = 1, (equalsCount + 2) do
										get()
									end
								end
							end
							foundEnd = false
						end

						if foundEnd then
							depth = depth - 1
							if depth == 0 then
								break
							else
								for i = 1, equalsCount + 2 do
									get()
								end
							end
						else
							get()
						end
					end

					--get the interior string
					local contentString = src:sub(contentStart, pointer-1)

					--found the end. Get rid of the trailing bit
					for i = 0, equalsCount+1 do get() end

					--get the exterior string
					local longString = src:sub(start, pointer-1)

					--return the stuff
					return contentString, longString
				else
					return nil
				end
			else
				return nil
			end
		end

		local function isDigit(c) return c >= '0' and c <= '9' end

		--main token emitting loop
		while true do
			--get leading whitespace. The leading whitespace will include any comments
			--preceding the token. This prevents the parser needing to deal with comments
			--separately.
			local comments, cn
			while true do
				local c = sub(src, pointer, pointer)
				if c == '#' and peek(1) == '!' and line == 1 then
					-- #! shebang for linux scripts
					get()
					get()
					leadingWhite = "#!"
					while peek() ~= '\n' and peek() ~= '' do
						get()
					end
				end
				if c == ' ' or c == '\t' then
					--whitespace
					char = char + 1
					pointer = pointer + 1
				elseif c == '\n' or c == '\r' then
					char = 1
					line = line + 1
					pointer = pointer + 1
				elseif c == '-' and peek(1) == '-' then
					--comment
					get()
					get()
					local startLine, startChar, startPointer = line, char, pointer
					local wholeText, _ = tryGetLongString()
					if not wholeText then
						local next = sub(src, pointer, pointer)
						while next ~= '\n' and next ~= '' do
							get()
							next = sub(src, pointer, pointer)
						end
						wholeText = sub(src, startPointer, pointer - 1)
					end
					if not comments then
						comments = {}
						cn = 0
					end
					cn = cn + 1
					comments[cn] = {
						Data = wholeText,
						Line = startLine,
						Char = startChar,
					}
				else
					break
				end
			end

			--get the initial char
			local thisLine = line
			local thisChar = char
			local c = sub(src, pointer, pointer)

			--symbol to emit
			local toEmit = nil

			--branch on type
			if c == '' then
				--eof
				toEmit = { Type = 'Eof' }

			elseif (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or c == '_' then
				--ident or keyword
				local start = pointer
				repeat
					get()
					c = sub(src, pointer, pointer)
				until not ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or c == '_' or (c >= '0' and c <= '9'))
				local dat = src:sub(start, pointer-1)
				if keywords[dat] then
					toEmit = {Type = 'Keyword', Data = dat}
				else
					toEmit = {Type = 'Ident', Data = dat}
				end

			elseif (c >= '0' and c <= '9') or (c == '.' and digits[peek(1)]) then
				--number const
				local start = pointer
				if c == '0' and peek(1) == 'x' then
					get();get()
					while hexDigits[peek()] do get() end
					if consume('Pp') then
						consume('+-')
						while digits[peek()] do get() end
					end
				else
					while digits[peek()] do get() end
					if consume('.') then
						while digits[peek()] do get() end
					end
					if consume('Ee') then
						consume('+-')

						if not digits[peek()] then generateError("Expected exponent") end
						repeat get() until not digits[peek()]
					end

					local n = peek():lower()
					if (n >= 'a' and n <= 'z') or n == '_' then
						generateError("Invalid number format")
					end
				end
				toEmit = {Type = 'Number', Data = src:sub(start, pointer-1)}

			elseif c == '\'' or c == '\"' then
				local start = pointer
				--string const
				local delim = get()
				local contentStart = pointer
				while true do
					local c = get()
					if c == '\\' then
						get() --get the escape char
					elseif c == delim then
						break
					elseif c == '' then
						generateError("Unfinished string near <eof>")
					end
				end
				local content = src:sub(contentStart, pointer-2)
				local constant = src:sub(start, pointer-1)
				toEmit = {Type = 'String', Data = constant, Constant = content}

			elseif c == '[' then
				local content, wholetext = tryGetLongString()
				if wholetext then
					toEmit = {Type = 'String', Data = wholetext, Constant = content}
				else
					get()
					toEmit = {Type = 'Symbol', Data = '['}
				end

			elseif c == '>' or c == '<' or c == '=' then
				get()
				if consume('=') then
					toEmit = {Type = 'Symbol', Data = c..'='}
				else
					toEmit = {Type = 'Symbol', Data = c}
				end

			elseif c == '~' then
				get()
				if consume('=') then
					toEmit = {Type = 'Symbol', Data = '~='}
				else
					generateError("Unexpected symbol `~` in source.", 2)
				end

			elseif c == '.' then
				get()
				if consume('.') then
					if consume('.') then
						toEmit = {Type = 'Symbol', Data = '...'}
					else
						toEmit = {Type = 'Symbol', Data = '..'}
					end
				else
					toEmit = {Type = 'Symbol', Data = '.'}
				end

			elseif c == ':' then
				get()
				if consume(':') then
					toEmit = {Type = 'Symbol', Data = '::'}
				else
					toEmit = {Type = 'Symbol', Data = ':'}
				end

			elseif symbols[c] then
				get()
				toEmit = {Type = 'Symbol', Data = c}

			else
				local contents, all = tryGetLongString()
				if contents then
					toEmit = {Type = 'String', Data = all, Constant = contents}
				else
					generateError("Unexpected Symbol `"..c.."` in source.", 2)
				end
			end

			--add the emitted symbol, after adding some common data
			toEmit.Line = thisLine
			toEmit.Char = thisChar
			if comments then toEmit.Comments = comments end
			tokens[#tokens+1] = toEmit

			--halt after eof has been emitted
			if toEmit.Type == 'Eof' then break end
		end
	end

	--public interface:
	local tokenList = TokenList(tokens)

	return tokenList
end

--- Create a AST tree from a Lua Source
-- @tparam TokenList tok List of tokens from @{LexLua}
-- @treturn table The AST tree
local function ParseLua(tok, src)
	--- Generate an error
	-- @tparam string msg The error message
	-- @raise The produces error message
	local function GenerateError(msg)
		local err = tok.Peek().Line..":"..tok.Peek().Char..": "..msg.."\n"
		local peek = tok.Peek()
		err = err.. " got " .. peek.Type .. ": " .. peek.Data.. "\n"
		--find the line
		local lineNum = 0
		if type(src) == 'string' then
			for line in src:gmatch("[^\n]*\n?") do
				if line:sub(-1,-1) == '\n' then line = line:sub(1,-2) end
				lineNum = lineNum+1
				if lineNum == tok.Peek().Line then
					err = err..""..line:gsub('\t','    ').."\n"
					for i = 1, tok.Peek().Char do
						local c = line:sub(i,i)
						err = err..' '
					end
					err = err.."^"
					break
				end
			end
		end
		error(err)
	end

	local ParseExpr,
	      ParseStatementList,
	      ParseSimpleExpr,
	      ParsePrimaryExpr,
	      ParseSuffixedExpr

	--- Parse the function definition and its arguments
	-- @tparam Scope.Scope scope The current scope
	-- @tparam table tokenList A table to fill with tokens
	-- @treturn Node A function Node
	local function ParseFunctionArgsAndBody(scope, tokenList)
		local funcScope = Scope(scope)
		if not tok.ConsumeSymbol('(', tokenList) then
			GenerateError("`(` expected.")
		end

		--arg list
		local argList = {}
		local isVarArg = false
		while not tok.ConsumeSymbol(')', tokenList) do
			if tok.Is('Ident') then
				local arg = funcScope:CreateLocal(tok.Get(tokenList).Data)
				argList[#argList+1] = arg
				if not tok.ConsumeSymbol(',', tokenList) then
					if tok.ConsumeSymbol(')', tokenList) then
						break
					else
						GenerateError("`)` expected.")
					end
				end
			elseif tok.ConsumeSymbol('...', tokenList) then
				isVarArg = true
				if not tok.ConsumeSymbol(')', tokenList) then
					GenerateError("`...` must be the last argument of a function.")
				end
				break
			else
				GenerateError("Argument name or `...` expected")
			end
		end

		--body
		local body = ParseStatementList(funcScope)

		--end
		if not tok.ConsumeKeyword('end', tokenList) then
			GenerateError("`end` expected after function body")
		end

		return {
			AstType   = 'Function',
			Scope     = funcScope,
			Arguments = argList,
			Body      = body,
			VarArg    = isVarArg,
			Tokens    = tokenList,
		}
	end

	--- Parse a simple expression
	-- @tparam Scope.Scope scope The current scope
	-- @treturn Node the resulting node
	function ParsePrimaryExpr(scope)
		local tokenList = {}

		if tok.ConsumeSymbol('(', tokenList) then
			local ex = ParseExpr(scope)
			if not tok.ConsumeSymbol(')', tokenList) then
				GenerateError("`)` Expected.")
			end

			return {
				AstType = 'Parentheses',
				Inner   = ex,
				Tokens  = tokenList,
			}

		elseif tok.Is('Ident') then
			local id = tok.Get(tokenList)
			local var = scope:GetLocal(id.Data)
			if not var then
				var = scope:GetGlobal(id.Data)
				if not var then
					var = scope:CreateGlobal(id.Data)
				else
					var.References = var.References + 1
				end
			else
				var.References = var.References + 1
			end

			return {
				AstType  = 'VarExpr',
				Name     = id.Data,
				Variable = var,
				Tokens   = tokenList,
			}
		else
			GenerateError("primary expression expected")
		end
	end

	--- Parse some table related expressions
	-- @tparam Scope.Scope scope The current scope
	-- @tparam boolean onlyDotColon Only allow '.' or ':' nodes
	-- @treturn Node The resulting node
	function ParseSuffixedExpr(scope, onlyDotColon)
		--base primary expression
		local prim = ParsePrimaryExpr(scope)

		while true do
			local tokenList = {}

			if tok.IsSymbol('.') or tok.IsSymbol(':') then
				local symb = tok.Get(tokenList).Data
				if not tok.Is('Ident') then
					GenerateError("<Ident> expected.")
				end
				local id = tok.Get(tokenList)

				prim = {
					AstType  = 'MemberExpr',
					Base     = prim,
					Indexer  = symb,
					Ident    = id,
					Tokens   = tokenList,
				}

			elseif not onlyDotColon and tok.ConsumeSymbol('[', tokenList) then
				local ex = ParseExpr(scope)
				if not tok.ConsumeSymbol(']', tokenList) then
					GenerateError("`]` expected.")
				end

				prim = {
					AstType  = 'IndexExpr',
					Base     = prim,
					Index    = ex,
					Tokens   = tokenList,
				}

			elseif not onlyDotColon and tok.ConsumeSymbol('(', tokenList) then
				local args = {}
				while not tok.ConsumeSymbol(')', tokenList) do
					args[#args+1] = ParseExpr(scope)
					if not tok.ConsumeSymbol(',', tokenList) then
						if tok.ConsumeSymbol(')', tokenList) then
							break
						else
							GenerateError("`)` Expected.")
						end
					end
				end

				prim = {
					AstType   = 'CallExpr',
					Base      = prim,
					Arguments = args,
					Tokens    = tokenList,
				}

			elseif not onlyDotColon and tok.Is('String') then
				--string call
				prim = {
					AstType    = 'StringCallExpr',
					Base       = prim,
					Arguments  = { tok.Get(tokenList) },
					Tokens     = tokenList,
				}

			elseif not onlyDotColon and tok.IsSymbol('{') then
				--table call
				local ex = ParseSimpleExpr(scope)
				-- FIX: ParseExpr(scope) parses the table AND and any following binary expressions.
				-- We just want the table

				prim = {
					AstType   = 'TableCallExpr',
					Base      = prim,
					Arguments = { ex },
					Tokens    = tokenList,
				}

			else
				break
			end
		end
		return prim
	end

	--- Parse a simple expression (strings, numbers, booleans, varargs)
	-- @tparam Scope.Scope scope The current scope
	-- @treturn Node The resulting node
	function ParseSimpleExpr(scope)
		local tokenList = {}

		local next = tok.Peek()
		local type = next.Type
		if type == 'Number' then
			return {
				AstType = 'NumberExpr',
				Value   = tok.Get(tokenList),
				Tokens  = tokenList,
			}
		elseif type == 'String' then
			return {
				AstType = 'StringExpr',
				Value   = tok.Get(tokenList),
				Tokens  = tokenList,
			}
		elseif type == 'Keyword' then
			local data = next.Data
			if data == 'nil' then
				tok.Get(tokenList)
				return {
					AstType = 'NilExpr',
					Tokens  = tokenList,
				}
			elseif data == 'false' or data == 'true' then
				return {
					AstType = 'BooleanExpr',
					Value   = (tok.Get(tokenList).Data == 'true'),
					Tokens  = tokenList,
				}
			elseif data == 'function' then
				tok.Get(tokenList)
				local func = ParseFunctionArgsAndBody(scope, tokenList)

				func.IsLocal = true
				return func
			end
		elseif type == 'Symbol' then
			local data = next.Data
			if data == '...' then
				tok.Get(tokenList)
				return {
					AstType  = 'DotsExpr',
					Tokens   = tokenList,
				}
			elseif data == '{' then
				tok.Get(tokenList)

				local entryList = {}
				local v = {
					AstType = 'ConstructorExpr',
					EntryList = entryList,
					Tokens  = tokenList,
				}

				while true do
					if tok.IsSymbol('[', tokenList) then
						--key
						tok.Get(tokenList)
						local key = ParseExpr(scope)
						if not tok.ConsumeSymbol(']', tokenList) then
							GenerateError("`]` Expected")
						end
						if not tok.ConsumeSymbol('=', tokenList) then
							GenerateError("`=` Expected")
						end
						local value = ParseExpr(scope)
						entryList[#entryList+1] = {
							Type  = 'Key',
							Key   = key,
							Value = value,
						}

					elseif tok.Is('Ident') then
						--value or key
						local lookahead = tok.Peek(1)
						if lookahead.Type == 'Symbol' and lookahead.Data == '=' then
							--we are a key
							local key = tok.Get(tokenList)
							if not tok.ConsumeSymbol('=', tokenList) then
								GenerateError("`=` Expected")
							end
							local value = ParseExpr(scope)
							entryList[#entryList+1] = {
								Type  = 'KeyString',
								Key   = key.Data,
								Value = value,
							}

						else
							--we are a value
							local value = ParseExpr(scope)
							entryList[#entryList+1] = {
								Type = 'Value',
								Value = value,
							}

						end
					elseif tok.ConsumeSymbol('}', tokenList) then
						break

					else
						--value
						local value = ParseExpr(scope)
						entryList[#entryList+1] = {
							Type = 'Value',
							Value = value,
						}
					end

					if tok.ConsumeSymbol(';', tokenList) or tok.ConsumeSymbol(',', tokenList) then
						--all is good
					elseif tok.ConsumeSymbol('}', tokenList) then
						break
					else
						GenerateError("`}` or table entry Expected")
					end
				end
				return v
			end
		end

		return ParseSuffixedExpr(scope)
	end

	local unopprio = 8
	local priority = {
		['+'] = {6,6},
		['-'] = {6,6},
		['%'] = {7,7},
		['/'] = {7,7},
		['*'] = {7,7},
		['^'] = {10,9},
		['..'] = {5,4},
		['=='] = {3,3},
		['<'] = {3,3},
		['<='] = {3,3},
		['~='] = {3,3},
		['>'] = {3,3},
		['>='] = {3,3},
		['and'] = {2,2},
		['or'] = {1,1},
	}

	--- Parse an expression
	-- @tparam Skcope.Scope scope The current scope
	-- @tparam int level Current level (Optional)
	-- @treturn Node The resulting node
	function ParseExpr(scope, level)
		level = level or 0
		--base item, possibly with unop prefix
		local exp
		if unops[tok.Peek().Data] then
			local tokenList = {}
			local op = tok.Get(tokenList).Data
			exp = ParseExpr(scope, unopprio)

			local nodeEx = {
				AstType = 'UnopExpr',
				Rhs     = exp,
				Op      = op,
				OperatorPrecedence = unopprio,
				Tokens  = tokenList,
			}

			exp = nodeEx
		else
			exp = ParseSimpleExpr(scope)
		end

		--next items in chain
		while true do
			local prio = priority[tok.Peek().Data]
			if prio and prio[1] > level then
				local tokenList = {}
				local op = tok.Get(tokenList).Data
				local rhs = ParseExpr(scope, prio[2])

				local nodeEx = {
					AstType = 'BinopExpr',
					Lhs     = exp,
					Op      = op,
					OperatorPrecedence = prio[1],
					Rhs     = rhs,
					Tokens  = tokenList,
				}

				exp = nodeEx
			else
				break
			end
		end

		return exp
	end

	--- Parse a statement (if, for, while, etc...)
	-- @tparam Scope.Scope scope The current scope
	-- @treturn Node The resulting node
	local function ParseStatement(scope)
		local stat = nil
		local tokenList = {}

		local next = tok.Peek()
		if next.Type == "Keyword" then
			local type = next.Data
			if type == 'if' then
				tok.Get(tokenList)

				--setup
				local clauses = {}
				local nodeIfStat = {
					AstType = 'IfStatement',
					Clauses = clauses,
				}
				--clauses
				repeat
					local nodeCond = ParseExpr(scope)

					if not tok.ConsumeKeyword('then', tokenList) then
						GenerateError("`then` expected.")
					end
					local nodeBody = ParseStatementList(scope)
					clauses[#clauses+1] = {
						Condition = nodeCond,
						Body = nodeBody,
					}
				until not tok.ConsumeKeyword('elseif', tokenList)

				--else clause
				if tok.ConsumeKeyword('else', tokenList) then
					local nodeBody = ParseStatementList(scope)
					clauses[#clauses+1] = {
						Body = nodeBody,
					}
				end

				--end
				if not tok.ConsumeKeyword('end', tokenList) then
					GenerateError("`end` expected.")
				end

				nodeIfStat.Tokens = tokenList
				stat = nodeIfStat
			elseif type == 'while' then
				tok.Get(tokenList)

				--condition
				local nodeCond = ParseExpr(scope)

				--do
				if not tok.ConsumeKeyword('do', tokenList) then
					return GenerateError("`do` expected.")
				end

				--body
				local nodeBody = ParseStatementList(scope)

				--end
				if not tok.ConsumeKeyword('end', tokenList) then
					GenerateError("`end` expected.")
				end

				--return
				stat = {
					AstType = 'WhileStatement',
					Condition = nodeCond,
					Body      = nodeBody,
					Tokens    = tokenList,
				}
			elseif type == 'do' then
				tok.Get(tokenList)

				--do block
				local nodeBlock = ParseStatementList(scope)
				if not tok.ConsumeKeyword('end', tokenList) then
					GenerateError("`end` expected.")
				end

				stat = {
					AstType = 'DoStatement',
					Body    = nodeBlock,
					Tokens  = tokenList,
				}
			elseif type == 'for' then
				tok.Get(tokenList)

				--for block
				if not tok.Is('Ident') then
					GenerateError("<ident> expected.")
				end
				local baseVarName = tok.Get(tokenList)
				if tok.ConsumeSymbol('=', tokenList) then
					--numeric for
					local forScope = Scope(scope)
					local forVar = forScope:CreateLocal(baseVarName.Data)

					local startEx = ParseExpr(scope)
					if not tok.ConsumeSymbol(',', tokenList) then
						GenerateError("`,` Expected")
					end
					local endEx = ParseExpr(scope)
					local stepEx
					if tok.ConsumeSymbol(',', tokenList) then
						stepEx = ParseExpr(scope)
					end
					if not tok.ConsumeKeyword('do', tokenList) then
						GenerateError("`do` expected")
					end

					local body = ParseStatementList(forScope)
					if not tok.ConsumeKeyword('end', tokenList) then
						GenerateError("`end` expected")
					end

					stat = {
						AstType  = 'NumericForStatement',
						Scope    = forScope,
						Variable = forVar,
						Start    = startEx,
						End      = endEx,
						Step     = stepEx,
						Body     = body,
						Tokens   = tokenList,
					}
				else
					--generic for
					local forScope = Scope(scope)

					local varList = { forScope:CreateLocal(baseVarName.Data) }
					while tok.ConsumeSymbol(',', tokenList) do
						if not tok.Is('Ident') then
							GenerateError("for variable expected.")
						end
						varList[#varList+1] = forScope:CreateLocal(tok.Get(tokenList).Data)
					end
					if not tok.ConsumeKeyword('in', tokenList) then
						GenerateError("`in` expected.")
					end
					local generators = {ParseExpr(scope)}
					while tok.ConsumeSymbol(',', tokenList) do
						generators[#generators+1] = ParseExpr(scope)
					end

					if not tok.ConsumeKeyword('do', tokenList) then
						GenerateError("`do` expected.")
					end

					local body = ParseStatementList(forScope)
					if not tok.ConsumeKeyword('end', tokenList) then
						GenerateError("`end` expected.")
					end

					stat = {
						AstType      = 'GenericForStatement',
						Scope        = forScope,
						VariableList = varList,
						Generators   = generators,
						Body         = body,
						Tokens       = tokenList,
					}
				end
			elseif type == 'repeat' then
				tok.Get(tokenList)

				local body = ParseStatementList(scope)

				if not tok.ConsumeKeyword('until', tokenList) then
					GenerateError("`until` expected.")
				end

				local cond = ParseExpr(body.Scope)

				stat = {
					AstType   = 'RepeatStatement',
					Condition = cond,
					Body      = body,
					Tokens    = tokenList,
				}
			elseif type == 'function' then
				tok.Get(tokenList)

				if not tok.Is('Ident') then
					GenerateError("Function name expected")
				end
				local name = ParseSuffixedExpr(scope, true) --true => only dots and colons

				local func = ParseFunctionArgsAndBody(scope, tokenList)

				func.IsLocal = false
				func.Name    = name
				stat = func
			elseif type == 'local' then
				tok.Get(tokenList)

				if tok.Is('Ident') then
					local varList = { tok.Get(tokenList).Data }
					while tok.ConsumeSymbol(',', tokenList) do
						if not tok.Is('Ident') then
							GenerateError("local var name expected")
						end
						varList[#varList+1] = tok.Get(tokenList).Data
					end

					local initList = {}
					if tok.ConsumeSymbol('=', tokenList) then
						repeat
							initList[#initList+1] = ParseExpr(scope)
						until not tok.ConsumeSymbol(',', tokenList)
					end

					--now patch var list
					--we can't do this before getting the init list, because the init list does not
					--have the locals themselves in scope.
					for i, v in pairs(varList) do
						varList[i] = scope:CreateLocal(v)
					end

					stat = {
						AstType   = 'LocalStatement',
						LocalList = varList,
						InitList  = initList,
						Tokens    = tokenList,
					}

				elseif tok.ConsumeKeyword('function', tokenList) then
					if not tok.Is('Ident') then
						GenerateError("Function name expected")
					end
					local name = tok.Get(tokenList).Data
					local localVar = scope:CreateLocal(name)

					local func = ParseFunctionArgsAndBody(scope, tokenList)

					func.Name    = localVar
					func.IsLocal = true
					stat = func

				else
					GenerateError("local var or function def expected")
				end
			elseif type == '::' then
				tok.Get(tokenList)

				if not tok.Is('Ident') then
					GenerateError('Label name expected')
				end
				local label = tok.Get(tokenList).Data
				if not tok.ConsumeSymbol('::', tokenList) then
					GenerateError("`::` expected")
				end
				stat = {
					AstType = 'LabelStatement',
					Label   = label,
					Tokens  = tokenList,
				}
			elseif type == 'return' then
				tok.Get(tokenList)

				local exList = {}
				if not tok.IsKeyword('end') then
					-- Use PCall as this may produce an error
					local st, firstEx = pcall(function() return ParseExpr(scope) end)
					if st then
						exList[1] = firstEx
						while tok.ConsumeSymbol(',', tokenList) do
							exList[#exList+1] = ParseExpr(scope)
						end
					end
				end
				stat = {
					AstType   = 'ReturnStatement',
					Arguments = exList,
					Tokens    = tokenList,
				}
			elseif type == 'break' then
				tok.Get(tokenList)

				stat = {
					AstType = 'BreakStatement',
					Tokens  = tokenList,
				}
			elseif type == 'goto' then
				tok.Get(tokenList)

				if not tok.Is('Ident') then
					GenerateError("Label expected")
				end
				local label = tok.Get(tokenList).Data
				stat = {
					AstType = 'GotoStatement',
					Label   = label,
					Tokens  = tokenList,
				}
			end
		end

		if not stat then
			--statementParseExpr
			local suffixed = ParseSuffixedExpr(scope)

			--assignment or call?
			if tok.IsSymbol(',') or tok.IsSymbol('=') then
				--check that it was not parenthesized, making it not an lvalue
				if (suffixed.ParenCount or 0) > 0 then
					GenerateError("Can not assign to parenthesized expression, is not an lvalue")
				end

				--more processing needed
				local lhs = { suffixed }
				while tok.ConsumeSymbol(',', tokenList) do
					lhs[#lhs+1] = ParseSuffixedExpr(scope)
				end

				--equals
				if not tok.ConsumeSymbol('=', tokenList) then
					GenerateError("`=` Expected.")
				end

				--rhs
				local rhs = {ParseExpr(scope)}
				while tok.ConsumeSymbol(',', tokenList) do
					rhs[#rhs+1] = ParseExpr(scope)
				end

				--done
				stat = {
					AstType = 'AssignmentStatement',
					Lhs     = lhs,
					Rhs     = rhs,
					Tokens  = tokenList,
				}

			elseif suffixed.AstType == 'CallExpr' or
				   suffixed.AstType == 'TableCallExpr' or
				   suffixed.AstType == 'StringCallExpr'
			then
				--it's a call statement
				stat = {
					AstType    = 'CallStatement',
					Expression = suffixed,
					Tokens     = tokenList,
				}
			else
				GenerateError("Assignment Statement Expected")
			end
		end

		if tok.IsSymbol(';') then
			stat.Semicolon = tok.Get( stat.Tokens )
		end
		return stat
	end

	--- Parse a a list of statements
	-- @tparam Scope.Scope scope The current scope
	-- @treturn Node The resulting node
	function ParseStatementList(scope)
		local body = {}
		local nodeStatlist   = {
			Scope   = Scope(scope),
			AstType = 'Statlist',
			Body    = body,
			Tokens  = {},
		}

		while not statListCloseKeywords[tok.Peek().Data] and not tok.IsEof() do
			local nodeStatement = ParseStatement(nodeStatlist.Scope)
			--stats[#stats+1] = nodeStatement
			body[#body + 1] = nodeStatement
		end

		if tok.IsEof() then
			local nodeEof = {}
			nodeEof.AstType = 'Eof'
			nodeEof.Tokens  = { tok.Get() }
			body[#body + 1] = nodeEof
		end

		--nodeStatlist.Body = stats
		return nodeStatlist
	end

	return ParseStatementList(Scope())
end

--- @export
return { LexLua = LexLua, ParseLua = ParseLua }
end
preload["howl.lexer.constants"] = function(...)
--- Lexer constants
-- @module howl.lexer.constants

local function createLookup(tbl)
	for k,v in ipairs(tbl) do tbl[v] = k end
	return tbl
end

return {
	--- List of white chars
	WhiteChars = createLookup { ' ', '\n', '\t', '\r' },

	--- Lookup of escape characters
	EscapeLookup = { ['\r'] = '\\r', ['\n'] = '\\n', ['\t'] = '\\t', ['"'] = '\\"', ["'"] = "\\'" },

	--- Lookup of lower case characters
	LowerChars = createLookup {
		'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
		'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
	},

	--- Lookup of upper case characters
	UpperChars = createLookup {
		'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
		'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
	},

	--- Lookup of digits
	Digits = createLookup { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' },

	--- Lookup of hex digits
	HexDigits = createLookup {
		'0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
		'A', 'a', 'B', 'b', 'C', 'c', 'D', 'd', 'E', 'e', 'F', 'f'
	},

	--- Lookup of valid symbols
	Symbols = createLookup { '+', '-', '*', '/', '^', '%', ',', '{', '}', '[', ']', '(', ')', ';', '#' },

	--- Lookup of valid keywords
	Keywords = createLookup {
		'and', 'break', 'do', 'else', 'elseif',
		'end', 'false', 'for', 'function', 'goto', 'if',
		'in', 'local', 'nil', 'not', 'or', 'repeat',
		'return', 'then', 'true', 'until', 'while',
	},

	--- Keywords that end a block
	StatListCloseKeywords = createLookup { 'end', 'else', 'elseif', 'until' },

	--- Unary operators
	UnOps = createLookup { '-', 'not', '#' },
}
end
preload["howl.lexer.TokenList"] = function(...)
--- Provides utilities for reading tokens from a 'stream'
-- @module howl.lexer.TokenList

local min = math.min
local insert = table.insert

return function(tokens)
	local n = #tokens
	local pointer = 1

	--- Get this element in the token list
	-- @tparam int offset The offset in the token list
	local function Peek(offset)
		return tokens[min(n, pointer + (offset or 0))]
	end

	--- Get the next token in the list
	-- @tparam table tokenList Add the token onto this table
	-- @treturn Token The token
	local function Get(tokenList)
		local token = tokens[pointer]
		pointer = min(pointer + 1, n)
		if tokenList then
			insert(tokenList, token)
		end
		return token
	end

	--- Check if the next token is of a type
	-- @tparam string type The type to compare it with
	-- @treturn bool If the type matches
	local function Is(type)
		return Peek().Type == type
	end

	--- Check if the next token is a symbol and return it
	-- @tparam string symbol Symbol to check (Optional)
	-- @tparam table tokenList Add the token onto this table
	-- @treturn [ 0 ] ?|token If symbol is not specified, return the token
	-- @treturn [ 1 ] boolean If symbol is specified, return true if it matches
	local function ConsumeSymbol(symbol, tokenList)
		local token = Peek()
		if token.Type == 'Symbol' then
			if symbol then
				if token.Data == symbol then
					if tokenList then insert(tokenList, token) end
					pointer = pointer + 1
					return true
				else
					return nil
				end
			else
				if tokenList then insert(tokenList, token) end
				pointer = pointer + 1
				return token
			end
		else
			return nil
		end
	end

	--- Check if the next token is a keyword and return it
	-- @tparam string kw Keyword to check (Optional)
	-- @tparam table tokenList Add the token onto this table
	-- @treturn [ 0 ] ?|token If kw is not specified, return the token
	-- @treturn [ 1 ] boolean If kw is specified, return true if it matches
	local function ConsumeKeyword(kw, tokenList)
		local token = Peek()
		if token.Type == 'Keyword' and token.Data == kw then
			if tokenList then insert(tokenList, token) end
			pointer = pointer + 1
			return true
		else
			return nil
		end
	end

	--- Check if the next token matches is a keyword
	-- @tparam string kw The particular keyword
	-- @treturn boolean If it matches or not
	local function IsKeyword(kw)
		local token = Peek()
		return token.Type == 'Keyword' and token.Data == kw
	end

	--- Check if the next token matches is a symbol
	-- @tparam string symbol The particular symbol
	-- @treturn boolean If it matches or not
	local function IsSymbol(symbol)
		local token = Peek()
		return token.Type == 'Symbol' and token.Data == symbol
	end

	--- Check if the next token is an end of file
	-- @treturn boolean If the next token is an end of file
	local function IsEof()
		return Peek().Type == 'Eof'
	end

	--- Produce a string off all tokens
	-- @tparam boolean includeLeading Include the leading whitespace
	-- @treturn string The resulting string
	local function Print(includeLeading)
		includeLeading = (includeLeading == nil and true or includeLeading)

		local out = ""
		for _, token in ipairs(tokens) do
			if includeLeading then
				for _, whitespace in ipairs(token.LeadingWhite) do
					out = out .. whitespace:Print() .. "\n"
				end
			end
			out = out .. token:Print() .. "\n"
		end

		return out
	end

	return {
		Peek = Peek,
		Get = Get,
		Is = Is,
		ConsumeSymbol = ConsumeSymbol,
		ConsumeKeyword = ConsumeKeyword,
		IsKeyword = IsKeyword,
		IsSymbol = IsSymbol,
		IsEof = IsEof,
		Print = Print,
		Tokens = tokens,
	}
end
end
preload["howl.lexer.Scope"] = function(...)
--- Holds variables for one scope
-- This implementation is inefficient. Instead of using hashes,
-- a linear search is used instead to look up variables
-- @module howl.lexer.Scope

local keywords = require "howl.lexer.constants".Keywords

--- Holds the data for one variable
-- @table Variable
-- @tfield Scope Scope The parent scope
-- @tfield string Name The name of the variable
-- @tfield boolean IsGlobal Is the variable global
-- @tfield boolean CanRename If the variable can be renamed
-- @tfield int References Number of references

--- Holds variables for one scope
-- @type Scope
-- @tfield ?|Scope Parent The parent scope
-- @tfield table Locals A list of locals variables
-- @tfield table Globals A list of global variables
-- @tfield table Children A list of children @{Scope|scopes}

local Scope = {}

--- Add a local to this scope
-- @tparam Variable variable The local object
function Scope:AddLocal(name, variable)
	table.insert(self.Locals, variable)
	self.LocalMap[name] = variable
end

--- Create a @{Variable} and add it to the scope
-- @tparam string name The name of the local
-- @treturn Variable The created local
function Scope:CreateLocal(name)
	local variable = self:GetLocal(name)
	if variable then return variable end

	variable = {
		Scope = self,
		Name = name,
		IsGlobal = false,
		CanRename = true,
		References = 1,
	}

	self:AddLocal(name, variable)
	return variable
end

--- Get a local variable
-- @tparam string name The name of the local
-- @treturn ?|Variable The variable
function Scope:GetLocal(name)
	repeat
		local var = self.LocalMap[name]
		if var then return var end


		self = self.Parent
	until not self
end

--- Find an local variable by its old name
-- @tparam string name The old name of the local
-- @treturn ?|Variable The local variable
function Scope:GetOldLocal(name)
	if self.oldLocalNamesMap[name] then
		return self.oldLocalNamesMap[name]
	end
	return self:GetLocal(name)
end

--- Rename a local variable
-- @tparam string|Variable oldName The old variable name
-- @tparam string newName The new variable name
function Scope:RenameLocal(oldName, newName)
	oldName = type(oldName) == 'string' and oldName or oldName.Name

	repeat
		local var = self.LocalMap[oldName]
		if var then
			var.Name = newName
			self.oldLocalNamesMap[oldName] = var
			self.LocalMap[oldName] = nil
			self.LocalMap[newName] = var
			break
		end

		self = self.Parent
	until not self
end

--- Add a global to this scope
-- @tparam Variable name The name of the global
function Scope:AddGlobal(name, variable)
	table.insert(self.Globals, variable)
	self.GlobalMap[name] = variable
end

--- Create a @{Variable} and add it to the scope
-- @tparam string name The name of the global
-- @treturn Variable The created global
function Scope:CreateGlobal(name)
	local variable = self:GetGlobal(name)
	if variable then return variable end

	variable = {
		Scope = self,
		Name = name,
		IsGlobal = true,
		CanRename = true,
		References = 1,
	}

	self:AddGlobal(name, variable)
	return variable
end

--- Get a global variable
-- @tparam string name The name of the global
-- @treturn ?|Variable The variable
function Scope:GetGlobal(name)
	repeat
		local var = self.GlobalMap[name]
		if var then return var end


		self = self.Parent
	until not self
end

--- Get a variable by name
-- @tparam string name The name of the variable
-- @treturn ?|Variable The found variable
-- @fixme This is a very inefficient implementation, as with @{Scope:GetLocal} and @{Scope:GetGlocal}
function Scope:GetVariable(name)
	return self:GetLocal(name) or self:GetGlobal(name)
end

--- Get all variables in the scope
-- @treturn table A list of @{Variable|variables}
function Scope:GetAllVariables()
	return self:getVars(true, self:getVars(true))
end

--- Get all variables
-- @tparam boolean top If this values is the 'top' of the function stack
-- @tparam table ret Table to fill with return values (optional)
-- @treturn table The variables
-- @local
function Scope:getVars(top, ret)
	local ret = ret or {}
	if top then
		for _, v in pairs(self.Children) do
			v:getVars(true, ret)
		end
	else
		for _, v in pairs(self.Locals) do
			table.insert(ret, v)
		end
		for _, v in pairs(self.Globals) do
			table.insert(ret, v)
		end
		if self.Parent then
			self.Parent:getVars(false, ret)
		end
	end
	return ret
end

--- Rename all locals to smaller values
-- @tparam string validNameChars All characters that can be used to make a variable name
-- @fixme Some of the string generation happens a lot, this could be looked at
function Scope:ObfuscateLocals(validNameChars)
	-- Use values sorted for letter frequency instead
	local startChars = validNameChars or "etaoinshrdlucmfwypvbgkqjxz_ETAOINSHRDLUCMFWYPVBGKQJXZ"
	local otherChars = validNameChars or "etaoinshrdlucmfwypvbgkqjxz_0123456789ETAOINSHRDLUCMFWYPVBGKQJXZ"

	local startCharsLength, otherCharsLength = #startChars, #otherChars
	local index = 0
	local floor = math.floor
	for _, var in pairs(self.Locals) do
		local name

		repeat
			if index < startCharsLength then
				index = index + 1
				name = startChars:sub(index, index)
			else
				if index < startCharsLength then
					index = index + 1
					name = startChars:sub(index, index)
				else
					local varIndex = floor(index / startCharsLength)
					local offset = index % startCharsLength
					name = startChars:sub(offset, offset)

					while varIndex > 0 do
						offset = varIndex % otherCharsLength
						name = otherChars:sub(offset, offset) .. name
						varIndex = floor(varIndex / otherCharsLength)
					end
					index = index + 1
				end
			end
		until not (keywords[name] or self:GetVariable(name))
		self:RenameLocal(var.Name, name)
	end
end

--- Converts the scope to a string
-- No, it actually just returns '&lt;scope&gt;'
-- @treturn string '&lt;scope&gt;'
function Scope:ToString()
	return '<Scope>'
end

--- Create a new scope
-- @tparam Scope parent The parent scope
-- @treturn Scope The created scope
local function NewScope(parent)
	local scope = setmetatable({
		Parent = parent,
		Locals = {},
		LocalMap = {},
		Globals = {},
		GlobalMap = {},
		oldLocalNamesMap = {},
		Children = {},
	}, { __index = Scope })

	if parent then
		table.insert(parent.Children, scope)
	end

	return scope
end

return NewScope
end
preload["howl.files.matcher"] = function(...)
--- Used to create matchers for particular patterns
-- @module howl.files.matcher

local utils = require "howl.lib.utils"

-- Matches with * and ?  removed
local basicMatches = {
	["^"] = "%^", ["$"] = "%$", ["("] = "%(", [")"] = "%)",
	["%"] = "%%", ["."] = "%.", ["["] = "%[", ["]"] = "%]",
	["+"] = "%+", ["-"] = "%-", ["\0"] = "%z",
}

local wildMatches = {
	-- ["*"] = "([^\\]+)",
	-- ["?"] = "([^\\])",
	["*"] = "(.*)"
}
for k,v in pairs(basicMatches) do wildMatches[k] = v end

--- A resulting pattern
-- @table Pattern
-- @tfield string tag `pattern` or `normal`
-- @tfield (Pattern, string)->boolean match Predicate to check if this is a valid item

local function patternAction(self, text) return text:match(self.text) end
local function textAction(self, text)
	return self.text == "" or self.text == text or text:sub(1, #self.text + 1) == self.text .. "/"
end
local function funcAction(self, text) return self.func(text) end

--- Create a matcher
-- @tparam string|function pattern Pattern to check against
-- @treturn Pattern
local function createMatcher(pattern)
	local t = type(pattern)
	if t == "string" then
		local remainder = utils.startsWith(pattern, "pattern:") or utils.startsWith(pattern, "ptrn:")
		if remainder then
			return { tag = "pattern", text = remainder, match = patternAction }
		end

		if pattern:find("%*") then
			local pattern = "^" .. pattern:gsub(".", wildMatches) .. "$"
			return { tag = "pattern", text = pattern, match = patternAction }
		end

		return { tag = "text", text = pattern, match = textAction}
	elseif t == "function" or (t == "table" and (getmetatable(pattern) or {}).__call) then
		return { tag = "function", func = pattern, match = funcAction }
	else
		error("Expected string or function")
	end
end


return {
	createMatcher = createMatcher,
}
end
preload["howl.files.Source"] = function(...)
--- A source location for a series of files.
-- This holds a list of inclusion and exclusion filters.
-- @classmod howl.files.Source

local assert = require "howl.lib.assert"
local class = require "howl.class"
local matcher = require "howl.files.matcher"
local mixin = require "howl.class.mixin"
local fs = require "howl.platform".fs

local insert = table.insert

local Source = class("howl.files.Source")
	:include(mixin.configurable)
	:include(mixin.filterable)

local function extractPattern(item)
	local t = type(item)
	if t == "function" or t == "string" then
		return matcher.createMatcher(item)
	elseif t == "table" and item.tag and item.predicate then
		return item
	elseif t == "table" and item.isInstanceOf and item:isInstanceOf(Source) then
		return matcher.createMatcher(function(text) return item:matches(text) end)
	else
		return nil
	end
end

local function append(destination, source, func, i)
	local extracted = extractPattern(source)
	local t = type(source)
	if extracted then
		insert(destination, extracted)
	elseif t == "table" then
		for i, item in ipairs(source) do
			local extracted = extractPattern(item)
			if extracted then
				insert(destination, extracted)
			else
				error("bad item #" .. i .. " for " .. func .. " (expected pattern, got " .. type(item) .. ")")
			end
		end
	else
		error("bad argument #" .. i .. " for " .. func .. " (expected pattern, got " .. t .. ")")
	end
end

local function matches(items, text)
	for _, pattern in pairs(items) do
		if pattern:match(text) then
			return true
		end
	end

	return false
end

function Source:initialize(allowEmpty, parent)
	if allowEmpty == nil then allowEmpty = true end

	self.parent = parent
	self.children = {}

	self.includes = {}
	self.excludes = {}
	self.allowEmpty = allowEmpty
end

function Source:from(path, configure)
	assert.argType(path, "string", "from", 1)
	path = fs.normalise(path)

	local source = self.children[path]
	if not source then
		source = self.class(true)
		self.children[path] = source
		self.allowEmpty = false
	end

	if configure ~= nil then
		return source:configureWith(configure)
	else
		return source
	end
end

function Source:include(...)
	local n = select('#', ...)
	local args = {...}
	for i = 1, n do
		append(self.includes, args[i], "include", i)
	end

	return self
end

function Source:exclude(...)
	local n = select('#', ...)
	local args = {...}
	for i = 1, n do
		append(self.excludes, args[i], "exclude", i)
	end

	return self
end

function Source:excluded(text)
	if matches(self.excludes, text) then
		return true
	elseif self.parent then
		-- FIXME: Combine this path
		return self.parent:excluded(text)
	else
		return false
	end
end

function Source:included(text)
	if #self.includes == 0 then
		return self.allowEmpty
	else
		return matches(self.includes, text)
	end
end

function Source:configure(item)
	assert.argType(item, "table", "configure", 1)
	-- TODO: Ensure other keys aren't passed
	-- TODO: Fix passing other source instances

	if item.include ~= nil then self:include(item.include) end
	if item.exclude ~= nil then self:exclude(item.exclude) end

	if item.with ~= nil then
		assert.type(item.with, "table", "expected table for with, got %s")
		for _, v in ipairs(item.with) do
			self:with(v)
		end
	end
end

function Source:matches(text)
	return self:included(text) and not self:excluded(text)
end

function Source:hasFiles()
	if self.allowEmpty or #self.includes > 0 then return true end
	for _, source in pairs(self.children) do
		if source:hasFiles() then return true end
	end
	return false
end

function Source:gatherFiles(root, includeDirectories, outList)
	if not outList then outList = {} end

	for dir, source in pairs(self.children) do
		local path = fs.combine(root, dir)
		source:gatherFiles(path, includeDirectories, outList)
	end

	if self.allowEmpty or #self.includes > 0 then
		-- I lied. Its a stack
		local queue, queueN = { root }, 1

		local n = #outList
		while queueN > 0 do
			local path = queue[queueN]
			local relative = path
			if root ~= "" then relative = relative:sub(#root + 2) end
			queueN = queueN - 1

			if fs.isDir(path) then
				if not self:excluded(relative) then
					if includeDirectories and self:included(relative) then
						n = n + 1
						outList[n] = self:buildFile(path, relative)
					end

					for _, v in ipairs(fs.list(path)) do
						queueN = queueN + 1
						queue[queueN] = fs.combine(path, v)
					end
				end
			elseif self:included(relative) and not self:excluded(relative) then
				n = n + 1
				outList[n] = self:buildFile(path, relative)
			end
		end
	end

	return outList
end

function Source:buildFile(path, relative)
	return {
		path = path,
		relative = relative,
		name = relative,
	}
end

return Source
end
preload["howl.files.CopySource"] = function(...)
--- A source location for a series of files.
-- This holds a list of inclusion and exclusion filters.
-- @classmod howl.files.Source

local assert = require "howl.lib.assert"
local matcher = require "howl.files.matcher"
local mixin = require "howl.class.mixin"
local fs = require "howl.platform".fs

local Source = require "howl.files.Source"

local insert = table.insert

local CopySource = Source:subclass("howl.files.CopySource")

function CopySource:initialize(allowEmpty, parent)
	Source.initialize(self, allowEmpty, parent)

	self.renames = {}
	self.modifiers = {}
end

function CopySource:configure(item)
	assert.argType(item, "table", "configure", 1)
	Source.configure(self, item)

	if item.rename ~= nil then self:rename(item.rename) end
	if item.modify ~= nil then self:modify(item.modify) end
end

function CopySource:rename(from, to)
	local tyFrom, tyTo = type(from), type(to)
	if tyFrom == "table" and to == nil then
		for _, v in ipairs(from) do
			self:rename(v)
		end
	elseif tyFrom == "function" and to == nil then
		insert(self.renames, from)
	elseif tyFrom == "string" and tyTo == "string" then
		insert(self.renames, function(file)
			return (file.name:gsub(from, to))
		end)
	else
		error("bad arguments for rename (expected table, function or string, string pair, got " .. tyFrom .. " and " .. tyTo .. ")", 2)
	end
end


function CopySource:modify(modifier)
	local ty = type(modifier)
	if ty == "table" then
		for _, v in ipairs(modifier) do
			self:modify(v)
		end
	elseif ty == "function" then
		insert(self.modifiers, modifier)
	else
		error("bad argument #1 for modify (expected table or function, got " .. ty .. ")", 2)
	end
end

function CopySource:doMutate(file)
	for _, modifier in ipairs(self.modifiers) do
		local contents = modifier(file)
		if contents then file.contents = contents end
	end

	for _, renamer in ipairs(self.renames) do
		local name = renamer(file)
		if name then file.name = name end
	end

	if self.parent then
		return self.parent:doMutate(file)
	else
		return file
	end
end

function CopySource:buildFile(path, relative)
	return self:doMutate {
		path = path,
		relative = relative,
		name = relative,
		contents = fs.read(path),
	}
end

return CopySource
end
preload["howl.context"] = function(...)
--- Handles the whole Howl instance
-- @classmod howl.Context

local assert = require "howl.lib.assert"
local class = require "howl.class"
local mixin = require "howl.class.mixin"
local mediator = require "howl.lib.mediator"
local argparse = require "howl.lib.argparse"

local Logger = require "howl.lib.Logger"
local Manager = require "howl.packages.Manager"

local Context = class("howl.Context"):include(mixin.sealed)

--- Setup the main context
-- @tparam string root The project root of the directory
-- @tparam howl.lib.argparse args The argument parser
function Context:initialize(root, args)
	assert.type(root, "string", "bad argument #1 for Context expected string, got %s")
	assert.type(args, "table", "bad argument #2 for Context expected table, got %s")

	self.root = root
	self.out = "build"
	self.mediator = mediator
	self.arguments = argparse.Options(self.mediator, args)
	self.logger = Logger(self)
	self.packageManager = Manager(self)
	self.modules = {}
end

--- Include a module in this context
-- @tparam string|table The module to include
function Context:include(module)
	if type(module) ~= "table" then
		module = require(module)
	end

	if self.modules[module.name] then
		self.logger:warn(module.name .. " already included, skipping")
		return
	end

	local data = { module = module, }
	self.modules[module.name] = data

	self.logger:verbose("Including " .. module.name .. ": " .. module.description)

	if not module.applied then
		module.applied = true
		if module.apply then module.apply() end
	end

	if module.setup then module.setup(self, data) end
end

function Context:getModuleData(name)
	return self.modules[name]
end

return Context
end
preload["howl.cli"] = function(...)
--- Core script for Howl
-- @script howl.cli

local loader = require "howl.loader"
local colored = require "howl.lib.colored"
local fs = require "howl.platform".fs

local howlFile, currentDirectory = loader.FindHowl()
-- TODO: Don't pass the error message as the current directory: construct mediator/arg parser another time.
local context = require "howl.context"(currentDirectory or fs.currentDir(), {...})

local options = context.arguments

options
	:Option "verbose"
	:Alias "v"
	:Description "Print verbose output"
options
	:Option "time"
	:Alias "t"
	:Description "Display the time taken for tasks"
options
	:Option "trace"
	:Description "Print a stack trace on errors"
options
	:Option "help"
	:Alias "?"
	:Alias "h"
	:Description "Print this help"

context:include "howl.modules.dependencies.file"
context:include "howl.modules.dependencies.task"
context:include "howl.modules.list"
context:include "howl.modules.plugins"
context:include "howl.modules.packages.file"
context:include "howl.modules.packages.gist"
context:include "howl.modules.packages.pastebin"
context:include "howl.modules.tasks.clean"
context:include "howl.modules.tasks.gist"
context:include "howl.modules.tasks.minify"
context:include "howl.modules.tasks.pack"
context:include "howl.modules.tasks.require"

-- Setup Tasks
local taskList = options:Arguments()
local function setHelp()
	if options:Get "help" then
		taskList = { "help" }
	end
end
context.mediator:subscribe({ "ArgParse", "changed" }, setHelp)
setHelp()

-- Locate the howl file
if not howlFile then
	if #taskList == 1 and taskList[1] == "help" then
		colored.writeColor("yellow", "Howl")
		colored.printColor("lightGrey", " is a simple build system for Lua")
		colored.printColor("grey", "You can read the full documentation online: https://github.com/SquidDev-CC/Howl/wiki/")

		colored.printColor("white", (([[
			The key thing you are missing is a HowlFile. This can be "Howlfile" or "Howlfile.lua".
			Then you need to define some tasks. Maybe something like this:
		]]):gsub("\t", ""):gsub("\n+$", "")))

		colored.printColor("magenta", 'Tasks:minify "minify" {')
		colored.printColor("magenta", '  input = "build/Howl.lua",')
		colored.printColor("magenta", '  output = "build/Howl.min.lua",')
		colored.printColor("magenta", '}')

		colored.printColor("white", "Now just run '" .. fs.getName(fs.currentProgram()) .. " minify'!")

		colored.printColor("orange", "\nOptions:")
		options:Help("  ")
	elseif #taskList == 0 then
		error(currentDirectory .. " Use " .. fs.getName(fs.currentProgram()) .. " --help to dislay usage.", 0)
	else
		error(currentDirectory, 0)
	end

	return
end

context.logger:verbose("Found HowlFile at " .. fs.combine(currentDirectory, howlFile))

local tasks, environment = loader.SetupTasks(context, howlFile)

-- Basic list tasks
tasks:Task "list" (function()
	tasks:listTasks()
end):description "Lists all the tasks"

tasks:Task "help" (function()
	print("Howl [options] [task]")
	colored.printColor("orange", "Tasks:")
	tasks:listTasks("  ")

	colored.printColor("orange", "\nOptions:")
	options:Help("  ")
end):description "Print out a detailed usage for Howl"

-- If no other task exists run this
tasks:Default(function()
	context.logger:error("No default task exists.")
	context.logger:verbose("Use 'Tasks:Default' to define a default task")
	colored.printColor("orange", "Choose from: ")
	tasks:listTasks("  ")
end)

environment.dofile(fs.combine(currentDirectory, howlFile))

if not tasks:setup() then
	error("Error setting up tasks", 0)
end

-- Run the task
if not tasks:RunMany(taskList) then
	error("Error running tasks", 0)
end
end
preload["howl.class.mixin"] = function(...)
--- Various mixins for the class library
-- @module howl.class.mixin

local assert = require "howl.lib.assert"
local rawset = rawset

local mixins = {}

--- Prevent subclassing a class
mixins.sealed = {
	static = {
		subclass = function(self, name)
			assert(type(self) == 'table', "Make sure that you are using 'Class:subclass' instead of 'Class.subclass'")
			assert(type(name) == "string", "You must provide a name(string) for your class")
			error("Cannot subclass '" .. tostring(self) .. "' (attempting to create '" .. name .. "')", 2)
		end,
	}
}

mixins.curry = {
	curry = function(self, name)
		assert.type(self, "table", "Bad argument #1 to class:curry (expected table, got %s)")
		assert.type(name, "string", "Bad argument #2 to class:curry (expected string, got %s)")
		local func = self[name]
		assert.type(func, "function", "No such function " .. name)
		return function(...) return func(self, ...) end
	end,

	__div = function(self, name) return self:curry(name) end,
}

mixins.configurable = {
	configureWith = function(self, arg)
		local t = type(arg)
		if t == "table" then
			self:configure(arg)
			return self
		elseif t == "function" then
			arg(self)
			return self
		else
			error("Expected table or function, got " .. type(arg), 2)
		end

		return self
	end,

	__call = function(self, ...) return self:configureWith(...) end,
}

mixins.filterable = {
	__add = function(self, ...) return self:include(...) end,
	__sub = function(self, ...) return self:exclude(...) end,
	with = function(self, ...) return self:configure(...) end,
}

function mixins.delegate(name, keys)
	local out = {}
	for _, key in ipairs(keys) do
		out[key] = function(self, ...)
			local object = self[name]
			return object[key](object, ...)
		end
	end

	return out
end

mixins.optionGroup = {
	static = {
		addOption = function(self, key)
			local func = function(self, value)
				if value == nil then value = true end
				self.options[key] = value
				return self
			end

			self[key:gsub("^%l", string.upper)] = func
			self[key] = func

			if not rawget(self.static, "options") then
				local options = {}
				self.static.options = options
				local parent = self.super and self.super.static.options

				-- TODO: Copy instead. Also propagate to children below
				if parent then setmetatable(options, { __index = parent } ) end
			end

			self.static.options[key] = true

			return self
		end,
		addOptions = function(self, names)
			for i = 1, #names do
				self:addOption(names[i])
			end

			return self
		end,
	},

	configure = function(self, item)
		assert.argType(item, "table", "configure", 1)

		local class = self.class
		local options = class.options
		while class and not options do
			options = class.options
			class = class.super
		end

		if not options then return end

		for k, v in pairs(item) do
			if options[k] then
				self[k](self, v)
			end
		end
	end,

	__newindex = function(self, key, value)
		if self.class.options and self.class.options[key] then -- TODO: This is being applied to superclasses
			self[key](self, value)
		else
			rawset(self, key, value)
		end
	end
}

return mixins
end
preload["howl.class"] = function(...)
--- An OOP library for Lua
-- @module howl.class

local middleclass = {
	_VERSION     = 'middleclass v4.0.0',
	_DESCRIPTION = 'Object Orientation for Lua',
	_URL         = 'https://github.com/kikito/middleclass',
	_LICENSE     = [[
		MIT LICENSE

		Copyright (c) 2011 Enrique García Cota

		Permission is hereby granted, free of charge, to any person obtaining a
		copy of this software and associated documentation files (the
		"Software"), to deal in the Software without restriction, including
		without limitation the rights to use, copy, modify, merge, publish,
		distribute, sublicense, and/or sell copies of the Software, and to
		permit persons to whom the Software is furnished to do so, subject to
		the following conditions:

		The above copyright notice and this permission notice shall be included
		in all copies or substantial portions of the Software.

		THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
		OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
		MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
		IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
		CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
		TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
		SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
	]]
}

local function _createIndexWrapper(aClass, f)
	if f == nil then
		return aClass.__instanceDict
	else
		return function(self, name)
			local value = aClass.__instanceDict[name]

			if value ~= nil then
				return value
			elseif type(f) == "function" then
				return (f(self, name))
			else
				return f[name]
			end
		end
	end
end

local function _propagateInstanceMethod(aClass, name, f)
	f = name == "__index" and _createIndexWrapper(aClass, f) or f
	aClass.__instanceDict[name] = f

	for subclass in pairs(aClass.subclasses) do
		if rawget(subclass.__declaredMethods, name) == nil then
			_propagateInstanceMethod(subclass, name, f)
		end
	end
end

local function _declareInstanceMethod(aClass, name, f)
	aClass.__declaredMethods[name] = f

	if f == nil and aClass.super then
		f = aClass.super.__instanceDict[name]
	end

	_propagateInstanceMethod(aClass, name, f)
end

local function _tostring(self) return "class " .. self.name end
local function _call(self, ...) return self:new(...) end

local function _createClass(name, super)
	local dict = {}
	dict.__index = dict

	local aClass = {
		name = name, super = super, static = {},
		__instanceDict = dict, __declaredMethods = {},
		subclasses = setmetatable({}, {__mode='k'})
	}

	if super then
		setmetatable(aClass.static, { __index = function(_,k) return rawget(dict,k) or super.static[k] end })
	else
		setmetatable(aClass.static, { __index = function(_,k) return rawget(dict,k) end })
	end

	setmetatable(aClass, {
		__index = aClass.static, __tostring = _tostring,
		__call = _call, __newindex = _declareInstanceMethod
	})

	return aClass
end

local function _includeMixin(aClass, mixin)
	assert(type(mixin) == 'table', "mixin must be a table")

	for name,method in pairs(mixin) do
		if name ~= "included" and name ~= "static" then aClass[name] = method end
	end

	for name,method in pairs(mixin.static or {}) do
		aClass.static[name] = method
	end

	if type(mixin.included)=="function" then mixin:included(aClass) end
	return aClass
end

local DefaultMixin = {
	__tostring   = function(self) return "instance of " .. tostring(self.class) end,

	initialize   = function(self, ...) end,

	isInstanceOf = function(self, aClass)
		return
			type(self)       == 'table' and
			type(self.class) == 'table' and
			type(aClass)     == 'table' and
			( aClass == self.class or
				type(aClass.isSubclassOf) == 'function' and
				self.class:isSubclassOf(aClass)
			)
	end,

	static = {
		allocate = function(self)
			assert(type(self) == 'table', "Make sure that you are using 'Class:allocate' instead of 'Class.allocate'")
			return setmetatable({ class = self }, self.__instanceDict)
		end,

		new = function(self, ...)
			assert(type(self) == 'table', "Make sure that you are using 'Class:new' instead of 'Class.new'")
			local instance = self:allocate()
			instance:initialize(...)
			return instance
		end,

		subclass = function(self, name)
			assert(type(self) == 'table', "Make sure that you are using 'Class:subclass' instead of 'Class.subclass'")
			assert(type(name) == "string", "You must provide a name(string) for your class")

			local subclass = _createClass(name, self)

			for methodName, f in pairs(self.__instanceDict) do
				_propagateInstanceMethod(subclass, methodName, f)
			end
			subclass.initialize = function(instance, ...) return self.initialize(instance, ...) end

			self.subclasses[subclass] = true
			self:subclassed(subclass)

			return subclass
		end,

		subclassed = function(self, other) end,

		isSubclassOf = function(self, other)
			return
				type(other)      == 'table' and
				type(self)       == 'table' and
				type(self.super) == 'table' and
				(self.super == other or
					type(self.super.isSubclassOf) == 'function' and
					self.super:isSubclassOf(other) )
		end,

		include = function(self, ...)
			assert(type(self) == 'table', "Make sure you that you are using 'Class:include' instead of 'Class.include'")
			for _,mixin in ipairs({...}) do _includeMixin(self, mixin) end
			return self
		end
	}
}

return function(name, super)
	assert(type(name) == 'string', "A name (string) is needed for the new class")
	return super and super:subclass(name) or _includeMixin(_createClass(name), DefaultMixin)
end
end
if not shell or type(... or nil) == 'table' then
local tbl = ... or {}
tbl.require = require tbl.preload = preload
return tbl
else
return preload["howl.cli"](...)
end
