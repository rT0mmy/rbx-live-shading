--!strict
--!native

--// A shader is the render code: from a material's params, its binding's inputs and the time, it
--// works out the output channels the writers put onto instances (Writers/).

local Param = require(`./Param`)
local Types = require(`./Types`)

local Shader = {}

export type Out = Types.Out
export type Evaluate = Types.Evaluate
export type Def = Types.ShaderDef
export type Shader = Types.Shader

local registry: { [string]: Shader } = {}

--[[
	Checks a definition and registers it under its name. Errors here, at definition, for anything
	malformed, and for a name already taken.

	@param def Def
	@return Shader
--]]
function Shader.Define(def: Def): Shader
	assert(type(def) == 'table', 'Shading.Shader - needs a definition table')
	assert(type(def.Name) == 'string' and def.Name ~= '', 'Shading.Shader - needs a Name')
	assert(not registry[def.Name], `Shading.Shader('{def.Name}') - already defined`)
	assert(type(def.Evaluate) == 'function', `Shading.Shader('{def.Name}') - needs Evaluate`)
	assert(
		def.Rate == nil or (type(def.Rate) == 'number' and def.Rate > 0),
		`Shading.Shader('{def.Name}') - Rate must be above 0`
	)

	local params: { [string]: Param.Spec } = def.Params or {}

	for name, spec in params do
		Param.Check(name, spec, def.Name)
	end

	local order = {}

	if def.Order then
		for _, name in def.Order do
			assert(params[name], `Shading.Shader('{def.Name}') - Order names '{name}', which is not a param`)
			table.insert(order, name)
		end
	end

	local rest = {}

	for name in params do
		if not table.find(order, name) then table.insert(rest, name) end
	end

	table.sort(rest)
	table.move(rest, 1, #rest, #order + 1, order)

	local shader: Shader = {
		Name = def.Name,
		Description = def.Description or '',
		Params = params,
		Order = order,
		Inputs = def.Inputs or {},
		Static = def.Static == true,
		Rate = def.Rate,
		Evaluate = def.Evaluate,
	}

	registry[def.Name] = shader

	return shader
end

function Shader.Get(name: string): Shader?
	return registry[name]
end

--[[
	Every registered shader's name, sorted

	@return {string}
--]]
function Shader.Names(): { string }
	local out = {}

	for name in registry do
		table.insert(out, name)
	end

	table.sort(out)

	return out
end

return Shader
