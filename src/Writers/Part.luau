--!strict
--!native

--// Parts: Color, Transparency and MaterialVariant, and Neon while lit when the binding is Emissive

local MaterialService = game:GetService('MaterialService')

local Common = require(`./Common`)
local Shader = require(`../Shader`)

type Base = { Color: Color3, Material: Enum.Material, MaterialVariant: string, Transparency: number }

--[[
	The base material a MaterialVariant is made for, nil when MaterialService has no such variant

	@param name string
	@return Enum.Material?
--]]
local function baseOf(name: string): Enum.Material?
	local variant = MaterialService:FindFirstChild(name, true)

	return if variant and variant:IsA('MaterialVariant') then variant.BaseMaterial else nil
end

local Part: Common.Writer = {
	Class = 'BasePart',

	Capture = function(part: BasePart): Base
		return {
			Color = part.Color,
			Material = part.Material,
			MaterialVariant = part.MaterialVariant,
			Transparency = part.Transparency,
		}
	end,

	Write = function(part: BasePart, out: Shader.Out, cache, base: Base, options: Common.Options)
		if out.Transparency ~= nil then
			local transparency = Common.Level(out.Transparency)

			if cache.Transparency ~= transparency then
				cache.Transparency = transparency
				part.Transparency = transparency
			end
		end

		local color = out.Color
		local material = base.Material
		local variant = out.MaterialVariant

		if variant ~= nil then
			if cache.Variant ~= variant then
				cache.Variant = variant
				cache.VariantBase = baseOf(variant) or false
				part.MaterialVariant = variant
			end

			--// A variant only shows on its own base material
			if cache.VariantBase then material = cache.VariantBase end
		end

		if options.Emissive then
			local emission = Common.Level(out.Emission or 1)

			if emission <= Common.DARK then
				color = base.Color
			else
				material = Enum.Material.Neon
				color = (color or base.Color):Lerp(Color3.new(), 1 - emission)
			end
		end

		if cache.Material ~= material then
			cache.Material = material
			part.Material = material
		end

		if color then
			local packed = Common.Key(color)

			if cache.Color ~= packed then
				cache.Color = packed
				part.Color = color
			end
		end
	end,

	Restore = function(part: BasePart, base: Base)
		part.Color = base.Color
		part.Material = base.Material
		part.MaterialVariant = base.MaterialVariant
		part.Transparency = base.Transparency
	end,
}

return Part
