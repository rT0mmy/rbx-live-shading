--!strict
--!native

--// Unsteady light from smooth noise: a flame, a failing tube

local Shader = require(`../Shader`)

local def: Shader.Def = {
	Name = 'Flicker',
	Description = 'Unsteady light, like a flame or a failing tube.',
	Order = { 'Color', 'Speed', 'Depth', 'Brightness' },
	Inputs = { Index = 0 },
	Params = {
		Color = { Kind = 'Color', Default = 'FFAA44' },
		Speed = { Kind = 'Number', Default = 6, Min = 0.5, Max = 20, Label = 'Speed (wobbles/s)' },
		Depth = { Kind = 'Number', Default = 0.6, Min = 0, Max = 1, Label = 'Depth (how far it dips)' },
		Brightness = { Kind = 'Number', Default = 1, Min = 0, Max = 1 },
	},

	Evaluate = function(params, inputs, time, out)
		--// math.noise repeats every 256, so wrapping server time there is seamless and keeps it small
		--// enough for the noise to stay smooth. Each Index reads its own row, so neighbours flicker apart.
		local noise = math.noise((time * params.Speed) % 256, inputs.Index * 7.31 + 0.5)
		local steady = math.clamp(0.5 + noise, 0, 1)

		out.Color = params.Color
		out.Emission = params.Brightness * (1 - params.Depth * (1 - steady))
	end,
}

return def
