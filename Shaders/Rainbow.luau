--!strict
--!native

--// The hue wheel, each Index a little further round it

local Shader = require(`../Shader`)

local def: Shader.Def = {
	Name = 'Rainbow',
	Description = 'Rolls round the hue wheel, each light a little further on.',
	Order = { 'Speed', 'Spread', 'Saturation', 'Brightness' },
	Inputs = { Index = 0 },
	Params = {
		Speed = { Kind = 'Number', Default = 0.1, Min = 0.01, Max = 2, Label = 'Speed (turns/s)' },
		Spread = { Kind = 'Number', Default = 0.25, Min = 0, Max = 1, Label = 'Spread per index (turns)' },
		Saturation = { Kind = 'Number', Default = 1, Min = 0, Max = 1 },
		Brightness = { Kind = 'Number', Default = 1, Min = 0, Max = 1 },
	},

	Evaluate = function(params, inputs, time, out)
		local hue = (time * params.Speed + inputs.Index * params.Spread) % 1

		out.Color = Color3.fromHSV(hue, params.Saturation, 1)
		out.Emission = params.Brightness
	end,
}

return def
