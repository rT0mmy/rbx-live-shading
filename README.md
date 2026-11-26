# Shading

Shaders and materials for Roblox instances.

- A **shader** is Lua code that works out an instance's look each frame: `Color`, `Emission`,
  `Transparency`, `MaterialVariant`.
- A **material** is plain, JSON-friendly data: a shader name plus its parameters. It can be saved,
  sent over the network and sanitized anywhere.
- A **binding** draws a material on a set of parts and lights until you destroy it.

Only clients draw. The render loop starts on the first `Bind` and never runs on the server, where
its writes would replicate.

```lua
local Shading = require(ReplicatedStorage.Shading)

Shading.Shader {
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
```

## Shaders

`Shading.Shader(def)` registers a shader and errors on a malformed definition. `def` takes:

| Key | Meaning |
|---|---|
| `Name` | Unique name; materials refer to it |
| `Description` | Optional text for editors |
| `Params` | Parameters by name, each `{ Kind = 'Number' \| 'Color' \| 'Colors' \| 'Bool' \| 'Choice', Default, ... }` |
| `Order` | Optional order of the params for editors |
| `Inputs` | Per-binding numbers with their defaults (e.g. `Index`, `Count`, `Group`) |
| `Static` | Evaluated only when the material or an input changes, not every frame |
| `Rate` | Cap on evaluations per second |
| `Evaluate` | `(params, inputs, serverTime, out)`: fills `out` |

Colours are `'RRGGBB'` hex strings in material data and arrive in `Evaluate` as `Color3`. Server
time is about 1.8e9, so take a phase `% 1` before multiplying it by 2π. If a shader errors, its
binding stops until it is given a new material.

The built-in shaders are `Solid`, `Pulse`, `Strobe`, `Chase`, `Alternate`, `Cycle` and `Rainbow`.

## API

**Shaders:** `Shading.Shader`, `Shading.Get(name)`, `Shading.Names()`.

**Materials:**
- `Shading.Material(shader, params)` errors on bad data.
- `Shading.Sanitize(raw)` returns `material, issues`. It fills in defaults and drops unknown or
  invalid params, so use it on anything that came over the network or from saved data.
- `Shading.Equal`, `Shading.Decode`, and `Shading.Hex(value)`, which normalises a `Color3`,
  `#hex` or buffer to `'RRGGBB'`.

**Drawing:**
- `Shading.Bind(material, targets, options?)` returns a binding with `SetMaterial`, `SetInput`
  and `Destroy`.
- `Shading.Apply(material, targets, options?, time?)` writes once with no binding. You can call it
  on the server, so the result replicates.
- `Shading.Evaluate(material, inputs?, time)` returns a material's output without drawing it, for
  previews and tests.
- Options take `Inputs`, `Emissive` and `Anchor`. With `Emissive`, a lit part turns Neon in its
  colour, dimmed by Emission, and goes back to its authored look when dark. `Anchor` is the part
  distance is measured from.

**Writers:** `Shading.Writer(writer)` adds support for another instance class. `BasePart` and
`Light` writers come built in. A writer captures what it changes when a binding starts and restores
it when the binding is destroyed.

**Loop:** `Shading.Stats()` returns `{ Bindings, Evaluated }`. `Shading.Step(time, clock,
cameraPosition)` runs the renderer once by hand, which is how the tests drive it.

## Settings

`Shading.Config` is read live, so it can be changed at any time:

| Key | Default | Meaning |
|---|---|---|
| `LightRadius` | 150 | Studs from the camera past which lights switch off |
| `CullRadius` | 400 | Studs from the camera past which a binding holds its last look |
| `RangePeriod` | 0.25 | Seconds between distance checks (staggered per binding) |
| `Profiler` | `debug.profilebegin` / `debug.profileend` | `{ Begin, End }` pair called around each frame's work |

## Development

Tools are pinned in `aftman.toml`. `rojo build -o Shading.rbxm` builds the model;
`stylua src` and `selene src` format and lint it. `lune run tests/run`, run from the repository
root, runs the test suite against fake instances.
