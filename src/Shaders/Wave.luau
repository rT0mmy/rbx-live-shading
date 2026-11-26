--!strict
--!native

--// Bands of light rolling through the world, by where each target is: no Index needed

local Shader = require(`../Shader`)

local def: Shader.Def = {
	Name = 'Wave',
	Description = 'Bands of light rolling along an axis of the world. Best with PerTarget.',
	Order = { 'Color', 'Axis', 'Speed', 'Wavelength', 'Floor', 'Brightness' },
	Inputs = { X = 0, Y = 0, Z = 0 },
	Params = {
		Color = { Kind = 'Color', Default = '00AAFF' },
		Axis = { Kind = 'Choice', Default = 'X', Options = { 'X', 'Y', 'Z' } },
		Speed = { Kind = 'Number', Default = 0.5, Min = 0.05, Max = 5, Label = 'Speed (waves/s)' },
		Wavelength = { Kind = 'Number', Default = 40, Min = 2, Max = 500, Label = 'Wavelength (studs)' },
		Floor = { Kind = 'Number', Default = 0, Min = 0, Max = 1, Label = 'Dimmest' },
		Brightness = { Kind = 'Number', Default = 1, Min = 0, Max = 1 },
	},

	Evaluate = function(params, inputs, time, out)
		local along = inputs[params.Axis] or 0
		local phase = (time * params.Speed - along / params.Wavelength) % 1
		local wave = 0.5 + 0.5 * math.cos(phase * 2 * math.pi)

		out.Color = params.Color
		out.Emission = params.Brightness * (params.Floor + (1 - params.Floor) * wave)
	end,
}

return def
