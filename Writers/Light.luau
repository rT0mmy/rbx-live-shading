--!strict
--!native

--// Point, spot and surface lights. A light's authored Brightness is its brightness at full emission.

local Common = require(`./Common`)
local Shader = require(`../Shader`)

type Base = { Color: Color3, Brightness: number, Enabled: boolean }

local Light: Common.Writer = {
	Class = 'Light',

	Capture = function(light: Light): Base
		return { Color = light.Color, Brightness = light.Brightness, Enabled = light.Enabled }
	end,

	Write = function(light: Light, out: Shader.Out, cache, base: Base, _options: Common.Options, far: boolean)
		local emission = Common.Level(out.Emission or 1)
		local enabled = base.Enabled and not far and emission > Common.DARK

		if cache.Enabled ~= enabled then
			cache.Enabled = enabled
			light.Enabled = enabled
		end

		if not enabled then return end

		local brightness = base.Brightness * emission

		if cache.Brightness ~= brightness then
			cache.Brightness = brightness
			light.Brightness = brightness
		end

		local color = out.Color

		if color then
			local packed = Common.Key(color)

			if cache.Color ~= packed then
				cache.Color = packed
				light.Color = color
			end
		end
	end,

	Restore = function(light: Light, base: Base)
		light.Color = base.Color
		light.Brightness = base.Brightness
		light.Enabled = base.Enabled
	end,
}

return Light
