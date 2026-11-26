--!strict
--!native

--// Short hard flashes in bursts

local Shader = require(`../Shader`)

const FLASH = 0.06 -- seconds lit per flash
const GAP = 0.06 -- seconds dark between flashes in a burst

local def: Shader.Def = {
	Name = 'Strobe',
	Description = 'Bursts of short hard flashes.',
	Order = { 'Color', 'Speed', 'Flashes', 'Brightness', 'Offset' },
	Inputs = { Index = 0 },
	Params = {
		Color = { Kind = 'Color', Default = 'FFFFFF' },
		Speed = { Kind = 'Number', Default = 1, Min = 0.1, Max = 4, Label = 'Speed (bursts/s)' },
		Flashes = { Kind = 'Number', Default = 2, Min = 1, Max = 6, Step = 1, Label = 'Flashes per burst' },
		Brightness = { Kind = 'Number', Default = 1, Min = 0, Max = 1 },
		Offset = { Kind = 'Number', Default = 0, Min = 0, Max = 1, Label = 'Offset per index (bursts)' },
	},

	Evaluate = function(params, inputs, time, out)
		local period = 1 / params.Speed

		--// Flashes keep their length at any speed; a burst too long for its period is cut short
		local into = ((time * params.Speed + inputs.Index * params.Offset) % 1) * period
		local slot = into // (FLASH + GAP)
		local lit = slot < params.Flashes and into - slot * (FLASH + GAP) < FLASH

		out.Color = params.Color
		out.Emission = if lit then params.Brightness else 0
	end,
}

return def
