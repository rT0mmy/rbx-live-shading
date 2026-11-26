--!strict
--!native

--// Point, spot and surface lights. A light's authored Brightness is its brightness at full emission.

local Common = require(`./Common`)
local Shader = require(`../Shader`)

type Base = { Color: Color3, Key: number, Brightness: number, Enabled: boolean }

local Light: Common.Writer = {
	Class = 'Light',

	Capture = function(light: Light): Base
		return {
			Color = light.Color,
			Key = Common.Key(light.Color),
			Brightness = light.Brightness,
			Enabled = light.Enabled,
		}
	end,

	Write = function(
		light: Light,
		out: Shader.Out,
		cache,
		base: Base,
		_options: Common.Options,
		far: boolean,
		frame: Common.Frame
	)
		local emission = frame.Emission
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

		--// Unset, the light shows its authored colour rather than the last material's
		local key = frame.ColorKey or base.Key

		if cache.Color ~= key then
			cache.Color = key
			light.Color = out.Color or base.Color
		end
	end,

	Restore = function(light: Light, base: Base)
		light.Color = base.Color
		light.Brightness = base.Brightness
		light.Enabled = base.Enabled
	end,
}

return Light
