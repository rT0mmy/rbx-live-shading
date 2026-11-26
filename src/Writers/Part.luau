--!strict
--!native

--// Parts: Color, Transparency and MaterialVariant, and Neon while lit when the binding is Emissive

local MaterialService = game:GetService('MaterialService')

local Common = require(`./Common`)
local Shader = require(`../Shader`)

type Base = {
	Color: Color3,
	Key: number, -- Common.Key(Color)
	Material: Enum.Material,
	MaterialVariant: string,
	Transparency: number,
}

--// Each variant name's base material, false for none; shared by every part, and forgotten when MaterialService changes
local variants: { [string]: Enum.Material | false } = {}

local function forget()
	table.clear(variants)
end

MaterialService.DescendantAdded:Connect(forget)
MaterialService.DescendantRemoving:Connect(forget)

--[[
	The base material a MaterialVariant is made for, nil when MaterialService has no such variant

	@param name string
	@return Enum.Material?
--]]
local function baseOf(name: string): Enum.Material?
	local known = variants[name]

	if known == nil then
		local variant = MaterialService:FindFirstChild(name, true)

		known = if variant and variant:IsA('MaterialVariant') then variant.BaseMaterial else false
		variants[name] = known
	end

	return known or nil
end

local Part: Common.Writer = {
	Class = 'BasePart',

	Capture = function(part: BasePart): Base
		return {
			Color = part.Color,
			Key = Common.Key(part.Color),
			Material = part.Material,
			MaterialVariant = part.MaterialVariant,
			Transparency = part.Transparency,
		}
	end,

	--// A channel the shader leaves unset shows the authored look, so nothing carries over from a previous material
	Write = function(
		part: BasePart,
		out: Shader.Out,
		cache,
		base: Base,
		options: Common.Options,
		_far: boolean,
		frame: Common.Frame
	)
		local transparency = frame.Transparency or base.Transparency

		if cache.Transparency ~= transparency then
			cache.Transparency = transparency
			part.Transparency = transparency
		end

		local color = out.Color or base.Color
		local key = frame.ColorKey or base.Key
		local material = base.Material
		local variant = out.MaterialVariant

		if variant ~= nil then
			--// A variant only shows on its own base material
			material = baseOf(variant) or material
		else
			variant = base.MaterialVariant
		end

		if cache.MaterialVariant ~= variant then
			cache.MaterialVariant = variant
			part.MaterialVariant = variant
		end

		if options.Emissive then
			local emission = frame.Emission

			if emission <= Common.DARK then
				color = base.Color
				key = base.Key
			else
				material = Enum.Material.Neon

				--// Dimmed by its key first, so a Color3 is only made when the colour really changes
				if emission < 1 then
					key = Common.Scaled(color, emission)

					if cache.Color ~= key then
						color = Color3.new(color.R * emission, color.G * emission, color.B * emission)
					end
				end
			end
		end

		if cache.Material ~= material then
			cache.Material = material
			part.Material = material
		end

		if cache.Color ~= key then
			cache.Color = key
			part.Color = color
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
