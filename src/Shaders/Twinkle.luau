--!strict
--!native

--// Random sparkles: each step, a share of the indices light up and fade. Every client picks the same ones.

local Shader = require(`../Shader`)

const WRAP = 4294967296

--[[
	A step and an index as a number in 0..1 that looks random, the same on every client: integer
	xorshift, so no float maths that could differ between devices

	@param step number
	@param index number
	@return number
--]]
local function hash(step: number, index: number): number
	local x = bit32.bxor(step % WRAP, (index * 73244475) % WRAP, 0x9E3779B9)

	for _ = 1, 3 do
		x = bit32.bxor(x, bit32.lshift(x, 13))
		x = bit32.bxor(x, bit32.rshift(x, 17))
		x = bit32.bxor(x, bit32.lshift(x, 5))
	end

	return x / WRAP
end

local def: Shader.Def = {
	Name = 'Twinkle',
	Description = 'Random sparkles. Best with PerTarget, so each target picks for itself.',
	Order = { 'Color', 'Density', 'Speed', 'Brightness' },
	Inputs = { Index = 0 },
	Params = {
		Color = { Kind = 'Color', Default = 'FFFFFF' },
		Density = { Kind = 'Number', Default = 0.3, Min = 0, Max = 1, Label = 'Density (share lit)' },
		Speed = { Kind = 'Number', Default = 2, Min = 0.2, Max = 10, Label = 'Speed (sparkles/s)' },
		Brightness = { Kind = 'Number', Default = 1, Min = 0, Max = 1 },
	},

	Evaluate = function(params, inputs, time, out)
		local position = time * params.Speed
		local step = position // 1
		local lit = hash(step, inputs.Index) < params.Density

		out.Color = params.Color
		out.Emission = if lit then params.Brightness * math.sin((position - step) * math.pi) else 0
	end,
}

return def
