--!strict
--!native

local Shader = require(`../Shader`)

local Common = {}

export type Options = {
	Emissive: boolean, -- parts glow (Neon) while lit, and show their authored look when not
}

export type Writer = {
	Class: string, -- matched with IsA, in registration order
	Capture: (target: any) -> any,
	Write: (target: any, out: Shader.Out, cache: { [string]: any }, base: any, options: Options, far: boolean) -> (),
	Restore: (target: any, base: any) -> (),
}

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
	Emission clamped and rounded to one of LEVELS steps

	@param emission number
	@return number
--]]
function Common.Level(emission: number): number
	return math.round(math.clamp(emission, 0, 1) * LEVELS) / LEVELS
end

return Common
