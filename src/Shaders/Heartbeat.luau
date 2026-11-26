--!strict
--!native

--// A double thump, then rest

local Shader = require(`../Shader`)

--[[
	A soft bump centred on at

	@param phase number
	@param at number
	@param width number
	@return number
--]]
local function bump(phase: number, at: number, width: number): number
	local d = (phase - at) / width
	return math.exp(-d * d)
end

local def: Shader.Def = {
	Name = 'Heartbeat',
	Description = 'A double thump, then rest.',
	Order = { 'Color', 'Rate', 'Floor', 'Brightness', 'Offset' },
	Inputs = { Index = 0 },
	Params = {
		Color = { Kind = 'Color', Default = 'FF2040' },
		Rate = { Kind = 'Number', Default = 70, Min = 30, Max = 200, Step = 1, Label = 'Rate (beats/min)' },
		Floor = { Kind = 'Number', Default = 0.05, Min = 0, Max = 1, Label = 'Dimmest' },
		Brightness = { Kind = 'Number', Default = 1, Min = 0, Max = 1 },
		Offset = { Kind = 'Number', Default = 0, Min = 0, Max = 1, Label = 'Offset per index (beats)' },
	},

	Evaluate = function(params, inputs, time, out)
		local phase = (time * params.Rate / 60 + inputs.Index * params.Offset) % 1
		local beat = math.max(bump(phase, 0.1, 0.04), 0.6 * bump(phase, 0.28, 0.05))

		out.Color = params.Color
		out.Emission = params.Brightness * (params.Floor + (1 - params.Floor) * beat)
	end,
}

return def
