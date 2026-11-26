--!strict
--!native

--[[
	Materials as compact buffers, for remotes and saved data. Both ends must have the same shader
	definitions: params are written in the shader's Order, and only those not at their default.

	u8      version
	u8      shader name length, then the name
	bytes   one bit a param in Order, set when it is written (not at its default)
	then each written param, in Order:
		Number   u8 tag, then 0: u8 whole number | 1: f32 | 2: f64 (the smallest that holds it exactly)
		Color    3 bytes
		Colors   u8 count, then 3 bytes each
		Bool     u8
		Choice   u8, the option's place in Options
--]]

local Material = require(`./Material`)
local Param = require(`./Param`)
local Shader = require(`./Shader`)
local Types = require(`./Types`)

local Wire = {}

const VERSION = 1

--// Tests whether a number survives f32
local scratch = buffer.create(4)

--[[
	How a number is written: its tag and its size in bytes, tag included

	@param value number
	@return number, number
--]]
local function numberTag(value: number): (number, number)
	if value >= 0 and value <= 255 and value % 1 == 0 then return 0, 2 end

	buffer.writef32(scratch, 0, value)
	if buffer.readf32(scratch, 0) == value then return 1, 5 end

	return 2, 9
end

--[[
	Whether a param holds its default

	@param spec ParamSpec
	@param value any -- clean
	@return boolean
--]]
local function isDefault(spec: Types.ParamSpec, value: any): boolean
	local default = Param.Default(spec)

	if spec.Kind ~= 'Colors' then return value == default end
	if #value ~= #default then return false end

	for index, hex in value do
		if default[index] ~= hex then return false end
	end

	return true
end

--[[
	The bytes a written param takes

	@param spec ParamSpec
	@param value any -- clean
	@return number
--]]
local function sizeOf(spec: Types.ParamSpec, value: any): number
	local kind = spec.Kind

	if kind == 'Number' then
		local _, size = numberTag(value)
		return size
	end

	if kind == 'Color' then return 3 end
	if kind == 'Colors' then return 1 + 3 * #value end

	return 1
end

--[[
	Writes a colour

	@param b buffer
	@param offset number
	@param hex string -- 'RRGGBB'
	@return number -- the offset after it
--]]
local function writeColor(b: buffer, offset: number, hex: string): number
	for channel = 0, 2 do
		buffer.writeu8(b, offset + channel, tonumber(string.sub(hex, channel * 2 + 1, channel * 2 + 2), 16) :: number)
	end

	return offset + 3
end

--[[
	Reads a colour

	@param b buffer
	@param offset number
	@return string -- 'RRGGBB'
--]]
local function readColor(b: buffer, offset: number): string
	return string.format(
		'%02X%02X%02X',
		buffer.readu8(b, offset),
		buffer.readu8(b, offset + 1),
		buffer.readu8(b, offset + 2)
	)
end

--[[
	A material as a buffer

	@param material Material -- sanitized
	@return buffer
--]]
function Wire.Pack(material: Types.Material): buffer
	local shader = Shader.Get(material.Shader)

	assert(shader, `Shading.Pack - no shader called {material.Shader}`)

	local name = shader.Name
	local order = shader.Order
	local maskSize = (#order + 7) // 8

	assert(#name <= 255, 'Shading.Pack - shader name over 255 bytes')

	--// Measured first, so the buffer is made once
	local size = 2 + #name + maskSize
	local written = {}

	for index, key in order do
		local spec = shader.Params[key]
		local value = material.Params[key]

		if value ~= nil and not isDefault(spec, value) then
			written[index] = true
			size += sizeOf(spec, value)
		end
	end

	local b = buffer.create(size)

	buffer.writeu8(b, 0, VERSION)
	buffer.writeu8(b, 1, #name)
	buffer.writestring(b, 2, name)

	local maskAt = 2 + #name
	local offset = maskAt + maskSize

	for index, key in order do
		if not written[index] then continue end

		local byte = maskAt + (index - 1) // 8
		buffer.writeu8(b, byte, bit32.bor(buffer.readu8(b, byte), bit32.lshift(1, (index - 1) % 8)))

		local spec = shader.Params[key]
		local value = material.Params[key]
		local kind = spec.Kind

		if kind == 'Number' then
			local tag = numberTag(value)

			buffer.writeu8(b, offset, tag)

			if tag == 0 then
				buffer.writeu8(b, offset + 1, value)
				offset += 2
			elseif tag == 1 then
				buffer.writef32(b, offset + 1, value)
				offset += 5
			else
				buffer.writef64(b, offset + 1, value)
				offset += 9
			end
		elseif kind == 'Color' then
			offset = writeColor(b, offset, value)
		elseif kind == 'Colors' then
			buffer.writeu8(b, offset, #value)
			offset += 1

			for _, hex in value do
				offset = writeColor(b, offset, hex)
			end
		elseif kind == 'Bool' then
			buffer.writeu8(b, offset, if value then 1 else 0)
			offset += 1
		else
			buffer.writeu8(b, offset, table.find(spec.Options :: { string }, value) :: number)
			offset += 1
		end
	end

	return b
end

--[[
	Reads a buffer from Pack. Safe on anything: a short or garbled buffer gives nil, and what it
	holds is sanitized like any other untrusted material.

	@param b any -- a buffer
	@return Material?, {string} -- nil when unreadable or for no such shader; and what was dropped
--]]
function Wire.Unpack(b: any): (Types.Material?, { string })
	if typeof(b) ~= 'buffer' then return nil, { 'not a buffer' } end

	local ok, raw = pcall(function()
		local version = buffer.readu8(b, 0)

		if version ~= VERSION then error(`version {version}`, 0) end

		local length = buffer.readu8(b, 1)
		local name = buffer.readstring(b, 2, length)
		local shader = Shader.Get(name)

		if not shader then return { Shader = name } end

		local order = shader.Order
		local maskAt = 2 + length
		local offset = maskAt + (#order + 7) // 8
		local params = {}

		for index, key in order do
			local mask = buffer.readu8(b, maskAt + (index - 1) // 8)

			if bit32.band(mask, bit32.lshift(1, (index - 1) % 8)) == 0 then continue end

			local spec = shader.Params[key]
			local kind = spec.Kind

			if kind == 'Number' then
				local tag = buffer.readu8(b, offset)

				if tag == 0 then
					params[key] = buffer.readu8(b, offset + 1)
					offset += 2
				elseif tag == 1 then
					params[key] = buffer.readf32(b, offset + 1)
					offset += 5
				else
					params[key] = buffer.readf64(b, offset + 1)
					offset += 9
				end
			elseif kind == 'Color' then
				params[key] = readColor(b, offset)
				offset += 3
			elseif kind == 'Colors' then
				local colors = {}
				local count = buffer.readu8(b, offset)

				offset += 1

				for _ = 1, count do
					table.insert(colors, readColor(b, offset))
					offset += 3
				end

				params[key] = colors
			elseif kind == 'Bool' then
				params[key] = buffer.readu8(b, offset) == 1
				offset += 1
			else
				--// Out of range, it is a number, which sanitizing refuses
				local at = buffer.readu8(b, offset)
				params[key] = (spec.Options :: { string })[at] or at
				offset += 1
			end
		end

		return { Shader = name, Params = params }
	end)

	if not ok then return nil, { `unreadable buffer: {raw}` } end

	return Material.Sanitize(raw)
end

return Wire
