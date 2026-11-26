--!strict
--!native

--// Live bindings and the one loop that draws them

local RunService = game:GetService('RunService')

local Config = require(`./Config`)
local Material = require(`./Material`)
local Shader = require(`./Shader`)
local Types = require(`./Types`)
local Writers = require(`./Writers`)

local Renderer = {}

export type Options = Types.Options
export type Stats = Types.Stats

--// What a slot's targets show, for telling when a new output would change nothing
type Shown = {
	Far: boolean,
	Emission: number,
	ColorKey: number?,
	Transparency: number?,
	Variant: string?,
	Extra: { [string]: any }, -- Out's keys past the built-in channels, for a game's own writers
}

--// One evaluation's worth of targets: all of a binding's, or with PerTarget, one
type Slot = {
	Targets: { Target },
	Index: number, -- PerTarget: the Index input, the target's place in the list it was bound with
	Out: Types.Out,
	Frame: Types.Frame, -- Out levelled and packed, once a draw
	Shown: Shown,
	Drawn: boolean, -- Out holds a whole evaluation that the targets show
}

type Target = {
	Instance: Instance,
	Writer: Types.Writer,
	Base: any,
	Cache: { [string]: any },
	Connection: RBXScriptConnection, -- Destroying
	Slot: Slot,
}

export type Binding = {
	Material: Material.Material,
	Shader: Shader.Shader,
	Params: { [string]: any },
	Inputs: { [string]: number },
	Targets: { Target },
	Slots: { Slot },
	Options: Types.WriterOptions,
	Anchor: BasePart?,
	AnchorConnection: RBXScriptConnection?, -- the anchor's Destroying

	PerTarget: boolean,
	Count: number, -- PerTarget: the Count input
	TimeScale: number,
	TimeOffset: number,

	--// Inputs that fill themselves in, by whether the shader declares them
	ReadsPosition: boolean, -- X, Y, Z
	ReadsDistance: boolean, -- Distance
	ReadsLoudness: boolean, -- Loudness

	Dirty: boolean,
	Far: boolean,
	Culled: boolean,
	Lights: boolean, -- has a light among its targets, which lights what is on screen from behind the camera
	Position: Vector3?, -- the anchor's, at the last distance check
	NextEval: number,
	NextRange: number,
	Broken: boolean, -- its shader errored; it stays as it was until given a new material
	Alive: boolean,
	Place: number, -- its index in the list
}

--// Live bindings as a list, so a frame over budget can stop and the next carry on from there
local list: { Binding } = {}
local cursor = 1
local connection: RBXScriptConnection? = nil

local stats: Stats = { Bindings = 0, Evaluated = 0, Written = 0 }

--// Out's channels the frame covers; any other key is compared as it is
const CHANNELS = { Color = true, Emission = true, Transparency = true, MaterialVariant = true }

--// Methods on a binding, filled in at the bottom
local BindingClass = {}
BindingClass.__index = BindingClass

--[[
	What distance is measured from: a part among the targets, or the part a light hangs off

	@param targets {Target}
	@param except Instance? -- one being destroyed, which cannot be the anchor
	@return BasePart?
--]]
local function anchorOf(targets: { Target }, except: Instance?): BasePart?
	for _, target in targets do
		local instance = target.Instance
		if instance ~= except and instance:IsA('BasePart') then return instance :: BasePart end
	end

	for _, target in targets do
		local parent = target.Instance.Parent

		if parent and parent:IsA('Attachment') then parent = parent.Parent end
		if parent and parent ~= except and parent:IsA('BasePart') then return parent end
	end

	return nil
end

--[[
	Where a target is, for the X, Y and Z inputs: a part's position, or the attachment or part it
	hangs off

	@param instance Instance
	@return Vector3?
--]]
local function positionOf(instance: Instance): Vector3?
	if instance:IsA('BasePart') then return instance.Position end

	local parent = instance.Parent

	if parent and parent:IsA('Attachment') then return parent.WorldPosition end
	if parent and parent:IsA('BasePart') then return parent.Position end

	return nil
end

local setAnchor: (binding: Binding, anchor: BasePart?) -> ()

--[[
	Picks a new anchor when the old one is destroyed. With none left, the binding is always in range.

	@param binding Binding
	@param gone Instance -- the anchor being destroyed
	@return nil
--]]
local function reanchor(binding: Binding, gone: Instance)
	if not binding.Alive or binding.Anchor ~= gone then return end

	setAnchor(binding, anchorOf(binding.Targets, gone))

	if not binding.Anchor then
		binding.Culled = false
		binding.Position = nil

		if binding.Far then
			binding.Far = false
			binding.Dirty = true
		end
	end
