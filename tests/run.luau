local roblox = require('@lune/roblox')
local process = require('@lune/process')

local Harness = require('./harness')
local Shading = Harness.Load()

local Color3, Vector3, Enum = roblox.Color3, roblox.Vector3, roblox.Enum

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

--// A fake instance: IsA by a class list, every property write counted
local function fake(classes, props)
	local writes = {}
	local object = setmetatable({}, {
		__index = function(_, key)
			if key == 'IsA' then
				return function(_, class)
					return table.find(classes, class) ~= nil
				end
			end
			return props[key]
		end,
		__newindex = function(_, key, value)
			props[key] = value
			writes[key] = (writes[key] or 0) + 1
		end,
	})
	return object, props, writes
end

local function part(position)
	return fake({ 'Part', 'BasePart' }, {
		Color = Color3.fromRGB(40, 40, 40),
		Material = Enum.Material.SmoothPlastic,
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

print(`{passed} passed, {failed} failed`)
if failed > 0 then process.exit(1) end
