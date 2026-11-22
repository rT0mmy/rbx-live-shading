--!strict
--!native

--// A shader is the render code: from a material's params, its binding's inputs and the time, it
--// works out the output channels the writers put onto instances (Writers/).

local Param = require(`./Param`)

local Shader = {}

--// Shader write seq
export type Out = {
	Color: Color3?,
	Emission: number?, -- 0..1: how lit; drives Neon on emissive parts and light brightness
	Transparency: number?, -- 0..1
}

export type Evaluate = (params: { [string]: any }, inputs: { [string]: number }, time: number, out: Out) -> ()

export type Def = {
	Name: string,
	Description: string?,
	Params: { [string]: Param.Spec },
	Order: { string }?, -- params in the order an editor lists them; alphabetical otherwise
	Inputs: { [string]: number }?, -- per-binding inputs it reads, and their defaults
	Static: boolean?, -- the output never changes with time, so it is worked out only when something it reads does
	Rate: number?, -- evaluations per second at most; every frame when nil
	Evaluate: Evaluate,
}

export type Shader = {
	Name: string,
	Description: string,
	Params: { [string]: Param.Spec },
	Order: { string },
	Inputs: { [string]: number },
	Static: boolean,
	Rate: number?,
	Evaluate: Evaluate,
}

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
