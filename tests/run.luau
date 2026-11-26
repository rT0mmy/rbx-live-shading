local fs = require('@lune/fs')
local roblox = require('@lune/roblox')
local process = require('@lune/process')

local Harness = require('./harness')

local Color3, Vector3, Enum = roblox.Color3, roblox.Vector3, roblox.Enum

--// A signal that counts its connections
local function signal()
	local listeners = {}
	return {
		Connect = function(_, fn)
			listeners[fn] = true
			return {
				Disconnect = function()
					listeners[fn] = nil
				end,
			}
		end,
		Fire = function(_, ...)
			for fn in table.clone(listeners) do
				fn(...)
			end
		end,
		Count = function()
			local n = 0
			for _ in listeners do
				n += 1
			end
			return n
		end,
	}
end

--// CollectionService: tags with their signals, and collections the tests add and remove members of by hand
local tagged, addedSignals, removedSignals, collections = {}, {}, {}, {}

local function tagSignal(signals, tag)
	signals[tag] = signals[tag] or signal()
	return signals[tag]
end

local CollectionService = {
	GetTagged = function(_, tag)
		return table.clone(tagged[tag] or {})
	end,
	GetInstanceAddedSignal = function(_, tag)
		return tagSignal(addedSignals, tag)
	end,
	GetInstanceRemovedSignal = function(_, tag)
		return tagSignal(removedSignals, tag)
	end,
	AddTag = function(_, instance, tag)
		tagged[tag] = tagged[tag] or {}
		table.insert(tagged[tag], instance)
		tagSignal(addedSignals, tag):Fire(instance)
	end,
	RemoveTag = function(_, instance, tag)
		local index = table.find(tagged[tag], instance)
		table.remove(tagged[tag], index)
		tagSignal(removedSignals, tag):Fire(instance)
	end,
	--// Callbacks assigned once each, OnAdded run for members already there, Destroy removes them all
	CreateCollection = function(_, query, root)
		local members = {}
		local callbacks = {}
		local collection
		collection = setmetatable({
			Query = query,
			Root = root,
			Destroy = function()
				for _, member in table.clone(members) do
					collection.Remove(member)
				end
				collections[query] = nil
			end,
			--// Test hooks, not Roblox API
			Add = function(instance)
				table.insert(members, instance)
				if callbacks.OnAdded then callbacks.OnAdded(instance) end
			end,
			Remove = function(instance)
				table.remove(members, table.find(members, instance))
				if callbacks.OnRemoved then callbacks.OnRemoved(instance) end
			end,
		}, {
			__index = callbacks,
			__newindex = function(_, key, fn)
				assert(callbacks[key] == nil, `{key} assigned twice`)
				callbacks[key] = fn
				if key == 'OnAdded' then
					for _, member in members do
						fn(member)
					end
				end
			end,
		})
		collections[query] = collection
		return collection
	end,
}

Harness.Services.CollectionService = CollectionService

local Shading = Harness.Load()

local passed, failed = 0, 0

local function check(name, ok, detail)
	if ok then
		passed += 1
	else
		failed += 1
		print(`FAIL {name}{if detail then ' - ' .. tostring(detail) else ''}`)
	end
end

local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end

--// Each fake's signals
local signals = {}

--[[
	A fake instance: IsA by a class list, every property write counted. props.Inside says whether it
	is under Workspace; props.Descendants lists what it holds.
--]]
local function fake(classes, props)
	local writes = {}
	local own = { Destroying = signal(), AncestryChanged = signal() }
	local object = setmetatable({}, {
		__index = function(_, key)
			if key == 'IsA' then
				return function(_, class)
					return table.find(classes, class) ~= nil
				end
			end
			if key == 'IsDescendantOf' then
				return function()
					return props.Inside ~= false
				end
			end
			if key == 'GetDescendants' then
				return function()
					return props.Descendants or {}
				end
			end
			if own[key] then return own[key] end
			return props[key]
		end,
		__newindex = function(_, key, value)
			props[key] = value
			writes[key] = (writes[key] or 0) + 1
		end,
	})
	signals[object] = own
	return object, props, writes
end

local function destroy(object)
	signals[object].Destroying:Fire()
end

--// Moves a fake in or out of Workspace
local function move(object, inside)
	object.Inside = inside
	signals[object].AncestryChanged:Fire()
end

--// Connections a fake still has on its Destroying
local function listening(object)
	return signals[object].Destroying:Count()
end

local function part(position)
	return fake({ 'Part', 'BasePart' }, {
		Color = Color3.fromRGB(40, 40, 40),
		Material = Enum.Material.SmoothPlastic,
		MaterialVariant = '',
		Transparency = 0,
		Position = position or Vector3.zero,
	})
end

local function light()
	return fake({ 'PointLight', 'Light' }, { Color = Color3.new(1, 1, 1), Brightness = 4, Enabled = true })
end

local function total(writes)
	local n = 0
	for _, count in writes do
		n += count
	end
	return n
end

--// ---------------------------------------------------------------- Params and materials

do
	check('hex from Color3', Shading.Hex(Color3.fromRGB(255, 0, 170)) == 'FF00AA')
	check('hex from string with #', Shading.Hex('#ff00aa') == 'FF00AA')
	local b = buffer.create(3)
	buffer.writeu8(b, 0, 1)
	buffer.writeu8(b, 1, 2)
	buffer.writeu8(b, 2, 255)
	check('hex from buffer', Shading.Hex(b) == '0102FF')
	check('hex refuses junk', Shading.Hex('nope') == nil and Shading.Hex(12) == nil)
end

