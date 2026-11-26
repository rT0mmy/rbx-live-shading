--!strict
--!native

--// Bindings that follow a tag or a CollectionService query: each member is given its own binding when
--// it joins, and that binding is destroyed, so the member gets its look back, when it leaves

local CollectionService = game:GetService('CollectionService')

local Material = require(`./Material`)
local Renderer = require(`./Renderer`)
local Shader = require(`./Shader`)
local Types = require(`./Types`)

local Group = {}

export type Options = Types.GroupOptions

type Group = {
	Material: Material.Material,
	Inputs: { [string]: number }, -- also in Bind, so later members get what SetInput set
	Bind: Types.Options, -- what each member is bound with
	Descendants: boolean,
	OnAdded: ((instance: Instance, binding: Types.Binding) -> ())?,
	Bindings: { [Instance]: Types.Binding },
	Stop: () -> (), -- stops following its tag or query
	Alive: boolean,
}

export type Public = Types.Group

local GroupClass = {}
GroupClass.__index = GroupClass

--[[
	Binds a member that has joined

	@param group Group
	@param instance Instance
	@return nil
--]]
local function join(group: Group, instance: Instance)
	if not group.Alive or group.Bindings[instance] then return end

	local targets = { instance }

	if group.Descendants then
		for _, descendant in instance:GetDescendants() do
			table.insert(targets, descendant)
		end
	end

	local made = Renderer.Bind(group.Material, targets, group.Bind)

	--// Nothing in it can be drawn on
	if #made.Targets == 0 then
		Renderer.Destroy(made)
		return
	end

	local binding: Types.Binding = made :: any

	group.Bindings[instance] = binding

	if group.OnAdded then group.OnAdded(instance, binding) end
end

--[[
	Unbinds a member that has left

	@param group Group
	@param instance Instance
	@return nil
--]]
local function leave(group: Group, instance: Instance)
	local binding = group.Bindings[instance]

	if not binding then return end

	group.Bindings[instance] = nil
	binding:Destroy()
end

--[[
	A group with no members yet

	@param material Material
	@param options Options?
	@param caller string -- for the error
	@return Group
--]]
local function new(material: Material.Material, options: Options?, caller: string): Group
	assert(Shader.Get(material.Shader), `{caller} - no shader called {material.Shader}`)

	local inputs = {}

	if options and options.Inputs then
		for name, value in options.Inputs do
			inputs[name] = value
		end
	end

	local group: Group = {
		Material = material,
		Inputs = inputs,
		Bind = {
			Inputs = inputs,
			Emissive = options and options.Emissive,
			PerTarget = options and options.PerTarget,
			TimeScale = options and options.TimeScale,
			TimeOffset = options and options.TimeOffset,
		},
		Descendants = options == nil or options.Descendants ~= false,
		OnAdded = options and options.OnAdded,
		Bindings = {},
		Stop = function() end,
		Alive = true,
	}

	return setmetatable(group, GroupClass) :: any
end

--[[
	Draws a material on everything with a tag under the root, as long as it has the tag and is
	there. Works with any tag name, and on engines without CollectionService:CreateCollection.

	@param tag string
	@param material Material -- sanitized
	@param options Options?
	@return Group
--]]
function Group.Tag(tag: string, material: Material.Material, options: Options?): Public
	assert(type(tag) == 'string' and tag ~= '', 'Shading.BindTag - needs a tag')

	local group = new(material, options, 'Shading.BindTag')
	local root: Instance = (options and options.Root) or workspace

	--// Every tagged instance in the game, watched so it joins and leaves as it moves in and out of root
	local watching: { [Instance]: RBXScriptConnection } = {}

	local function update(instance: Instance)
		if instance:IsDescendantOf(root) then
			join(group, instance)
		else
			leave(group, instance)
		end
	end

	local function track(instance: Instance)
		if watching[instance] then return end

		watching[instance] = instance.AncestryChanged:Connect(function()
			update(instance)
		end)

		update(instance)
	end

	local function untrack(instance: Instance)
		local connection = watching[instance]

		if connection then
			connection:Disconnect()
			watching[instance] = nil
		end

		leave(group, instance)
	end

	local added = CollectionService:GetInstanceAddedSignal(tag):Connect(track)
	local removed = CollectionService:GetInstanceRemovedSignal(tag):Connect(untrack)

	for _, instance in CollectionService:GetTagged(tag) do
		track(instance)
	end

	group.Stop = function()
		added:Disconnect()
		removed:Disconnect()

		for instance in watching do
			untrack(instance)
		end
	end

	return group :: any
end

--[[
	Draws a material on every instance a CollectionService:CreateCollection query matches, e.g.
	'Model.Car >> Part.Underglow' or 'BasePart.Neon:not([$Broken])', for as long as it matches

	@param query string
	@param material Material -- sanitized
	@param options Options? -- Root is the collection's root
	@return Group
--]]
function Group.Query(query: string, material: Material.Material, options: Options?): Public
	assert(type(query) == 'string' and query ~= '', 'Shading.BindQuery - needs a query')

	local group = new(material, options, 'Shading.BindQuery')
	local collection = (CollectionService :: any):CreateCollection(query, options and options.Root)

	--// OnRemoved first: assigning OnAdded runs it for every instance already matching
	function collection.OnRemoved(instance: Instance)
		leave(group, instance)
	end

	function collection.OnAdded(instance: Instance)
		join(group, instance)
	end

	group.Stop = function()
		collection:Destroy()
	end

	return group :: any
end

--[[
	Swaps every member's material, and the one later members are bound with

	@param material Material -- sanitized
	@return nil
--]]
function GroupClass.SetMaterial(group: Group, material: Material.Material)
	if not group.Alive then return end

	if not Shader.Get(material.Shader) then
		warn(`[Shading] no shader called {material.Shader}; the material was not changed`)
		return
	end

	group.Material = material

	for _, binding in group.Bindings do
		binding:SetMaterial(material)
	end
end

--[[
	Sets an input on every member, and on later members as they are bound

	@param name string
	@param value number
	@return nil
--]]
function GroupClass.SetInput(group: Group, name: string, value: number)
	if not group.Alive then return end

	group.Inputs[name] = value

	for _, binding in group.Bindings do
		binding:SetInput(name, value)
	end
end

--[[
	A member's binding, nil when it is not a member

	@param instance Instance
	@return Binding?
--]]
function GroupClass.Get(group: Group, instance: Instance): Types.Binding?
	return group.Bindings[instance]
end

--[[
	Stops following the tag or query and puts every member back as it was bound

	@return nil
--]]
function GroupClass.Destroy(group: Group)
	if not group.Alive then return end

	group.Alive = false
	group.Stop()

	for instance in group.Bindings do
		leave(group, instance)
	end
end

return Group
