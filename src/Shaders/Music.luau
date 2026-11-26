--!strict
--!native

--// Brightness and colour following Shading.Config.Loudness

local Shader = require(`../Shader`)

local def: Shader.Def = {
	Name = 'Music',
	Description = 'Follows the music: set Shading.Config.Loudness to read it.',
	Order = { 'Color', 'Peak', 'Gain', 'Floor', 'Brightness' },
	Inputs = { Loudness = 0 },
	Params = {
		Color = { Kind = 'Color', Default = 'FF0066', Label = 'Quiet colour' },
		Peak = { Kind = 'Color', Default = 'FFFFFF', Label = 'Loud colour' },
		Gain = { Kind = 'Number', Default = 2, Min = 0.5, Max = 10 },
		Floor = { Kind = 'Number', Default = 0.05, Min = 0, Max = 1, Label = 'Dimmest' },
		Brightness = { Kind = 'Number', Default = 1, Min = 0, Max = 1 },
	},

	Evaluate = function(params, inputs, _time, out)
		local level = math.clamp(inputs.Loudness * params.Gain, 0, 1)

		out.Color = params.Color:Lerp(params.Peak, level)
		out.Emission = params.Brightness * (params.Floor + (1 - params.Floor) * level)
	end,
}

return def
