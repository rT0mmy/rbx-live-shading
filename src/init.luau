--!strict
--!native

--[[
Shaders and materials for instances

local Glow = Shading.Shader {
       Name = 'Glow',
       Params = {
           Color = { Kind = 'Color', Default = 'FFFFFF' },
           Speed = { Kind = 'Number', Default = 1, Min = 0.1, Max = 4 },
       },
       Inputs = { Index = 0 },
       Evaluate = function(params, inputs, time, out)
           out.Color = params.Color
           out.Emission = 0.5 + 0.5 * math.sin(((time * params.Speed + inputs.Index * 0.25) % 1) * 2 * math.pi)
       end,
   }

   local material = Shading.Material('Glow', { Color = 'FF00AA' })
   local binding = Shading.Bind(material, { strip, strip.SurfaceLight }, { Emissive = true, Inputs = { Index = 2 } })
   binding:SetInput('Index', 3)
   binding:SetMaterial(Shading.Material('Rainbow'))
   binding:Destroy()
]]

local Config = require(`@self/Config`)
local Group = require(`@self/Group`)
local Material = require(`@self/Material`)
local Param = require(`@self/Param`)
local Renderer = require(`@self/Renderer`)
local Shader = require(`@self/Shader`)
local Types = require(`@self/Types`)
local Wire = require(`@self/Wire`)
local Writers = require(`@self/Writers`)

local Shading = {}

--// The same types as Shading.Types, which can be required alone
export type Kind = Types.Kind
export type ParamSpec = Types.ParamSpec
export type Out = Types.Out
export type Evaluate = Types.Evaluate
export type ShaderDef = Types.ShaderDef
export type Shader = Types.Shader
export type Material = Types.Material
export type WriterOptions = Types.WriterOptions
export type Frame = Types.Frame
export type Writer = Types.Writer
export type Options = Types.Options
export type Binding = Types.Binding
export type GroupOptions = Types.GroupOptions
export type Group = Types.Group
export type Stats = Types.Stats

Shading.Config = Config

--// Shaders and materials

Shading.Shader = Shader.Define
Shading.Get = Shader.Get
Shading.Names = Shader.Names

Shading.Material = Material.new
Shading.Sanitize = Material.Sanitize
Shading.Equal = Material.Equal
Shading.Decode = Material.Decode
Shading.Hex = Param.Hex

--// Materials as compact buffers for remotes and saved data
Shading.Pack = Wire.Pack
Shading.Unpack = Wire.Unpack

--[[
	A material's output at one moment, without drawing it anywhere: for previews and tests

	@param material Material -- sanitized
	@param inputs {[string]: number}? -- the shader's defaults fill the rest
	@param time number
	@return Out
--]]
function Shading.Evaluate(material: Material, inputs: { [string]: number }?, time: number): Out
	local shader = Shader.Get(material.Shader)
	local out = {}

	if not shader then return out end

	local merged = {}

	for name, default in shader.Inputs do
		merged[name] = if inputs and inputs[name] ~= nil then inputs[name] else default
	end

	shader.Evaluate(Material.Decode(material), merged, time, out)

	return out
end

--[[
	Writes a material onto instances once

	@param material Material -- sanitized
	@param targets {Instance} -- parts and lights; anything no writer draws on is skipped
	@param options Options?
	@param time number? -- 0 by default
	@return nil
--]]
function Shading.Apply(material: Material, targets: { Instance }, options: Options?, time: number?)
	local out = Shading.Evaluate(material, nil, time or 0)
	local written = { Emissive = options ~= nil and options.Emissive == true }
	local frame = Writers.Prepare(out, { Emission = 1 })

	for _, target in targets do
		local writer = Writers.For(target)
		if writer then writer.Write(target, out, {}, writer.Capture(target), written, false, frame) end
	end
end

--// Bindings

--[[
	Draws a material on some instances until destroyed. The binding has SetMaterial, SetInput, Edit
	and Destroy.

	@param material Material -- sanitized (Shading.Material or Shading.Sanitize)
	@param targets {Instance} -- parts and lights; anything no writer draws on is skipped
	@param options Options?
	@return Binding
--]]
Shading.Bind = (Renderer.Bind :: any) :: (material: Material, targets: { Instance }, options: Options?) -> Binding

--// One binding per member of a tag or a CollectionService query, for as long as it is one
Shading.BindTag = Group.Tag
Shading.BindQuery = Group.Query

--[[
	Adds a writer for another class of instance (see Writers/)

	@param writer Writer
	@return nil
--]]
Shading.Writer = Writers.Register

Shading.Stats = Renderer.Stats
Shading.Step = Renderer.Step

for _, def in require(`@self/Shaders`) do
	Shader.Define(def)
end

return Shading
