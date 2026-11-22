--!strict
--!native

--// Two groups taking turns, each in its own colour

local Shader = require(`../Shader`)

local def: Shader.Def = {
	Name = 'Alternate',
	Description = 'Two groups taking turns, each in its own colour.',
	Order = { 'Color', 'Color2', 'Speed', 'Fade', 'Brightness' },
	Inputs = { Group = 0 },
	Params = {
		Color = { Kind = 'Color', Default = 'FF0000', Label = 'Group 1 colour' },
		Color2 = { Kind = 'Color', Default = '0000FF', Label = 'Group 2 colour' },
		Speed = { Kind = 'Number', Default = 1, Min = 0.1, Max = 6, Label = 'Speed (swaps/s)' },
		Fade = { Kind = 'Number', Default = 0, Min = 0, Max = 1, Label = 'Fade (share of a turn)' },
		Brightness = { Kind = 'Number', Default = 1, Min = 0, Max = 1 },
	},

	Evaluate = function(params, inputs, time, out)
		local second = inputs.Group % 2 == 1

		--// One turn per swap: group 1 holds the first half of a cycle, group 2 the second
		local phase = ((time * params.Speed * 0.5) % 1) * 2
		local turn = if second then (phase + 1) % 2 else phase

		local lit = 0

		if turn < 1 then
			local fade = params.Fade * 0.5
			lit = if fade > 0 then math.min(1, turn / fade, (1 - turn) / fade) else 1
		end

		out.Color = if second then params.Color2 else params.Color
		out.Emission = params.Brightness * lit
	end,
}

return def
