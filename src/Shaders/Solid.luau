--!strict

--// One colour, steady

local Shader = require(`../Shader`)

local def: Shader.Def = {
	Name = 'Solid',
	Description = 'One steady colour.',
	Static = true,
	Order = { 'Color', 'Brightness' },
	Params = {
		Color = { Kind = 'Color', Default = 'FFFFFF' },
		Brightness = { Kind = 'Number', Default = 1, Min = 0, Max = 1 },
	},

	Evaluate = function(params, _inputs, _time, out)
		out.Color = params.Color
		out.Emission = params.Brightness
	end,
}

return def
