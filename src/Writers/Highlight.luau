--!strict
--!native

--[[
	Highlights: fill and outline take Color, and fade out as Emission falls, from their authored
	transparency at full emission to invisible at none. Transparency, when set, is the fill's own.
--]]

local Common = require(`./Common`)
local Types = require(`../Types`)

type Base = {
	FillColor: Color3,
	FillKey: number,
	OutlineColor: Color3,
	OutlineKey: number,
	FillTransparency: number,
	OutlineTransparency: number,
	Enabled: boolean,
}

local Highlight: Types.Writer = {
	Class = 'Highlight',

	Capture = function(highlight: Highlight): Base
		return {
			FillColor = highlight.FillColor,
			FillKey = Common.Key(highlight.FillColor),
			OutlineColor = highlight.OutlineColor,
			OutlineKey = Common.Key(highlight.OutlineColor),
			FillTransparency = highlight.FillTransparency,
			OutlineTransparency = highlight.OutlineTransparency,
			Enabled = highlight.Enabled,
		}
	end,

	Write = function(
		highlight: Highlight,
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
			highlight.Enabled = enabled
		end

		if not enabled then return end

		local fill = frame.Transparency or 1 - (1 - base.FillTransparency) * emission
		local outline = 1 - (1 - base.OutlineTransparency) * emission

		if cache.Fill ~= fill then
			cache.Fill = fill
			highlight.FillTransparency = fill
		end

		if cache.Outline ~= outline then
			cache.Outline = outline
			highlight.OutlineTransparency = outline
		end

		local color = out.Color
		local fillKey = frame.ColorKey or base.FillKey
		local outlineKey = frame.ColorKey or base.OutlineKey

		if cache.FillColor ~= fillKey then
			cache.FillColor = fillKey
			highlight.FillColor = color or base.FillColor
		end

		if cache.OutlineColor ~= outlineKey then
			cache.OutlineColor = outlineKey
			highlight.OutlineColor = color or base.OutlineColor
		end
	end,

	Restore = function(highlight: Highlight, base: Base)
		highlight.FillColor = base.FillColor
		highlight.OutlineColor = base.OutlineColor
		highlight.FillTransparency = base.FillTransparency
		highlight.OutlineTransparency = base.OutlineTransparency
		highlight.Enabled = base.Enabled
	end,
}

return Highlight
