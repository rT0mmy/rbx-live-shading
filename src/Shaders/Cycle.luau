--!strict
--!native

--// Steps through a list of colours, blending from each into the next

local Shader = require(`../Shader`)

local def: Shader.Def = {
	Name = 'Cycle',
	Description = 'Steps through a list of colours, blending between them.',
	Order = { 'Colors', 'Speed', 'Blend', 'Brightness', 'Offset' },
	Inputs = { Index = 0 },
	Params = {
		Colors = { Kind = 'Colors', Default = { 'FF0000', '00FF00', '0000FF' }, Min = 1, Max = 6 },
		Speed = { Kind = 'Number', Default = 0.5, Min = 0.05, Max = 5, Label = 'Speed (colours/s)' },
		Blend = { Kind = 'Number', Default = 1, Min = 0, Max = 1, Label = 'Blend (share of a step)' },
		Brightness = { Kind = 'Number', Default = 1, Min = 0, Max = 1 },
		Offset = { Kind = 'Number', Default = 0, Min = 0, Max = 1, Label = 'Offset per index (colours)' },
	},

	Evaluate = function(params, inputs, time, out)
		local colors = params.Colors
		local count = #colors
		local position = (time * params.Speed + inputs.Index * params.Offset) % count
		local step = position // 1

		--// Each step holds its colour, then spends its last Blend share fading into the next
		local into = position - step
		local blend = params.Blend
		local mix = if blend > 0 then math.clamp((into - (1 - blend)) / blend, 0, 1) else 0

		out.Color = colors[step + 1]:Lerp(colors[(step + 1) % count + 1], mix)
		out.Emission = params.Brightness
	end,
}

return def
