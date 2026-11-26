--!strict
--!native

--// Colours spread across the bindings in Index order, held or scrolling

local Shader = require(`../Shader`)

local def: Shader.Def = {
	Name = 'Gradient',
	Description = 'Colours spread along a row in Index order, held or scrolling. Best with PerTarget.',
	Order = { 'Colors', 'Mode', 'Speed', 'Brightness' },
	Inputs = { Index = 0, Count = 1 },
	Params = {
		Colors = { Kind = 'Colors', Default = { 'FF0000', 'FFFF00', '00FF00', '00FFFF', '0000FF' }, Min = 2, Max = 8 },
		Mode = { Kind = 'Choice', Default = 'Scroll', Options = { 'Fixed', 'Scroll' } },
		Speed = { Kind = 'Number', Default = 0.2, Min = 0.01, Max = 2, Label = 'Speed (lengths/s)' },
		Brightness = { Kind = 'Number', Default = 1, Min = 0, Max = 1 },
	},

	Evaluate = function(params, inputs, time, out)
		local colors = params.Colors
		local n = #colors
		local count = math.max(inputs.Count, 1)
		local position

		if params.Mode == 'Fixed' then
			--// The first colour on the first, the last on the last
			position = if count > 1 then math.clamp(inputs.Index / (count - 1), 0, 1) * (n - 1) else 0
		else
			--// The whole list once along the row, wrapping from the last colour into the first
			position = ((inputs.Index / count + time * params.Speed) % 1) * n
		end

		local step = position // 1
		local from = colors[step % n + 1]
		local into = colors[(step + 1) % n + 1]

		out.Color = from:Lerp(into, position - step)
		out.Emission = params.Brightness
	end,
}

return def
