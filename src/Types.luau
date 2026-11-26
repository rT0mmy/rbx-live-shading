--!strict

--[[
	Every public type and nothing else: require this module alone to annotate code without loading the
	library, e.g. a server script that only builds materials, or a plugin.

	local Types = require(ReplicatedStorage.Shading.Types)
	local function paint(material: Types.Material) ... end
--]]

--// ---------------------------------------------------------------- Params

export type Kind = 'Number' | 'Color' | 'Colors' | 'Bool' | 'Choice'

--[[ a shader's parameter
	@Number     { Default, Min, Max, Step? }       number
	@Color      { Default }                        'RRGGBB' -> Color3
	@Colors     { Default, Min?, Max? }            {'RRGGBB'} -> {Color3}
	@Bool       { Default }                        boolean
	@Choice     { Default, Options }               one of Options
--]]
export type ParamSpec = {
	Kind: Kind,
	Default: any,
	Min: number?, -- Number: lowest value; Colors: fewest colours
	Max: number?, -- Number: highest value; Colors: most colours
	Step: number?, -- Number: values snap to multiples of it
	Options: { string }?, -- Choice
	Label: string?, -- for an editor; the param's name otherwise
}

--// ---------------------------------------------------------------- Shaders

--// What a shader works out; the writers put it onto instances
export type Out = {
	Color: Color3?,
	Emission: number?, -- 0..1: how lit; drives Neon on emissive parts and light brightness
	Transparency: number?, -- 0..1
	MaterialVariant: string?, -- a MaterialVariant under MaterialService; the part takes its base material
}

export type Evaluate = (params: { [string]: any }, inputs: { [string]: number }, time: number, out: Out) -> ()

export type ShaderDef = {
	Name: string,
	Description: string?,
	Params: { [string]: ParamSpec }?,
	Order: { string }?, -- params in the order an editor lists them; alphabetical otherwise
	Inputs: { [string]: number }?, -- per-binding inputs it reads, and their defaults
	Static: boolean?, -- the output never changes with time, so it is worked out only when something it reads does
	Rate: number?, -- evaluations per second at most; every frame when nil
	Evaluate: Evaluate,
}

export type Shader = {
	Name: string,
	Description: string,
	Params: { [string]: ParamSpec },
	Order: { string },
	Inputs: { [string]: number },
	Static: boolean,
	Rate: number?,
	Evaluate: Evaluate,
}

--// ---------------------------------------------------------------- Materials

export type Material = {
	Shader: string,
	Params: { [string]: any }, -- clean data: numbers, booleans, option names, 'RRGGBB' colours
}

--// ---------------------------------------------------------------- Writers

export type WriterOptions = {
	Emissive: boolean, -- parts glow (Neon) while lit, and show their authored look when not
}

--// An output worked out once per draw for every target: levelled and packed, so writers compare numbers
export type Frame = {
	Emission: number, -- levelled Emission, 1 when unset
	Transparency: number?, -- levelled Transparency, nil when unset
	ColorKey: number?, -- Color packed to one number, nil when unset
}

export type Writer = {
	Class: string, -- matched with IsA; later registrations are tried first
	Capture: (target: any) -> any,
	Write: (
		target: any,
		out: Out,
		cache: { [string]: any },
		base: any,
		options: WriterOptions,
		far: boolean,
		frame: Frame
	) -> (),
	Restore: (target: any, base: any) -> (),
}

--// ---------------------------------------------------------------- Bindings

export type Options = {
	Inputs: { [string]: number }?, -- starting inputs; the shader's defaults fill the rest
	Emissive: boolean?, -- parts glow while lit
	Anchor: BasePart?, -- what distance is measured from; the first part found among the targets otherwise
	PerTarget: boolean?, -- each target is evaluated on its own, with Index and Count filled in
	TimeScale: number?, -- the shader's clock runs this much faster; 1 by default
	TimeOffset: number?, -- seconds added to the shader's clock; 0 by default
}

export type Binding = {
	Material: Material,
	Inputs: { [string]: number },
	Broken: boolean, -- its shader errored; it stays as it was until given a new material
	Alive: boolean,

	SetMaterial: (self: Binding, material: Material) -> (),
	SetInput: (self: Binding, name: string, value: number) -> (),
	Edit: (self: Binding, edit: () -> ()) -> (),
	Destroy: (self: Binding) -> (),
}

export type GroupOptions = {
	Inputs: { [string]: number }?,
	Emissive: boolean?,
	PerTarget: boolean?,
	TimeScale: number?,
	TimeOffset: number?,
	Descendants: boolean?, -- a member's descendants are drawn on as well as itself; true by default
	Root: Instance?, -- only members under it count; Workspace by default
	OnAdded: ((instance: Instance, binding: Binding) -> ())?, -- per member as it joins. Cannot yield.
}

export type Group = {
	Material: Material,
	Alive: boolean,

	SetMaterial: (self: Group, material: Material) -> (),
	SetInput: (self: Group, name: string, value: number) -> (),
	Get: (self: Group, instance: Instance) -> Binding?,
	Destroy: (self: Group) -> (),
}

export type Stats = {
	Bindings: number,
	Evaluated: number, -- last frame
	Written: number, -- targets written to last frame
}

return {}
