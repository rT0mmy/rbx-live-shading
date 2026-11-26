-- Loads the library under Lune with string requires (@self, ./, ../),
-- rewriting `const` to `local`, and with a stubbed `game` / `workspace`.
local fs = require('@lune/fs')
local luau = require('@lune/luau')
local process = require('@lune/process')
local roblox = require('@lune/roblox')
local serde = require('@lune/serde')

--// Run from the repository root: lune run tests/run
local ROOT = (string.gsub(string.gsub(process.cwd, '\\', '/'), '/$', '')) .. '/src'

local cache = {}

local BUILTINS = {
	math = math,
	string = string,
	table = table,
	type = type,
	typeof = typeof,
	pairs = pairs,
	ipairs = ipairs,
	next = next,
	tostring = tostring,
	tonumber = tonumber,
	error = error,
	assert = assert,
	pcall = pcall,
	select = select,
	setmetatable = setmetatable,
	getmetatable = getmetatable,
	rawget = rawget,
	rawset = rawset,
	print = print,
	warn = warn,
	buffer = buffer,
	bit32 = bit32,
	vector = vector,
	os = os,
	task = task,
	utf8 = utf8,
	coroutine = coroutine,
	rawequal = rawequal,
	unpack = unpack,
	xpcall = xpcall,
}
local GLOBALS = {}
for name in BUILTINS do
	table.insert(GLOBALS, name)
end

local HttpService = {
	JSONEncode = function(_, value)
		return serde.encode('json', value)
	end,
	JSONDecode = function(_, text)
		return serde.decode('json', text)
	end,
}

local function stubContainer(name)
	return {
		Name = name,
		FindFirstChild = function()
			return nil
		end,
		GetChildren = function()
			return {}
		end,
		DescendantAdded = { Connect = function() end },
		DescendantRemoving = { Connect = function() end },
	}
end

local services = {
	HttpService = HttpService,
	ReplicatedStorage = stubContainer('ReplicatedStorage'),
	ServerStorage = stubContainer('ServerStorage'),
	ContentProvider = {},
	RunService = {
		IsClient = function()
			return false
		end,
	},
}

local game = {
	GetService = function(_, name)
		return services[name] or stubContainer(name)
	end,
}

local env = {
	game = game,
	workspace = { Gravity = 196.2, GlobalWind = roblox.Vector3.zero },
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	BrickColor = roblox.BrickColor,
	PhysicalProperties = roblox.PhysicalProperties,
	Enum = roblox.Enum,
	RaycastParams = roblox.RaycastParams,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	NumberSequence = roblox.NumberSequence,
	Instance = roblox.Instance,
	typeof = roblox.typeof or typeof,
}

local function resolve(path)
	for _, candidate in { path .. '.luau', path .. '/init.luau' } do
		if fs.isFile(candidate) then return candidate end
	end
	error('cannot resolve ' .. path)
end

local function dirOf(file)
	return string.match(file, '^(.*)/[^/]*$')
end

local load

local function makeRequire(file)
	local isInit = string.match(file, '/init%.luau$') ~= nil
	local here = dirOf(file)
	-- In an init module ./ is the folder's siblings and @self the folder
	local base = if isInit then dirOf(here) else here

	return function(spec)
		local target
		if string.sub(spec, 1, 6) == '@game/' then
			target = ROOT .. '/' .. string.sub(spec, 7)
		elseif string.sub(spec, 1, 6) == '@self/' then
			target = here .. '/' .. string.sub(spec, 7)
		elseif string.sub(spec, 1, 2) == './' then
			target = base .. '/' .. string.sub(spec, 3)
		elseif string.sub(spec, 1, 3) == '../' then
			local dir = base
			while string.sub(spec, 1, 3) == '../' do
				dir = dirOf(dir)
				spec = string.sub(spec, 4)
			end
			target = dir .. '/' .. spec
		else
			error('unsupported require ' .. spec)
		end
		return load(resolve(target))
	end
end

function load(file)
	if cache[file] ~= nil then return cache[file] end

	local source = fs.readFile(file)
	source = string.gsub(source, '\nconst ', '\nlocal ')
	source = string.gsub(source, '^const ', 'local ')
	source = string.gsub(source, '\n(\t+)const ', '\n%1local ')

	-- luau.load copies only raw keys of the environment, so every global goes in as one
	local fenv = { require = makeRequire(file) }
	for _, name in GLOBALS do
		fenv[name] = (_G :: any)[name] or BUILTINS[name]
	end
	for k, v in env do
		fenv[k] = v
	end

	local fn = luau.load(source, { debugName = file, environment = fenv })
	local result = fn()
	cache[file] = result
	return result
end

return {
	--// Services by name; a test can put its own fakes in before Load
	Services = services,
	Load = function()
		return load(resolve(ROOT))
	end,
}