end

function setAnchor(binding: Binding, anchor: BasePart?)
	if binding.AnchorConnection then binding.AnchorConnection:Disconnect() end

	binding.Anchor = anchor
	binding.AnchorConnection = if anchor
		then anchor.Destroying:Connect(function()
			reanchor(binding, anchor)
		end)
		else nil

	--// Checked on the next frame rather than left with the old anchor's distance
	binding.NextRange = 0
end

--[[
	Removes one item from a list, the last taking its place

	@param items {any}
	@param item any
	@return boolean -- whether it was there
--]]
local function remove(items: { any }, item: any): boolean
	local index = table.find(items, item)

	if not index then return false end

	items[index] = items[#items]
	items[#items] = nil

	return true
end

--[[
	Forgets a target that is being destroyed, so it is not written to or kept alive. A binding left
	with no targets destroys itself.

	@param binding Binding
	@param target Target
	@return nil
--]]
local function drop(binding: Binding, target: Target)
	if not remove(binding.Targets, target) then return end

	target.Connection:Disconnect()

	--// A shared slot's list is the binding's own, so only a PerTarget slot is left to go
	if binding.PerTarget then remove(binding.Slots, target.Slot) end

	if #binding.Targets == 0 then
		Renderer.Destroy(binding)
	elseif binding.Anchor == target.Instance then
		reanchor(binding, target.Instance)
	end
end

--[[
	Writes a slot's output to its targets, and notes what they now show

	@param binding Binding
	@param slot Slot
	@return nil
--]]
local function write(binding: Binding, slot: Slot)
	local out, frame, options, far = slot.Out, slot.Frame, binding.Options, binding.Far

	for _, target in slot.Targets do
		target.Writer.Write(target.Instance, out, target.Cache, target.Base, options, far, frame)
	end

	stats.Written += #slot.Targets

	local shown = slot.Shown

	shown.Far = far
	shown.Emission = frame.Emission
	shown.ColorKey = frame.ColorKey
	shown.Transparency = frame.Transparency
	shown.Variant = out.MaterialVariant

	table.clear(shown.Extra)

	for key, value in out do
		if not CHANNELS[key] then shown.Extra[key] = value end
	end

	slot.Drawn = true
end

--[[
	Whether a slot's targets already show its current output, levelled as the writers level it

	@param binding Binding
	@param slot Slot
	@return boolean
--]]
local function unchanged(binding: Binding, slot: Slot): boolean
	local out, frame, shown = slot.Out, slot.Frame, slot.Shown

	if
		shown.Far ~= binding.Far
		or shown.Emission ~= frame.Emission
		or shown.ColorKey ~= frame.ColorKey
		or shown.Transparency ~= frame.Transparency
		or shown.Variant ~= out.MaterialVariant
	then
		return false
	end

	local extra = shown.Extra

	for key, value in out do
		if not CHANNELS[key] and extra[key] ~= value then return false end
	end

	for key in extra do
		if out[key] == nil then return false end
	end

	return true
end

--[[
	Gives the binding its shader's default inputs for any it was not given, and notes which inputs
	fill themselves in

	@param binding Binding
	@return nil
--]]
local function fillInputs(binding: Binding)
	local declared = binding.Shader.Inputs

	for name, default in declared do
		if binding.Inputs[name] == nil then binding.Inputs[name] = default end
	end

	binding.ReadsPosition = declared.X ~= nil or declared.Y ~= nil or declared.Z ~= nil
	binding.ReadsDistance = declared.Distance ~= nil
	binding.ReadsLoudness = declared.Loudness ~= nil
end

--[[
	Evaluates a binding, once or once a target, and writes what changed

	@param binding Binding
	@param time number -- server time, shared by every client
	@return nil
--]]
local function draw(binding: Binding, time: number)
	local evaluate = binding.Shader.Evaluate :: any
	local params, inputs = binding.Params, binding.Inputs
	local perTarget, readsPosition = binding.PerTarget, binding.ReadsPosition
	local position: Vector3? = nil

	time = time * binding.TimeScale + binding.TimeOffset

	if readsPosition and not perTarget then
		local anchor = binding.Anchor
		position = if anchor then anchor.Position else nil
	end

	for _, slot in binding.Slots do
		if perTarget then
			inputs.Index = slot.Index
			inputs.Count = binding.Count

			if readsPosition then position = positionOf(slot.Targets[1].Instance) or binding.Position end
		end

		if position then
			inputs.X = position.X
			inputs.Y = position.Y
			inputs.Z = position.Z
		end

		local out = slot.Out
		table.clear(out)

		local ok, err = pcall(evaluate, params, inputs, time, out)

		if not ok then
			binding.Broken = true
			slot.Drawn = false
			warn(`[Shading] {binding.Shader.Name} errored and was stopped - {err}`)
			return
		end

		stats.Evaluated += 1
		Writers.Prepare(out, slot.Frame)

		--// A slow fade between levels, a held colour, a dark gap: no target would change
		if not (slot.Drawn and unchanged(binding, slot)) then write(binding, slot) end
	end
end

--[[
	Checks a binding's distance from the camera

	@param binding Binding
	@param camera Vector3
	@return nil
--]]
local function range(binding: Binding, camera: Vector3)
	local anchor = binding.Anchor

	if not anchor then return end

	local position = anchor.Position
	local distance = (position - camera).Magnitude
	local far = distance > Config.LightRadius
	local static = binding.Shader.Static

	binding.Position = position
	binding.Culled = distance > Config.CullRadius

	if far ~= binding.Far then
		binding.Far = far
		binding.Dirty = true
	end

	if binding.ReadsDistance and binding.Inputs.Distance ~= distance then
		binding.Inputs.Distance = distance
		if static then binding.Dirty = true end
	end

	--// Positions are read as it draws; a Static shader is drawn again for them as often as this runs
	if binding.ReadsPosition and static then binding.Dirty = true end
end

--[[
	Draws every binding that is due. The loop calls this each frame; tests call it directly.

	@param time number -- server time, which patterns run on so every client shows the same frame
	@param clock number -- local clock, for rates and distance checks
	@param camera Vector3
	@param look Vector3? -- the camera's LookVector; without it nothing is held for being behind
	@return nil
--]]
function Renderer.Step(time: number, clock: number, camera: Vector3, look: Vector3?)
	stats.Evaluated = 0
	stats.Written = 0

	local total = #list

	if total == 0 then return end

	local budget = Config.Budget
	local farRate = Config.FarRate
	local behind = if Config.ViewCull and look then -Config.ViewMargin else nil
	local loudness = if Config.Loudness then math.clamp(Config.Loudness(), 0, 1) else nil

	if cursor > total then cursor = 1 end

	local start = cursor

	for offset = 0, total - 1 do
		local index = (start + offset - 1) % total + 1
		local binding = list[index]

		--// Destroyed during this frame, by a Destroying that a write set off
		if not binding then continue end

		--// Over budget: the frame ends here, and the next starts with this binding
		if budget and stats.Written >= budget then
			cursor = index
			return
		end

		if clock >= binding.NextRange then
			--// The first check is straight away, so nothing out of range is drawn lit first. Later ones
			--// are staggered, so bindings made together do not all check on the same frame.
			binding.NextRange = clock + Config.RangePeriod * (if binding.NextRange == 0 then math.random() else 1)
			range(binding, camera)
		end

		if loudness and binding.ReadsLoudness and binding.Inputs.Loudness ~= loudness then
			binding.Inputs.Loudness = loudness
			if binding.Shader.Static then binding.Dirty = true end
		end

		if binding.Culled or binding.Broken then continue end

		local shader = binding.Shader
		local due = binding.Dirty or (not shader.Static and clock >= binding.NextEval)

		if not due then continue end

		--// Behind the camera, by where its anchor was at the last distance check. One with a light
		--// still on is drawn anyway, as it lights what is on screen.
		local position = binding.Position

		if behind and position and (binding.Far or not binding.Lights) then
			if (position - camera):Dot(look :: Vector3) < behind then continue end
		end

		local rate = shader.Rate

		if binding.Far and farRate and (not rate or farRate < rate) then rate = farRate end

		binding.Dirty = false

		--// The first wait is a random share of a period, so bindings made together spread out
		if rate then binding.NextEval = clock + (if binding.NextEval == 0 then math.random() else 1) / rate end

		draw(binding, time)
	end
end

local function onRender()
	Config.Profiler.Begin('Shading')

	local camera = workspace.CurrentCamera
	local time = workspace:GetServerTimeNow()

	if camera then
		local frame = camera.CFrame
		Renderer.Step(time, os.clock(), frame.Position, frame.LookVector)
	else
		Renderer.Step(time, os.clock(), Vector3.zero)
	end

	Config.Profiler.End()
end

--[[
	A slot with nothing drawn yet

	@param index number
	@param targets {Target}
	@return Slot
--]]
local function newSlot(index: number, targets: { Target }): Slot
	return {
		Targets = targets,
		Index = index,
		Out = {},
		Frame = { Emission = 1 },
		Shown = { Far = false, Emission = 1, Extra = {} },
		Drawn = false,
	}
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

	local inputs = {}

	if options and options.Inputs then
		for name, value in options.Inputs do
			inputs[name] = value
		end
	end

	local own: { Target } = {}
	local perTarget = options ~= nil and options.PerTarget == true

	local binding: Binding = {
		Material = material,
		Shader = shader,
		Params = Material.Decode(material),
		Inputs = inputs,
		Targets = own,
		Slots = {},
		Options = { Emissive = options ~= nil and options.Emissive == true },
		Anchor = nil,
		AnchorConnection = nil,

		PerTarget = perTarget,
		Count = 0,
		TimeScale = (options and options.TimeScale) or 1,
		TimeOffset = (options and options.TimeOffset) or 0,

		ReadsPosition = false,
		ReadsDistance = false,
		ReadsLoudness = false,

		Dirty = true,
		Far = false,
		Culled = false,
		Lights = false,
		Position = nil,
		NextEval = 0,
		NextRange = 0,
		Broken = false,
		Alive = true,
		Place = 0,
	}

	local shared = newSlot(0, own)

	for _, instance in targets do
		local writer = Writers.For(instance)
		if not writer then continue end

		local slot = if perTarget then newSlot(#own, {}) else shared

		local target: Target
		target = {
			Instance = instance,
			Writer = writer,
			Base = writer.Capture(instance),
			Cache = {},
			Connection = instance.Destroying:Connect(function()
				drop(binding, target)
			end),
			Slot = slot,
		}

		table.insert(own, target)

		if perTarget then
			table.insert(slot.Targets, target)
			table.insert(binding.Slots, slot)
		end

		if instance:IsA('Light') then binding.Lights = true end
	end

	if not perTarget then binding.Slots[1] = shared end

	binding.Count = #own

	setAnchor(binding, (options and options.Anchor) or anchorOf(own))
	fillInputs(binding)

	table.insert(list, binding)
	binding.Place = #list
	stats.Bindings = #list

	if not connection and RunService:IsClient() then connection = RunService.PreRender:Connect(onRender) end

	return setmetatable(binding, BindingClass) :: any
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
	binding.NextRange = 0

	fillInputs(binding)
end

--[[
	Sets one input. Only a change marks the binding for redrawing, so calling this every frame with
	the same value costs a Static shader nothing. Inputs that fill themselves in overwrite it.

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
	Changes the targets' authored look while bound. The targets are put back as they were bound,
	edit runs, and what it leaves becomes what Destroy restores; the binding then draws over it again
	at once, so the authored look never shows for a frame.

	@param binding Binding
	@param edit () -> () -- writes the new authored look, e.g. part.Color = paint
	@return nil
--]]
function Renderer.Edit(binding: Binding, edit: () -> ())
	if not binding.Alive then
		edit()
		return
	end

	for _, target in binding.Targets do
		target.Writer.Restore(target.Instance, target.Base)
	end

	local ok, err = pcall(edit)

	for _, target in binding.Targets do
		target.Base = target.Writer.Capture(target.Instance)
		table.clear(target.Cache)
	end

	--// The last output again, so a culled or rate-capped binding keeps its look too
	for _, slot in binding.Slots do
		if slot.Drawn then write(binding, slot) end
	end

	binding.Dirty = true

	if not ok then error(err, 2) end
end

--[[
	Stops drawing and puts every target back as it was bound

	@param binding Binding
	@return nil
--]]
function Renderer.Destroy(binding: Binding)
	if not binding.Alive then return end

	binding.Alive = false

	--// The last binding takes its place
	local last = list[#list]
	list[binding.Place] = last
	last.Place = binding.Place
	list[#list] = nil
	stats.Bindings = #list

	for _, target in binding.Targets do
		target.Connection:Disconnect()
		target.Writer.Restore(target.Instance, target.Base)
	end

	table.clear(binding.Targets)
	table.clear(binding.Slots)

	if binding.AnchorConnection then
		binding.AnchorConnection:Disconnect()
		binding.AnchorConnection = nil
	end

	if #list == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

--[[
	How many bindings are live, and how many were evaluated and targets written last frame

	@return Stats
--]]
function Renderer.Stats(): Stats
	return stats
end

BindingClass.SetMaterial = Renderer.SetMaterial
BindingClass.SetInput = Renderer.SetInput
BindingClass.Edit = Renderer.Edit
BindingClass.Destroy = Renderer.Destroy

return Renderer