do
	local m, issues =
		Shading.Sanitize({ Shader = 'Strobe', Params = { Speed = 99, Flashes = 2.6, Color = 'zz', Bogus = 1 } })
	check('strobe sanitized', m ~= nil)
	check('number clamped', m.Params.Speed == 4, m.Params.Speed)
	check('number snapped to step', m.Params.Flashes == 3, m.Params.Flashes)
	check('bad colour takes default', m.Params.Color == 'FFFFFF')
	check('missing param filled', m.Params.Brightness == 1)
	check('unknown param dropped', m.Params.Bogus == nil)
	check('issues reported', #issues == 2, #issues)
end

do
	local m = Shading.Sanitize({
		Shader = 'Cycle',
		Params = { Colors = { 'FF0000', 'bad', '00FF00', '0000FF', 'FFFF00', 'FF00FF', '00FFFF', '123456' } },
	})
	check('colours capped at Max', #m.Params.Colors == 6, #m.Params.Colors)
	local empty = Shading.Sanitize({ Shader = 'Cycle', Params = { Colors = {} } })
	check('too few colours takes default', #empty.Params.Colors == 3)
	local nan = Shading.Sanitize({ Shader = 'Pulse', Params = { Speed = 0 / 0 } })
	check('NaN refused', nan.Params.Speed == 0.5)
end

do
	local m, issues = Shading.Sanitize({ Shader = 'Nope' })
	check('unknown shader refused', m == nil and #issues == 1)
	check('non-table refused', (Shading.Sanitize(5)) == nil)
	local a = Shading.Material('Cycle')
	local b = Shading.Material('Cycle')
	check('equal materials', Shading.Equal(a, b))
	b.Params.Colors[2] = '000000'
	check('colour list difference seen', not Shading.Equal(a, b))
	check('different shaders differ', not Shading.Equal(a, Shading.Material('Solid')))
	local ok = pcall(Shading.Material, 'Nope')
	check('Material errors on unknown shader', not ok)
end

do
	local ok = pcall(Shading.Shader, { Name = 'Solid', Evaluate = function() end })
	check('duplicate shader name refused', not ok)
	ok = pcall(
		Shading.Shader,
		{ Name = 'BadParam', Params = { X = { Kind = 'Number', Default = 1 } }, Evaluate = function() end }
	)
	check('number without range refused', not ok)
	ok = pcall(Shading.Shader, {
		Name = 'BadChoice',
		Params = { X = { Kind = 'Choice', Default = 'c', Options = { 'a' } } },
		Evaluate = function() end,
	})
	check('choice default outside options refused', not ok)
	local names = Shading.Names()
	check('built-ins registered', table.find(names, 'Rainbow') ~= nil and #names >= 7, #names)
	check('order honoured', Shading.Get('Pulse').Order[1] == 'Color')
end

--// ---------------------------------------------------------------- Shader output

local BIG = 1.8e9

do
	--// Every built-in stays in range at small and server-sized times
	for _, name in Shading.Names() do
		local m = Shading.Material(name)
		local fine = true
		for i = 0, 400 do
			local time = (if i % 2 == 0 then 0 else BIG) + i * 0.0137
			local out = Shading.Evaluate(m, { Index = i % 4, Count = 4, Group = i % 2 }, time)
			if out.Emission and (out.Emission < 0 or out.Emission > 1 or out.Emission ~= out.Emission) then
				fine = false
			end
			if out.Color and typeof(out.Color) ~= 'Color3' then fine = false end
		end
		check(`{name} output in range`, fine)
	end
end

do
	local m = Shading.Material('Solid', { Color = 'FF0000', Brightness = 0.5 })
	local out = Shading.Evaluate(m, nil, 0)
	check('solid colour', out.Color == Color3.fromHex('FF0000') and out.Emission == 0.5)
	check('solid leaves transparency alone', out.Transparency == nil)
end

do
	local m = Shading.Material('Pulse', { Speed = 1, Floor = 0.2 })
	check('pulse floor at phase 0', near(Shading.Evaluate(m, nil, 0).Emission, 0.2))
	check('pulse full at half phase', near(Shading.Evaluate(m, nil, 0.5).Emission, 1))
	check('pulse keeps precision at server time', near(Shading.Evaluate(m, nil, 1800000000.5).Emission, 1, 1e-4))
end

do
	--// Lit share of a strobe period: Flashes x FLASH / period
	local m = Shading.Material('Strobe', { Speed = 1, Flashes = 2 })
	local lit, steps = 0, 10000
	for i = 0, steps - 1 do
		if Shading.Evaluate(m, nil, i / steps).Emission > 0 then
			lit += 1
		end
	end
	check('strobe lit share', near(lit / steps, 0.12, 0.002), lit / steps)
end

do
	local m = Shading.Material('Chase', { Speed = 0.25, Tail = 0 })
	local one = true
	for i = 0, 200 do
		local time = i * 0.0731
		local litCount = 0
		for index = 0, 3 do
			if Shading.Evaluate(m, { Index = index, Count = 4 }, time).Emission > 0 then
				litCount += 1
			end
		end
		if litCount ~= 1 then one = false end
	end
	check('chase without tail lights exactly one', one)
	--// At t = 0.25 laps/s * 1 s = a quarter lap, the head is on index 1
	check('chase head position', Shading.Evaluate(m, { Index = 1, Count = 4 }, 1.01).Emission == 1)
	local tail = Shading.Material('Chase', { Speed = 0.25, Tail = 0.5 })
	local behind = Shading.Evaluate(tail, { Index = 0, Count = 4 }, 1.01).Emission
	check('chase tail fades behind the head', behind > 0 and behind < 1, behind)
	local rev = Shading.Material('Chase', { Speed = 0.25, Tail = 0, Reverse = true })
	check('chase reverse', Shading.Evaluate(rev, { Index = 2, Count = 4 }, 1.01).Emission == 1)
end

do
	local m = Shading.Material('Alternate', { Speed = 1 })
	local never = true
	for i = 0, 300 do
		local a = Shading.Evaluate(m, { Group = 0 }, i * 0.0113).Emission
		local b = Shading.Evaluate(m, { Group = 1 }, i * 0.0113).Emission
		if a > 0 and b > 0 then never = false end
		if a == 0 and b == 0 then never = false end
	end
	check('alternate: exactly one group lit', never)
	check('alternate group colours', Shading.Evaluate(m, { Group = 1 }, 1.25).Color == Color3.fromHex('0000FF'))
end

do
	local m = Shading.Material('Cycle', { Colors = { 'FF0000', '0000FF' }, Speed = 1, Blend = 0.5 })
	check('cycle holds its colour', Shading.Evaluate(m, nil, 0.25).Color == Color3.fromHex('FF0000'))
	local mid = Shading.Evaluate(m, nil, 0.75).Color
	check('cycle blends halfway', near(mid.R, 0.5, 0.01) and near(mid.B, 0.5, 0.01), mid)
	check('cycle wraps to the first', Shading.Evaluate(m, nil, 1.25).Color == Color3.fromHex('0000FF'))
end

--// ---------------------------------------------------------------- Renderer

do
	local strip, stripProps, stripWrites = part()
	local lamp, lampProps = light()
	local binding = Shading.Bind(Shading.Material('Solid', { Color = 'FF00AA' }), { strip, lamp }, { Emissive = true })

	Shading.Step(0, 0, Vector3.zero)
	check('emissive part goes neon', stripProps.Material == Enum.Material.Neon)
	check('part takes colour', stripProps.Color == Color3.fromHex('FF00AA'))
	check('light takes colour', lampProps.Color == Color3.fromHex('FF00AA') and lampProps.Brightness == 4)

	local before = total(stripWrites)
	for frame = 1, 30 do
		Shading.Step(frame / 60, frame / 60, Vector3.zero)
	end
	check('static shader writes once', total(stripWrites) == before, total(stripWrites) - before)

	binding:SetInput('Index', 0)
	Shading.Step(1, 1, Vector3.zero)
	check('same input causes no redraw', total(stripWrites) == before)

	binding:SetMaterial(Shading.Material('Solid', { Color = 'FF00AA', Brightness = 0 }))
	Shading.Step(1.1, 1.1, Vector3.zero)
	check(
		'dark emissive part shows its authored look',
		stripProps.Material == Enum.Material.SmoothPlastic and stripProps.Color == Color3.fromRGB(40, 40, 40)
	)
	check('dark light switches off', lampProps.Enabled == false)

	binding:SetMaterial(Shading.Material('Solid', { Color = '00FF00', Brightness = 0.5 }))
	Shading.Step(1.2, 1.2, Vector3.zero)
	check('half emission dims the neon', near(stripProps.Color.G, 0.5, 0.01), stripProps.Color)
	check('half emission halves light brightness', near(lampProps.Brightness, 2, 0.05), lampProps.Brightness)

	binding:Destroy()
	check(
		'destroy restores part',
		stripProps.Material == Enum.Material.SmoothPlastic and stripProps.Color == Color3.fromRGB(40, 40, 40)
	)
	check(
		'destroy restores light',
		lampProps.Enabled == true and lampProps.Brightness == 4 and lampProps.Color == Color3.new(1, 1, 1)
	)
	check('no bindings left', Shading.Stats().Bindings == 0)
end

do
	--// Far: lights out, parts keep drawing. Culled: nothing drawn.
	local strip, stripProps = part(Vector3.new(200, 0, 0))
	local lamp, lampProps = light()
	local binding = Shading.Bind(
		Shading.Material('Pulse', { Speed = 1, Floor = 0 }),
		{ strip, lamp },
		{ Emissive = true, Anchor = strip }
	)

	local C = os.clock() + 1
	Shading.Step(0.5, C, Vector3.zero)
	check('far binding turns its light off', lampProps.Enabled == false)
	check('far binding still draws its part', stripProps.Material == Enum.Material.Neon)

	stripProps.Position = Vector3.new(1000, 0, 0)
	Shading.Step(0.5, C + 1, Vector3.zero)
	local colour = stripProps.Color
	Shading.Step(0.75, C + 1.01, Vector3.zero)
	check('culled binding holds its last look', stripProps.Color == colour)

	stripProps.Position = Vector3.new(10, 0, 0)
	Shading.Step(0.5, C + 2, Vector3.zero)
	check('back in range lights up again', lampProps.Enabled == true)

	binding:Destroy()
end

do
	--// Rate caps evaluations
	local evaluations = 0
	Shading.Shader({
		Name = 'TestRated',
		Rate = 10,
		Evaluate = function(_, _, _, out)
			evaluations += 1
			out.Emission = 1
		end,
	})
	local strip = part()
	local binding = Shading.Bind(Shading.Material('TestRated'), { strip })
	for frame = 0, 59 do
		Shading.Step(frame / 60, 100 + frame / 60, Vector3.zero)
	end
	check('rate 10 evaluates about 10 times a second', evaluations >= 9 and evaluations <= 11, evaluations)
	binding:Destroy()
end

do
	--// A shader that errors is stopped, not retried every frame
	local calls = 0
	Shading.Shader({
		Name = 'TestBroken',
		Evaluate = function()
			calls += 1
			error('boom')
		end,
	})
	local strip = part()
	local binding = Shading.Bind(Shading.Material('TestBroken'), { strip })
	for frame = 0, 10 do
		Shading.Step(frame, 200 + frame, Vector3.zero)
	end
	check('broken shader stops after one error', calls == 1, calls)
	binding:SetMaterial(Shading.Material('Solid'))
	Shading.Step(0, 300, Vector3.zero)
	check('a new material revives it', not binding.Broken)
	binding:Destroy()
end

do
	--// Many targets, one evaluation
	local evaluations = 0
	Shading.Shader({
		Name = 'TestCount',
		Evaluate = function(_, _, _, out)
			evaluations += 1
			out.Color = Color3.new(1, 0, 0)
		end,
	})
	local targets, props = {}, {}
	for i = 1, 50 do
		local p, pp = part()
		targets[i] = p
		props[i] = pp
	end
	local binding = Shading.Bind(Shading.Material('TestCount'), targets)
	Shading.Step(0, 400, Vector3.zero)
	check('fifty targets, one evaluation', evaluations == 1, evaluations)
	check('every target drawn', props[50].Color == Color3.new(1, 0, 0))
	check('non-emissive part keeps its material', props[1].Material == Enum.Material.SmoothPlastic)
	check(
		'unsupported targets skipped',
		#Shading.Bind(Shading.Material('Solid'), { (fake({ 'Folder' }, {})) }).Targets == 0
	)
	binding:Destroy()
end

do
	--// A channel the new material leaves unset goes back to the authored look
	Shading.Shader({
		Name = 'TestFaded',
		Evaluate = function(_, _, _, out)
			out.Color = Color3.new(1, 0, 0)
			out.Transparency = 0.5
			out.MaterialVariant = 'Rusty'
		end,
	})
	Shading.Shader({
		Name = 'TestBare',
		Evaluate = function(_, _, _, out)
			out.Emission = 1
		end,
	})
	local strip, props = part()
	local lamp, lampProps = light()
	local binding = Shading.Bind(Shading.Material('TestFaded'), { strip, lamp })
	Shading.Step(0, 500, Vector3.zero)
	check('transparency written', props.Transparency == 0.5, props.Transparency)
	check('variant written', props.MaterialVariant == 'Rusty')
	binding:SetMaterial(Shading.Material('TestBare'))
	Shading.Step(0, 501, Vector3.zero)
	check('unset transparency goes back', props.Transparency == 0, props.Transparency)
	check('unset variant goes back', props.MaterialVariant == '')
	check('unset part colour goes back', props.Color == Color3.fromRGB(40, 40, 40))
	check('unset light colour goes back', lampProps.Color == Color3.new(1, 1, 1))
	binding:Destroy()
end

do
	--// A light out of range is never drawn lit, even on its first frame
	local strip = part(Vector3.new(200, 0, 0))
	local lamp, lampProps = light()
	local binding = Shading.Bind(Shading.Material('Solid'), { strip, lamp }, { Anchor = strip })
	Shading.Step(0, os.clock(), Vector3.zero)
	check('far light dark on its first frame', lampProps.Enabled == false)
	binding:Destroy()
end

do
	--// Destroyed targets are let go; the anchor moves; an empty binding destroys itself
	local live = Shading.Stats().Bindings
	local a, _, aWrites = part()
	local b = part(Vector3.new(1000, 0, 0))
	local binding = Shading.Bind(Shading.Material('Pulse'), { a, b })
	Shading.Step(0, 600, Vector3.zero)
	destroy(a)
	check('destroyed target dropped', #binding.Targets == 1)
	check('destroyed target disconnected', listening(a) == 0, listening(a))
	local before = total(aWrites)
	Shading.Step(0.3, 600.01, Vector3.zero)
	check('destroyed target not written', total(aWrites) == before)
	check('anchor moves to a live target', binding.Anchor == b)
	check('new anchor measured straight away', binding.Culled)
	destroy(b)
	check('binding with no targets destroys itself', not binding.Alive and Shading.Stats().Bindings == live)
	check('last target disconnected', listening(b) == 0)
end

do
	--// An anchor that is not a target, destroyed: the binding is always in range after
	local anchor = part(Vector3.new(1000, 0, 0))
	local lamp, lampProps = light()
	local binding = Shading.Bind(Shading.Material('Solid', { Color = 'FF00AA' }), { lamp }, { Anchor = anchor })
	Shading.Step(0, 700, Vector3.zero)
	check('culled by its anchor', binding.Culled and lampProps.Color == Color3.new(1, 1, 1))
	destroy(anchor)
	check('lost anchor leaves it in range', binding.Anchor == nil and not binding.Culled)
	check('lost anchor disconnected', listening(anchor) == 0)
	Shading.Step(0, 700.01, Vector3.zero)
	check('drawn once the anchor is gone', lampProps.Color == Color3.fromHex('FF00AA'))
	binding:Destroy()
end

do
	--// Edit changes the authored look without the shaded look dropping for a frame
	local strip, props = part()
	local binding = Shading.Bind(Shading.Material('Solid', { Color = 'FF00AA' }), { strip }, { Emissive = true })
	Shading.Step(0, 800, Vector3.zero)
	binding:Edit(function()
		strip.Color = Color3.fromRGB(0, 0, 255)
	end)
	check(
		'edit keeps the shaded look',
		props.Material == Enum.Material.Neon and props.Color == Color3.fromHex('FF00AA'),
		props.Color
	)
	local ok = pcall(binding.Edit, binding, function()
		error('oops')
	end)
	check('edit passes on an error', not ok)
	check('an erroring edit still leaves it drawn', props.Material == Enum.Material.Neon)
	binding:Destroy()
	check(
		'destroy restores the edited look',
		props.Color == Color3.fromRGB(0, 0, 255) and props.Material == Enum.Material.SmoothPlastic
	)
end

--// ---------------------------------------------------------------- Performance

do
	--// An output the targets already show is evaluated but not written
	Shading.Shader({
		Name = 'TestHold',
		Evaluate = function(_, _, time, out)
			out.Color = Color3.new(1, 0, 0)
			--// Under one level apart: the same after levelling
			out.Emission = 0.5 + (time % 1) * 0.001
		end,
	})
	local strip, _, writes = part()
	local binding = Shading.Bind(Shading.Material('TestHold'), { strip }, { Emissive = true })
	Shading.Step(0, 1100, Vector3.zero)
	local before = total(writes)
	Shading.Step(0.5, 1100.01, Vector3.zero)
	check('unchanged output evaluated', Shading.Stats().Evaluated >= 1)
	check('unchanged output not written', Shading.Stats().Written == 0 and total(writes) == before)
	binding:Destroy()
end

do
	--// Keys past the built-in channels still count as changes, for a game's own writers
	local seen = {}
	Shading.Writer({
		Class = 'TestGadget',
		Capture = function()
			return {}
		end,
		Write = function(_, out, _, _, _, _, frame)
			table.insert(seen, { Size = out.Size, Frame = frame })
		end,
		Restore = function() end,
	})
	Shading.Shader({
		Name = 'TestSized',
		Evaluate = function(_, _, time, out)
			out.Size = if time < 1 then 1 else 2
		end,
	})
	local gadget = fake({ 'TestGadget' }, {})
	local binding = Shading.Bind(Shading.Material('TestSized'), { gadget })
	Shading.Step(0, 1200, Vector3.zero)
	Shading.Step(0.5, 1200.01, Vector3.zero)
	Shading.Step(1.5, 1200.02, Vector3.zero)
	check('own channel: written once per change', #seen == 2 and seen[2].Size == 2, #seen)
	check('writers are given the frame', seen[1].Frame and seen[1].Frame.Emission == 1)
	binding:Destroy()
end

do
	--// Past LightRadius a binding evaluates at FarRate at most
	local evaluations = 0
	Shading.Shader({
		Name = 'TestFar',
		Evaluate = function(_, _, _, out)
			evaluations += 1
			out.Emission = 1
		end,
	})
	local strip = part(Vector3.new(200, 0, 0))
	local binding = Shading.Bind(Shading.Material('TestFar'), { strip })
	for frame = 0, 59 do
		Shading.Step(frame / 60, 1300 + frame / 60, Vector3.zero)
	end
	check('far binding capped at FarRate', evaluations >= 13 and evaluations <= 17, evaluations)
	binding:Destroy()
end

do
	--// Behind the camera: parts hold, a lit light is drawn anyway
	local behind, behindProps = part(Vector3.new(0, 0, -50))
	local glow = Shading.Bind(Shading.Material('Solid', { Color = 'FF00AA' }), { behind })
	local lampPart = part(Vector3.new(0, 0, -50))
	local lamp, lampProps = light()
	local lit = Shading.Bind(Shading.Material('Solid', { Color = 'FF00AA' }), { lamp }, { Anchor = lampPart })
	local forward = Vector3.new(0, 0, 1)
	Shading.Step(0, 1400, Vector3.zero, forward)
	check('part behind the camera held', behindProps.Color == Color3.fromRGB(40, 40, 40))
	check('light behind the camera still drawn', lampProps.Color == Color3.fromHex('FF00AA'))
	Shading.Step(0, 1400.01, Vector3.zero, -forward)
	check('drawn once in view', behindProps.Color == Color3.fromHex('FF00AA'))
	Shading.Config.ViewCull = false
	glow:SetMaterial(Shading.Material('Solid', { Color = '00FF00' }))
	Shading.Step(0, 1400.02, Vector3.zero, forward)
	check('ViewCull off draws behind', behindProps.Color == Color3.fromHex('00FF00'))
	Shading.Config.ViewCull = true
	glow:Destroy()
	lit:Destroy()
end

do
	--// Budget: frames stop at it, and the next carries on with the bindings left waiting
	local flips = {}
	Shading.Shader({
		Name = 'TestFlip',
		Inputs = { Index = 0 },
		Evaluate = function(_, inputs, time, out)
			flips[inputs.Index] = (flips[inputs.Index] or 0) + 1
			out.Color = if (time * 60 // 1) % 2 == 0 then Color3.new(1, 0, 0) else Color3.new(0, 0, 1)
		end,
	})
	local made = {}
	for index = 1, 3 do
		local targets = {}
		for i = 1, 10 do
			targets[i] = (part())
		end
		made[index] = Shading.Bind(Shading.Material('TestFlip'), targets, { Inputs = { Index = index } })
	end
	Shading.Config.Budget = 10
	local capped = true
	for frame = 1, 3 do
		Shading.Step(frame / 60, 1500 + frame / 60, Vector3.zero)
		if Shading.Stats().Written ~= 10 then capped = false end
	end
	Shading.Config.Budget = nil
	check('budget caps a frame', capped)
	check('budget takes turns', flips[1] == 1 and flips[2] == 1 and flips[3] == 1, `{flips[1]} {flips[2]} {flips[3]}`)
	for _, binding in made do
		binding:Destroy()
	end
end

--// ---------------------------------------------------------------- Groups

do
	--// BindTag: tagged instances under Workspace are members while tagged and there
	local live = Shading.Stats().Bindings
	local early, earlyProps = part()
	local stored, storedProps = part()
	storedProps.Inside = false
	CollectionService:AddTag(early, 'Glow')
	CollectionService:AddTag(stored, 'Glow')

	local seen = {}
	local group = Shading.BindTag('Glow', Shading.Material('Solid', { Color = 'FF00AA' }), {
		Emissive = true,
		Inputs = { Index = 4 },
		OnAdded = function(instance, binding)
			table.insert(seen, instance)
			check('OnAdded gets a binding with methods', type(binding.SetInput) == 'function')
		end,
	})
	check('tagged before: joins', group:Get(early) ~= nil and seen[1] == early)
	check('group inputs given to members', group:Get(early).Inputs.Index == 4)
	check('tagged outside Workspace: does not join', group:Get(stored) == nil)

	Shading.Step(0, 900, Vector3.zero)
	check('member drawn', earlyProps.Material == Enum.Material.Neon)
	check('outside Workspace not drawn', storedProps.Material == Enum.Material.SmoothPlastic)

	local late = part()
	CollectionService:AddTag(late, 'Glow')
	check('tagged later: joins', group:Get(late) ~= nil and #seen == 2)

	move(stored, true)
	check('moved into Workspace: joins', group:Get(stored) ~= nil)
	Shading.Step(0, 900.01, Vector3.zero)
	move(stored, false)
	check(
		'moved out: leaves and is restored',
		group:Get(stored) == nil and storedProps.Material == Enum.Material.SmoothPlastic
	)

	CollectionService:RemoveTag(late, 'Glow')
	check('untagged: leaves', group:Get(late) == nil)
	check('untagged: let go of', signals[late].AncestryChanged:Count() == 0)

	group:SetMaterial(Shading.Material('Solid', { Color = '00FF00' }))
	group:SetInput('Index', 7)
	Shading.Step(0, 900.02, Vector3.zero)
	check('group material reaches members', earlyProps.Color == Color3.fromHex('00FF00'))
	check('group input reaches members', group:Get(early).Inputs.Index == 7)
	CollectionService:AddTag(late, 'Glow')
	check('later members get the group material and inputs', group:Get(late).Material.Params.Color == '00FF00')
	check('later members get group inputs', group:Get(late).Inputs.Index == 7)

	group:Destroy()
	check(
		'destroy restores members',
		earlyProps.Material == Enum.Material.SmoothPlastic and Shading.Stats().Bindings == live
	)
	check(
		'destroy lets go of the tag',
		addedSignals.Glow:Count() == 0
			and removedSignals.Glow:Count() == 0
			and signals[early].AncestryChanged:Count() == 0
	)
	check('unknown shader refused', not pcall(Shading.BindTag, 'Glow', { Shader = 'Nope', Params = {} }))
end

do
	--// BindQuery: collection members bound with their descendants while they match
	local live = Shading.Stats().Bindings
	local strip, stripProps = part()
	local lamp, lampProps = light()
	local car = fake({ 'Model' }, { Descendants = { strip, lamp } })
	local empty = fake({ 'Folder' }, {})

	local group = Shading.BindQuery('Model.Car', Shading.Material('Solid', { Color = 'FF00AA' }))
	local collection = collections['Model.Car']
	check('collection made under Workspace by default', collection ~= nil and collection.Root == nil)

	collection.Add(car)
	check('member bound with its descendants', group:Get(car) ~= nil and #group:Get(car).Targets == 2)
	Shading.Step(0, 1000, Vector3.zero)
	check(
		'descendants drawn',
		stripProps.Color == Color3.fromHex('FF00AA') and lampProps.Color == Color3.fromHex('FF00AA')
	)

	collection.Add(empty)
	check('member with nothing to draw on is skipped', group:Get(empty) == nil and Shading.Stats().Bindings == live + 1)

	collection.Remove(car)
	check(
		'member that stops matching is restored',
		group:Get(car) == nil and stripProps.Color == Color3.fromRGB(40, 40, 40)
	)

	collection.Add(car)
	Shading.Step(0, 1000.01, Vector3.zero)
	group:Destroy()
	check('destroying the group destroys its collection', collections['Model.Car'] == nil)
	check(
		'and restores its members',
		stripProps.Color == Color3.fromRGB(40, 40, 40) and Shading.Stats().Bindings == live
	)

	local bare = Shading.BindQuery('Model.Bare', Shading.Material('Solid'), { Descendants = false, Root = car })
	check('root passed to the collection', collections['Model.Bare'].Root == car)
	collections['Model.Bare'].Add(car)
	check('Descendants = false draws on the member only', bare:Get(car) == nil)
	bare:Destroy()
end

--// ---------------------------------------------------------------- Types

do
	--// Types can be required alone: it loads nothing and touches no service
	local source = fs.readFile('src/Types.luau')
	source = string.gsub(string.gsub(source, '%-%-%[%[.-%]%]', ''), '%-%-[^\n]*', '')
	check('Types requires nothing', string.find(source, 'require(', 1, true) == nil)
	check('Types touches no service', string.find(source, 'game', 1, true) == nil)
end

--// ---------------------------------------------------------------- Per-target and auto inputs

do
	--// PerTarget: one evaluation a target, with Index and Count filled in
	local seen = {}
	Shading.Shader({
		Name = 'TestIndexed',
		Inputs = { Index = 0, Count = 1 },
		Evaluate = function(_, inputs, _, out)
			table.insert(seen, `{inputs.Index}/{inputs.Count}`)
			out.Color = Color3.new(inputs.Index / 2, 0, 0)
		end,
	})
	local a, aProps = part()
	local b, bProps = part()
	local c, cProps = part()
	local binding = Shading.Bind(Shading.Material('TestIndexed'), { a, b, c }, { PerTarget = true })
	Shading.Step(0, 2000, Vector3.zero)
	check('per target: one evaluation each', #seen == 3 and Shading.Stats().Evaluated == 3, #seen)
	check('per target: Index and Count', table.concat(seen, ' ') == '0/3 1/3 2/3', table.concat(seen, ' '))
	check(
		'per target: own output each',
		near(aProps.Color.R, 0, 0.01) and near(bProps.Color.R, 0.5, 0.01) and near(cProps.Color.R, 1, 0.01)
	)
	Shading.Step(0.5, 2000.01, Vector3.zero)
	check('per target: unchanged slots not written', Shading.Stats().Written == 0)
	destroy(b)
	table.clear(seen)
	Shading.Step(1, 2000.02, Vector3.zero)
	check('per target: a destroyed target loses its slot', #seen == 2, #seen)
	check(
		'per target: others keep their Index',
		table.concat(seen, ' ') == '0/3 2/3' or table.concat(seen, ' ') == '2/3 0/3'
	)
	binding:Destroy()
	check('per target: destroy restores', cProps.Color == Color3.fromRGB(40, 40, 40))
end

do
	--// Wave reads each target's position
	local near0, props0 = part(Vector3.new(0, 0, 0))
	local near20, props20 = part(Vector3.new(20, 0, 0))
	local again, propsAgain = part(Vector3.new(40, 0, 0))
	local binding = Shading.Bind(
		Shading.Material('Wave', { Wavelength = 40, Speed = 0.5 }),
		{ near0, near20, again },
		{ PerTarget = true, Emissive = true }
	)
	Shading.Step(0, 2100, Vector3.zero)
	check('wave: half a wavelength apart differ', props0.Color ~= props20.Color)
	check('wave: a whole wavelength apart match', props0.Color == propsAgain.Color)
	binding:Destroy()
end

do
	--// Distance and Loudness fill themselves in; TimeScale and TimeOffset move the shader's clock
	local got = {}
	Shading.Shader({
		Name = 'TestAuto',
		Static = true,
		Inputs = { Distance = 0, Loudness = 0 },
		Evaluate = function(_, inputs, time, out)
			got.Distance, got.Loudness, got.Time = inputs.Distance, inputs.Loudness, time
			out.Emission = 1
		end,
	})
	local strip = part(Vector3.new(30, 40, 0))
	local binding = Shading.Bind(Shading.Material('TestAuto'), { strip }, { TimeScale = 2, TimeOffset = 5 })
	Shading.Config.Loudness = function()
		return 0.25
	end
	Shading.Step(10, 2200, Vector3.zero)
	check('Distance filled in', got.Distance == 50, got.Distance)
	check('Loudness filled in', got.Loudness == 0.25, got.Loudness)
	check('TimeScale and TimeOffset', got.Time == 25, got.Time)
	Shading.Config.Loudness = function()
		return 3
	end
	Shading.Step(10, 2200.01, Vector3.zero)
	check('a Static shader redraws for new loudness, clamped', got.Loudness == 1, got.Loudness)
	Shading.Config.Loudness = nil
	binding:Destroy()

	local music = Shading.Material('Music', { Floor = 0, Gain = 1 })
	check('music: silent is dark', Shading.Evaluate(music, { Loudness = 0 }, 0).Emission == 0)
	local loud = Shading.Evaluate(music, { Loudness = 1 }, 0)
	check('music: loud is full and the peak colour', loud.Emission == 1 and loud.Color == Color3.fromHex('FFFFFF'))
end

do
	--// Group options reach their bindings
	local strip = part()
	local group = Shading.BindQuery('Part.PerTarget', Shading.Material('Solid'), { PerTarget = true, TimeScale = 3 })
	collections['Part.PerTarget'].Add(strip)
	local binding = group:Get(strip)
	check('group passes PerTarget and TimeScale', binding.PerTarget == true and binding.TimeScale == 3)
	group:Destroy()
end

--// ---------------------------------------------------------------- More writers

local ColorSequence, NumberSequence = roblox.ColorSequence, roblox.NumberSequence

do
	local beam, beamProps = fake({ 'Beam' }, {
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new(0.2),
		Brightness = 2,
		Enabled = true,
	})
	local trail, trailProps = fake({ 'Trail' }, {
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new(0),
		Brightness = 1,
		Enabled = true,
	})
	local binding = Shading.Bind(Shading.Material('Solid', { Color = 'FF00AA', Brightness = 0.5 }), { beam, trail })
	check('beam and trail bound', #binding.Targets == 2)
	Shading.Step(0, 2300, Vector3.zero)
	check('beam colour sequence', beamProps.Color.Keypoints[1].Value == Color3.fromHex('FF00AA'))
	check('beam brightness by emission', beamProps.Brightness == 1, beamProps.Brightness)
	check('beam keeps its transparency when unset', near(beamProps.Transparency.Keypoints[1].Value, 0.2, 1e-6))
	check('trail drawn by the same writer', trailProps.Color.Keypoints[1].Value == Color3.fromHex('FF00AA'))
	binding:SetMaterial(Shading.Material('Solid', { Brightness = 0 }))
	Shading.Step(0, 2300.01, Vector3.zero)
	check('dark effect switches off', beamProps.Enabled == false)
	binding:Destroy()
	check('effect restored', beamProps.Enabled == true and beamProps.Brightness == 2)
end

do
	local glow, props = fake({ 'Highlight' }, {
		FillColor = Color3.new(1, 1, 1),
		OutlineColor = Color3.new(0, 0, 0),
		FillTransparency = 0.5,
		OutlineTransparency = 0,
		Enabled = true,
	})
	local binding = Shading.Bind(Shading.Material('Solid', { Color = '00FF00', Brightness = 0.5 }), { glow })
	Shading.Step(0, 2400, Vector3.zero)
	check(
		'highlight colours',
		props.FillColor == Color3.fromHex('00FF00') and props.OutlineColor == Color3.fromHex('00FF00')
	)
	check('highlight fades with emission', near(props.FillTransparency, 0.75) and near(props.OutlineTransparency, 0.5))
	binding:Destroy()
	check('highlight restored', props.FillTransparency == 0.5 and props.OutlineColor == Color3.new(0, 0, 0))
end

do
	local texture, props = fake({ 'Texture', 'Decal' }, { Color3 = Color3.new(1, 1, 1), Transparency = 0 })
	local binding = Shading.Bind(
		Shading.Material('Solid', { Color = '0000FF', Brightness = 0.5 }),
		{ texture },
		{ Emissive = true }
	)
	Shading.Step(0, 2500, Vector3.zero)
	check('texture tinted and dimmed', near(props.Color3.B, 0.5, 0.01) and props.Color3.R == 0, props.Color3)
	binding:Destroy()
	check('texture restored', props.Color3 == Color3.new(1, 1, 1))
end

--// ---------------------------------------------------------------- New shaders

do
	local twinkle = Shading.Material('Twinkle', { Density = 0.3, Speed = 1 })
	local lit = 0
	for index = 0, 1999 do
		if Shading.Evaluate(twinkle, { Index = index }, BIG + 0.5).Emission > 0 then
			lit += 1
		end
	end
	check('twinkle lights about Density of them', near(lit / 2000, 0.3, 0.04), lit / 2000)
	check(
		'twinkle is the same every time',
		Shading.Evaluate(twinkle, { Index = 17 }, BIG + 0.5).Emission
			== Shading.Evaluate(twinkle, { Index = 17 }, BIG + 0.5).Emission
	)

	local fixed = Shading.Material('Gradient', { Mode = 'Fixed', Colors = { 'FF0000', '0000FF' } })
	check(
		'gradient fixed: first',
		Shading.Evaluate(fixed, { Index = 0, Count = 5 }, 0).Color == Color3.fromHex('FF0000')
	)
	check(
		'gradient fixed: last',
		Shading.Evaluate(fixed, { Index = 4, Count = 5 }, 0).Color == Color3.fromHex('0000FF')
	)

	local heart = Shading.Material('Heartbeat', { Rate = 60, Floor = 0 })
	check('heartbeat thumps', Shading.Evaluate(heart, nil, 0.1).Emission > 0.99)
	check('heartbeat rests', Shading.Evaluate(heart, nil, 0.7).Emission < 0.01)

	local flicker = Shading.Material('Flicker', { Depth = 1 })
	local low, high = 1, 0
	for i = 0, 300 do
		local e = Shading.Evaluate(flicker, nil, BIG + i * 0.05).Emission
		low, high = math.min(low, e), math.max(high, e)
	end
	check('flicker varies at server time', high - low > 0.2, high - low)
end

--// ---------------------------------------------------------------- Network format

do
	local everyOk = true
	for _, name in Shading.Names() do
		local material = Shading.Material(name)
		local back = Shading.Unpack(Shading.Pack(material))
		if not (back and Shading.Equal(material, back)) then
			everyOk = false
			print('  round trip failed for', name)
		end
	end
	check('every shader at defaults round trips', everyOk)
	check('defaults pack to header and mask', buffer.len(Shading.Pack(Shading.Material('Solid'))) == 8)

	local custom =
		Shading.Material('Cycle', { Colors = { '123456', 'ABCDEF' }, Speed = 0.1, Blend = 0.5, Brightness = 1 })
	local packed = Shading.Pack(custom)
	local back, issues = Shading.Unpack(packed)
	check('custom material round trips exactly', back and Shading.Equal(custom, back) and #issues == 0)
	check('it is small', buffer.len(packed) < 40, buffer.len(packed))

	local choice = Shading.Material('Gradient', { Mode = 'Fixed' })
	check('choice round trips', Shading.Unpack(Shading.Pack(choice)).Params.Mode == 'Fixed')

	local wave = Shading.Material('Wave', { Axis = 'Z', Wavelength = 123 })
	check('bigger whole numbers and choices round trip', Shading.Equal(wave, (Shading.Unpack(Shading.Pack(wave)))))

	check('not a buffer refused', (Shading.Unpack('hello')) == nil)
	check('empty buffer refused', (Shading.Unpack(buffer.create(0))) == nil)
	local short = buffer.create(buffer.len(packed) - 2)
	buffer.copy(short, 0, packed, 0, buffer.len(short))
	check('cut short refused', (Shading.Unpack(short)) == nil)
	local wrong = buffer.create(8)
	buffer.writeu8(wrong, 0, 99)
	check('unknown version refused', (Shading.Unpack(wrong)) == nil)
	local unknown = Shading.Pack(Shading.Material('Solid'))
	buffer.writestring(unknown, 2, 'Nopex')
	check('unknown shader refused', (Shading.Unpack(unknown)) == nil)

	local bad = Shading.Pack(choice)
	buffer.writeu8(bad, buffer.len(bad) - 1, 99)
	local fixedUp, choiceIssues = Shading.Unpack(bad)
	check('out of range choice takes its default', fixedUp and fixedUp.Params.Mode == 'Scroll' and #choiceIssues == 1)
end

print(`{passed} passed, {failed} failed`)
if failed > 0 then process.exit(1) end
