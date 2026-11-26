--!strict
--!native

local Shader = require(`../Shader`)
local Types = require(`../Types`)

local Common = {}

export type Options = Types.WriterOptions
export type Frame = Types.Frame -- Emission is Level(out.Emission), Transparency Level(out.Transparency), ColorKey Key(out.Color)
export type Writer = Types.Writer

--// Emission at or under this is off
Common.DARK = 0.004

--// Emission steps, so a slow fade is not a write every frame
const LEVELS = 128

--[[
	A colour as one comparable number, 8 bits a channel

	@param color Color3
	@return number
--]]
function Common.Key(color: Color3): number
	return math.round(color.R * 255) * 65536 + math.round(color.G * 255) * 256 + math.round(color.B * 255)
end

--[[
	The key of a colour dimmed towards black, without making the Color3

	@param color Color3
	@param scale number -- 0..1
	@return number
--]]
function Common.Scaled(color: Color3, scale: number): number
	scale *= 255

	return math.round(color.R * scale) * 65536 + math.round(color.G * scale) * 256 + math.round(color.B * scale)
end

--[[
	Emission clamped and rounded to one of LEVELS steps

	@param emission number
	@return number
--]]
function Common.Level(emission: number): number
	return math.round(math.clamp(emission, 0, 1) * LEVELS) / LEVELS
end

--[[
	Fills a frame from an output

	@param out Out
	@param frame Frame
	@return Frame
--]]
function Common.Prepare(out: Shader.Out, frame: Frame): Frame
	local color = out.Color
	local transparency = out.Transparency

	frame.Emission = Common.Level(out.Emission or 1)
	frame.Transparency = if transparency ~= nil then Common.Level(transparency) else nil
	frame.ColorKey = if color then Common.Key(color) else nil

	return frame
end

return Common
