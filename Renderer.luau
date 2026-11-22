--!strict
--!native

--// Live bindings and the one loop that draws them

local RunService = game:GetService('RunService')

local Config = require(`./Config`)
local Material = require(`./Material`)
local Profiler = require(`@game/ReplicatedStorage/Modules/Shared/Profiler`)
local Shader = require(`./Shader`)
local Writers = require(`./Writers`)

local Renderer = {}

export type Options = {
	Inputs: { [string]: number }?, -- starting inputs; the shader's defaults fill the rest
	Emissive: boolean?, -- parts glow while lit (Writers.Options)
	Anchor: BasePart?, -- what distance is measured from; the first part found among the targets otherwise
}

type Target = {
	Instance: Instance,
	Writer: Writers.Writer,
	Base: any,
	Cache: { [string]: any },
}

export type Binding = {
	Material: Material.Material,
	Shader: Shader.Shader,
	Params: { [string]: any },
	Inputs: { [string]: number },
	Targets: { Target },
	Options: Writers.Options,
	Anchor: BasePart?,
	Out: Shader.Out,

	Dirty: boolean,
	Far: boolean,
	Culled: boolean,
	NextEval: number,
	NextRange: number,
	Broken: boolean, -- its shader errored; it stays as it was until given a new material
	Alive: boolean,
}

local bindings: { [Binding]: true } = {}
local count = 0
local connection: RBXScriptConnection? = nil

local stats = { Bindings = 0, Evaluated = 0 }

--[[
	What distance is measured from: a part among the targets, or the part a light hangs off

	@param targets {Instance}
	@return BasePart?
--]]
local function anchorOf(targets: { Instance }): BasePart?
	for _, target in targets do
		if target:IsA('BasePart') then return target end
	end

	for _, target in targets do
		local parent = target.Parent

		if parent and parent:IsA('Attachment') then parent = parent.Parent end
		if parent and parent:IsA('BasePart') then return parent end
	end

	return nil
end

--[[
	Gives the binding its shader's default inputs for any it was not given

	@param binding Binding
	@return nil
--]]
local function fillInputs(binding: Binding)
	for name, default in binding.Shader.Inputs do
		if binding.Inputs[name] == nil then binding.Inputs[name] = default end
	end
end

--[[
	Evaluates one binding and writes it to its targets

	@param binding Binding
	@param time number -- server time, shared by every client
	@return nil
--]]
local function draw(binding: Binding, time: number)
	local out = binding.Out

	out.Color = nil
	out.Emission = nil
	out.Transparency = nil

	local ok, problem = pcall(binding.Shader.Evaluate :: any, binding.Params, binding.Inputs, time, out)

	if not ok then
		binding.Broken = true
		warn(`[Shading] {binding.Shader.Name} errored and was stopped - {problem}`)
		return
	end

	for _, target in binding.Targets do
		target.Writer.Write(target.Instance, out, target.Cache, target.Base, binding.Options, binding.Far)
	end

	stats.Evaluated += 1
end

--[[
	Draws every binding that is due. The loop calls this each frame; tests call it directly.

	@param time number -- server time, which patterns run on so every client shows the same frame
	@param clock number -- local clock, for rates and distance checks
	@param camera Vector3
	@return nil
--]]
function Renderer.Step(time: number, clock: number, camera: Vector3)
	stats.Evaluated = 0

	for binding in bindings do
		if clock >= binding.NextRange then
			binding.NextRange = clock + Config.RangePeriod

			local anchor = binding.Anchor

			if anchor then
				local distance = (anchor.Position - camera).Magnitude
				local far = distance > Config.LightRadius

				binding.Culled = distance > Config.CullRadius

				if far ~= binding.Far then
					binding.Far = far
					binding.Dirty = true
				end
			end
		end

		if binding.Culled or binding.Broken then continue end

		local shader = binding.Shader
		local due = binding.Dirty or (not shader.Static and clock >= binding.NextEval)

		if not due then continue end

		binding.Dirty = false
		if shader.Rate then binding.NextEval = clock + 1 / shader.Rate end

		draw(binding, time)
	end
