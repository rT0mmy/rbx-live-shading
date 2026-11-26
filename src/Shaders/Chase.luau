--!strict
--!native

--// A lit head running through the bindings in Index order, with a fading tail

local Shader = require(`../Shader`)

local def: Shader.Def = {
	Name = 'Chase',
	Description = 'Light running round in order, with a fading tail.',
	Order = { 'Color', 'Speed', 'Tail', 'Reverse', 'Brightness' },
	Inputs = { Index = 0, Count = 1 },
	Params = {
		Color = { Kind = 'Color', Default = 'FFFFFF' },
		Speed = { Kind = 'Number', Default = 0.5, Min = 0.05, Max = 4, Label = 'Speed (laps/s)' },
		Tail = { Kind = 'Number', Default = 0.5, Min = 0, Max = 1, Label = 'Tail (share of a lap)' },
		Reverse = { Kind = 'Bool', Default = false },
		Brightness = { Kind = 'Number', Default = 1, Min = 0, Max = 1 },
	},

	Evaluate = function(params, inputs, time, out)
		local count = math.max(inputs.Count, 1)
		local head = ((time * params.Speed) % 1) * count
		local index = if params.Reverse then count - 1 - inputs.Index else inputs.Index

		--// How far the head has gone past this one, in bindings
		local behind = (head - index) % count
		local tail = params.Tail * (count - 1)

		local lit = if behind < 1 then 1 elseif tail > 0 then math.max(0, 1 - (behind - 1) / tail) else 0

		out.Color = params.Color
		out.Emission = params.Brightness * lit
	end,
}

return def
