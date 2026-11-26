--!strict
--!native

--[[ shader's parameters (sanitized)
	@Number     { Default, Min, Max, Step? }       number
	@Color      { Default }                        'RRGGBB' -> Color3
	@Colors     { Default, Min?, Max? }            {'RRGGBB'} -> {Color3}
	@Bool       { Default }                        boolean
	@Choice     { Default, Options }               one of Options
--]]

local Types = require(`./Types`)

local Param = {}

export type Kind = Types.Kind
export type Spec = Types.ParamSpec

const KINDS = { Number = true, Color = true, Colors = true, Bool = true, Choice = true }

const MAX_COLORS = 8

--[[
	A colour as six uppercase hex digits, from a Color3, a 3-byte buffer or a hex string

	@param value any
	@return string?
--]]
function Param.Hex(value: any): string?
	if typeof(value) == 'Color3' then return string.upper(value:ToHex()) end

	if typeof(value) == 'buffer' then
		if buffer.len(value) < 3 then return nil end
		return string.format('%02X%02X%02X', buffer.readu8(value, 0), buffer.readu8(value, 1), buffer.readu8(value, 2))
	end

	if type(value) ~= 'string' then return nil end

	local digits = string.match(value, '^#?(%x%x%x%x%x%x)$')
	return if digits then string.upper(digits) else nil
end

--[[
	Checks a spec at definition time

	@param name string
	@param spec Spec
	@param owner string -- the shader, for the error
	@return nil
--]]
function Param.Check(name: string, spec: Spec, owner: string)
	local where = `Shading.Shader('{owner}') param '{name}'`

	assert(
		type(spec) == 'table' and KINDS[spec.Kind],
		`{where} - Kind must be one of Number, Color, Colors, Bool, Choice`
	)

	if spec.Kind == 'Number' then
		assert(type(spec.Default) == 'number', `{where} - Default must be a number`)
		assert(type(spec.Min) == 'number' and type(spec.Max) == 'number', `{where} - needs Min and Max`)
		assert((spec.Min :: number) <= (spec.Max :: number), `{where} - Min is above Max`)
	elseif spec.Kind == 'Color' then
		assert(Param.Hex(spec.Default), `{where} - Default must be a colour`)
	elseif spec.Kind == 'Colors' then
		assert(type(spec.Default) == 'table' and #spec.Default >= 1, `{where} - Default must be a list of colours`)

		for _, colour in spec.Default do
			assert(Param.Hex(colour), `{where} - Default holds something that is not a colour`)
		end
	elseif spec.Kind == 'Bool' then
		assert(type(spec.Default) == 'boolean', `{where} - Default must be a boolean`)
	elseif spec.Kind == 'Choice' then
		assert(type(spec.Options) == 'table' and #spec.Options >= 1, `{where} - needs Options`)
		assert(table.find(spec.Options, spec.Default), `{where} - Default is not one of its Options`)
	end
end

--[[
	The default as clean data

	@param spec Spec
	@return any
--]]
function Param.Default(spec: Spec): any
	if spec.Kind == 'Color' then return Param.Hex(spec.Default) end

	if spec.Kind == 'Colors' then
		local out = {}

		for _, colour in spec.Default do
			table.insert(out, Param.Hex(colour))
		end

		return out
	end

	return spec.Default
end

--[[
	Untrusted input as clean data; the default when it is missing or unreadable

	@param spec Spec
	@param raw any
	@return any, boolean -- the value, and whether raw was refused (missing is not refused)
--]]
function Param.Sanitize(spec: Spec, raw: any): (any, boolean)
	if raw == nil then return Param.Default(spec), false end

	local kind = spec.Kind

	if kind == 'Number' then
		if type(raw) ~= 'number' or raw ~= raw then return Param.Default(spec), true end

		local value = math.clamp(raw, spec.Min :: number, spec.Max :: number)
		local step = spec.Step

		if step and step > 0 then
			value = math.clamp(math.round(value / step) * step, spec.Min :: number, spec.Max :: number)
		end

		return value, false
	end

	if kind == 'Color' then
		local hex = Param.Hex(raw)

		return hex or Param.Default(spec), hex == nil
	end

	if kind == 'Colors' then
		if type(raw) ~= 'table' then return Param.Default(spec), true end

		local most = math.min(spec.Max or MAX_COLORS, MAX_COLORS)
		local out = {}
		local refused = false

		for _, colour in ipairs(raw) do
			local hex = Param.Hex(colour)

			if hex and #out < most then
				table.insert(out, hex)
			else
				refused = true
			end
		end

		if #out < (spec.Min or 1) then return Param.Default(spec), true end

		return out, refused
	end

	if kind == 'Bool' then
		if type(raw) ~= 'boolean' then return Param.Default(spec), true end

		return raw, false
	end

	if type(raw) ~= 'string' or not table.find(spec.Options :: { string }, raw) then
		return Param.Default(spec), true
	end

	return raw, false
end

--[[
	Clean data as the shader reads it: colours become Color3s

	@param spec Spec
	@param value any -- already sanitized
	@return any
--]]
function Param.Decode(spec: Spec, value: any): any
	if spec.Kind == 'Color' then return Color3.fromHex(value) end

	if spec.Kind == 'Colors' then
		local out = table.create(#value)

		for index, hex in value do
			out[index] = Color3.fromHex(hex)
		end

		return out
	end

	return value
end

return Param
