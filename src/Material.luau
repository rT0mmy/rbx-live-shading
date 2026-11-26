--!strict
--!native

local Param = require(`./Param`)
local Shader = require(`./Shader`)
local Types = require(`./Types`)

local Material = {}

export type Material = Types.Material

--[[
	A clean material from untrusted input. Every param the shader has is filled in, missing or
	unreadable ones with their default; params it does not have are dropped.

	@param raw any -- { Shader = string, Params = {[string]: any}? }
	@return Material?, {string} -- nil when there is no such shader; and what was dropped
--]]
function Material.Sanitize(raw: any): (Material?, { string })
	local issues: { string } = {}

	if type(raw) ~= 'table' then return nil, { 'material is not a table' } end

	local shader = if type(raw.Shader) == 'string' then Shader.Get(raw.Shader) else nil

	if not shader then return nil, { `no shader called {tostring(raw.Shader)}` } end

	local given = if type(raw.Params) == 'table' then raw.Params else {}
	local params = {}

	for name, spec in shader.Params do
		local value, refused = Param.Sanitize(spec, given[name])

		if refused then table.insert(issues, `{shader.Name}.{name} was not usable, so it took its default`) end

		params[name] = value
	end

	for name in given do
		if type(name) ~= 'string' or not shader.Params[name] then
			table.insert(issues, `{shader.Name} has no param {tostring(name)}`)
		end
	end

	return { Shader = shader.Name, Params = params }, issues
end

--[[
	A material for a shader, the params given and the rest at their defaults. For code that writes
	its own materials; errors for an unknown shader instead of returning nil.

	@param shader string
	@param params {[string]: any}?
	@return Material
--]]
function Material.new(shader: string, params: { [string]: any }?): Material
	local material, issues = Material.Sanitize({ Shader = shader, Params = params })

	assert(material, issues[1])

	for _, issue in issues do
		warn(`[Shading] {issue}`)
	end

	return material
end

--[[
	The params as the shader reads them: colours become Color3s

	@param material Material -- already sanitized
	@return {[string]: any}
--]]
function Material.Decode(material: Material): { [string]: any }
	local shader = Shader.Get(material.Shader)
	local out = {}

	if not shader then return out end

	for name, spec in shader.Params do
		local value = material.Params[name]

		out[name] = Param.Decode(spec, if value == nil then Param.Default(spec) else value)
	end

	return out
end

--[[
	Whether two clean materials are the same

	@param a Material?
	@param b Material?
	@return boolean
--]]
function Material.Equal(a: Material?, b: Material?): boolean
	if a == b then return true end
	if not a or not b or a.Shader ~= b.Shader then return false end

	for name, value in a.Params do
		local other = b.Params[name]

		if type(value) == 'table' and type(other) == 'table' then
			if #value ~= #other then return false end

			for index, item in value do
				if other[index] ~= item then return false end
			end
		elseif value ~= other then
			return false
		end
	end

	for name in b.Params do
		if a.Params[name] == nil then return false end
	end

	return true
end

return Material
