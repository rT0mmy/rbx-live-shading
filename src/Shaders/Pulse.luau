--!strict
--!native

--// One colour breathing between Floor and full

local Shader = require(`../Shader`)

local def: Shader.Def = {
	Name = 'Pulse',
	Description = 'One colour fading up and down.',
	Order = { 'Color', 'Speed', 'Floor', 'Brightness', 'Offset' },
	Inputs = { Index = 0 },
	Params = {
		Color = { Kind = 'Color', Default = 'FFFFFF' },
		Speed = { Kind = 'Number', Default = 0.5, Min = 0.05, Max = 5, Label = 'Speed (pulses/s)' },
		Floor = { Kind = 'Number', Default = 0.1, Min = 0, Max = 1, Label = 'Dimmest' },
		Brightness = { Kind = 'Number', Default = 1, Min = 0, Max = 1 },
		Offset = { Kind = 'Number', Default = 0, Min = 0, Max = 1, Label = 'Offset per index (cycles)' },
	},

	Evaluate = function(params, inputs, time, out)
		--// The fraction is taken before the multiply by 2 pi: server time is large enough that
		--// sin(time * speed * 2 pi) would lose its precision
		local phase = (time * params.Speed + inputs.Index * params.Offset) % 1
		local wave = 0.5 - 0.5 * math.cos(phase * 2 * math.pi)

		out.Color = params.Color
		out.Emission = params.Brightness * (params.Floor + (1 - params.Floor) * wave)
	end,
}

return def