end

local function onRender()
	Profiler.Begin('Shading')

	local camera = workspace.CurrentCamera
	Renderer.Step(workspace:GetServerTimeNow(), os.clock(), if camera then camera.CFrame.Position else Vector3.zero)

	Profiler.End()
end

--[[
	Draws a material on some instances until destroyed. Only clients draw: the loop never starts on
	the server, where a write would replicate.

	@param material Material -- sanitized (Material.Sanitize or Material.new)
	@param targets {Instance} -- parts and lights; anything no writer draws on is skipped
	@param options Options?
	@return Binding
--]]
function Renderer.Bind(material: Material.Material, targets: { Instance }, options: Options?): Binding
	local shader = Shader.Get(material.Shader)

	assert(shader, `Shading.Bind - no shader called {material.Shader}`)

	local list: { Target } = {}

	for _, instance in targets do
		local writer = Writers.For(instance)
		if not writer then continue end

		table.insert(list, { Instance = instance, Writer = writer, Base = writer.Capture(instance), Cache = {} })
	end

	local inputs = {}

	if options and options.Inputs then
		for name, value in options.Inputs do
			inputs[name] = value
		end
	end

	local clock = os.clock()

	local binding: Binding = {
		Material = material,
		Shader = shader,
		Params = Material.Decode(material),
		Inputs = inputs,
		Targets = list,
		Options = { Emissive = options ~= nil and options.Emissive == true },
		Anchor = (options and options.Anchor) or anchorOf(targets),
		Out = {},

		Dirty = true,
		Far = false,
		Culled = false,
		NextEval = 0,

		--// Staggered, so bindings made together do not all check distance on the same frame
		NextRange = clock + math.random() * Config.RangePeriod,
		Broken = false,
		Alive = true,
	}

	fillInputs(binding)

	bindings[binding] = true
	count += 1
	stats.Bindings = count

	if not connection and RunService:IsClient() then connection = RunService.RenderStepped:Connect(onRender) end

	return binding
end

--[[
	Swaps the material. A material equal to the current one changes nothing.

	@param binding Binding
	@param material Material -- sanitized
	@return nil
--]]
function Renderer.SetMaterial(binding: Binding, material: Material.Material)
	if not binding.Alive or Material.Equal(binding.Material, material) then return end

	local shader = Shader.Get(material.Shader)

	if not shader then
		warn(`[Shading] no shader called {material.Shader}; the material was not changed`)
		return
	end

	binding.Material = material
	binding.Shader = shader
	binding.Params = Material.Decode(material)
	binding.Broken = false
	binding.Dirty = true
	binding.NextEval = 0

	fillInputs(binding)
end

--[[
	Sets one input. Only a change marks the binding for redrawing, so calling this every frame with
	the same value costs a Static shader nothing.

	@param binding Binding
	@param name string
	@param value number
	@return nil
--]]
function Renderer.SetInput(binding: Binding, name: string, value: number)
	if binding.Inputs[name] == value then return end

	binding.Inputs[name] = value
	binding.Dirty = true
end

--[[
	Stops drawing and puts every target back as it was bound

	@param binding Binding
	@return nil
--]]
function Renderer.Destroy(binding: Binding)
	if not binding.Alive then return end

	binding.Alive = false
	bindings[binding] = nil
	count -= 1
	stats.Bindings = count

	for _, target in binding.Targets do
		target.Writer.Restore(target.Instance, target.Base)
	end

	table.clear(binding.Targets)

	if count == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

--[[
	How many bindings are live and how many were drawn last frame

	@return { Bindings: number, Evaluated: number }
--]]
function Renderer.Stats(): { Bindings: number, Evaluated: number }
	return stats
end

return Renderer
