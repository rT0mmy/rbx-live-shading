--!strict
--!native

--[[
	Beams, trails and particle emitters: Color and Transparency as flat sequences, Brightness from
	Emission, and off while dark. Their authored Brightness is the brightness at full emission, and
	their authored sequences come back when a channel is unset.
--]]

local Common = require(`./Common`)
local Types = require(`../Types`)

type Effect = Beam | Trail | ParticleEmitter

type Base = { Color: ColorSequence, Transparency: NumberSequence, Brightness: number, Enabled: boolean }

--// Cache value for "showing the authored sequence"
const AUTHORED = -1

--[[
	A writer for one class of effect

	@param class string
	@return Writer
--]]
local function effect(class: string): Types.Writer
	return {
		Class = class,

		Capture = function(target: Effect): Base
			return {
				Color = target.Color,
				Transparency = target.Transparency,
				Brightness = target.Brightness,
				Enabled = target.Enabled,
			}
		end,

		Write = function(
			target: Effect,
			out: Types.Out,
			cache,
			base: Base,
			_options: Types.WriterOptions,
			_far: boolean,
			frame: Types.Frame
		)
			local emission = frame.Emission
			local enabled = base.Enabled and emission > Common.DARK

			if cache.Enabled ~= enabled then
				cache.Enabled = enabled
				target.Enabled = enabled
			end

			if not enabled then return end

			local brightness = base.Brightness * emission

			if cache.Brightness ~= brightness then
				cache.Brightness = brightness
				target.Brightness = brightness
			end

			local key = frame.ColorKey or AUTHORED

			if cache.Color ~= key then
				cache.Color = key
				target.Color = if out.Color then ColorSequence.new(out.Color) else base.Color
			end

			local transparency = frame.Transparency or AUTHORED

			if cache.Transparency ~= transparency then
				cache.Transparency = transparency
				target.Transparency = if transparency == AUTHORED
					then base.Transparency
					else NumberSequence.new(transparency)
			end
		end,

		Restore = function(target: Effect, base: Base)
			target.Color = base.Color
			target.Transparency = base.Transparency
			target.Brightness = base.Brightness
			target.Enabled = base.Enabled
		end,
	}
end

return effect
