--!strict
--!native

--[[
	Decals and textures: Color3 tints with Color, Transparency as given. On an Emissive binding the
	tint dims with Emission, as a lit part does.
--]]

local Common = require(`./Common`)
local Types = require(`../Types`)

type Base = { Color3: Color3, Key: number, Transparency: number }

local Decal: Types.Writer = {
	Class = 'Decal',

	Capture = function(decal: Decal): Base
		return { Color3 = decal.Color3, Key = Common.Key(decal.Color3), Transparency = decal.Transparency }
	end,

	Write = function(
		decal: Decal,
		out: Types.Out,
		cache,
		base: Base,
		options: Types.WriterOptions,
		_far: boolean,
		frame: Types.Frame
	)
		local transparency = frame.Transparency or base.Transparency

		if cache.Transparency ~= transparency then
			cache.Transparency = transparency
			decal.Transparency = transparency
		end

		local color = out.Color or base.Color3
		local key = frame.ColorKey or base.Key
		local emission = frame.Emission

		if options.Emissive and emission < 1 then
			key = Common.Scaled(color, emission)

			if cache.Color ~= key then
				color = Color3.new(color.R * emission, color.G * emission, color.B * emission)
			end
		end

		if cache.Color ~= key then
			cache.Color = key
			decal.Color3 = color
		end
	end,

	Restore = function(decal: Decal, base: Base)
		decal.Color3 = base.Color3
		decal.Transparency = base.Transparency
	end,
}

return Decal
