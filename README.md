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

Some inputs fill themselves in when a shader declares them in `Inputs`. Anything set by hand for
these is overwritten:

| Input | Filled with |
|---|---|
| `Index`, `Count` | With `PerTarget`: the target's place in the list it was bound with (from 0), and how many there were |
| `X`, `Y`, `Z` | Where it is: each target with `PerTarget` (a part, or the attachment or part a light or effect hangs off), the anchor otherwise. Read each time it is drawn |
| `Distance` | Studs from the camera to the anchor, at each distance check |
| `Loudness` | `Config.Loudness()`, clamped to 0..1, once a frame |

The built-in shaders are:

| Shader | Look | Reads |
|---|---|---|
| `Solid` | One steady colour | |
| `Pulse` | One colour fading up and down | `Index` |
| `Strobe` | Bursts of short hard flashes | `Index` |
| `Chase` | Light running round in order, with a fading tail | `Index`, `Count` |
| `Alternate` | Two groups taking turns | `Group` |
| `Cycle` | Steps through a list of colours | `Index` |
| `Rainbow` | Rolls round the hue wheel | `Index` |
| `Flicker` | Unsteady, like a flame or a failing tube | `Index` |
| `Twinkle` | Random sparkles, the same on every client | `Index` |
| `Gradient` | Colours spread along a row, held or scrolling | `Index`, `Count` |
| `Wave` | Bands of light rolling along a world axis | `X`, `Y`, `Z` |
| `Heartbeat` | A double thump, then rest | `Index` |
| `Music` | Brightness and colour following `Config.Loudness` | `Loudness` |

`Twinkle`, `Gradient` and `Wave` are made for `PerTarget`.

## Types

`Shading.Types` holds every public type and no code, so it can be required alone for annotations,
without loading the library:

```lua
local Types = require(ReplicatedStorage.Shading.Types)
local function paint(material: Types.Material, binding: Types.Binding) end
```

The same types are exported from `Shading` itself.

## API

**Shaders:** `Shading.Shader`, `Shading.Get(name)`, `Shading.Names()`.

**Materials:**
- `Shading.Material(shader, params)` errors on bad data.
- `Shading.Sanitize(raw)` returns `material, issues`. It fills in defaults and drops unknown or
  invalid params, so use it on anything that came over the network or from saved data.
- `Shading.Equal`, `Shading.Decode`, and `Shading.Hex(value)`, which normalises a `Color3`,
  `#hex` or buffer to `'RRGGBB'`.
- `Shading.Pack(material)` returns a compact buffer, for remotes and saved data. It holds only the
  params not at their default: `Solid` at defaults is 8 bytes. `Shading.Unpack(buffer)` returns
  `material, issues` and is safe on anything: a short, garbled or unknown buffer gives `nil`, and
  the rest is sanitized. Numbers come back exact. Both ends need the same shader definitions,
  since params are written in each shader's `Order`.

**Drawing:**
- `Shading.Bind(material, targets, options?)` returns a binding with `SetMaterial`, `SetInput`,
  `Edit` and `Destroy`. A destroyed target is dropped from its binding, and a binding left with no
  targets destroys itself.
- `binding:Edit(fn)` changes the targets' authored look while bound: the targets are restored, `fn`
  runs (e.g. `part.Color = paint`), and what it leaves is what `Destroy` restores. Writing those
  properties directly instead would be drawn over, then undone by `Destroy`.
- A channel a shader leaves unset shows the target's authored look, so nothing carries over from a
  previous material.
- `Shading.BindTag(tag, material, options?)` and `Shading.BindQuery(query, material, options?)`
  return a group: each member gets its own binding when it joins, and gets its look back when it
  leaves. `BindTag` follows a CollectionService tag, and members must be under `Root`.
  `BindQuery` follows a
  [`CreateCollection`](https://create.roblox.com/docs/reference/engine/classes/CollectionService#CreateCollection)
  query such as `'Model.Car >> Part.Underglow'`. A group has `SetMaterial`, `SetInput` (both
  reach every member, present and later), `Get(instance)` for a member's binding, and `Destroy`.
  Group options take `Inputs`, `Emissive`, `PerTarget`, `TimeScale`, `TimeOffset` and:

  | Key | Default | Meaning |
  |---|---|---|
  | `Descendants` | `true` | Draw on a member's descendants too (a strip and its `SurfaceLight`, a whole model). They are gathered when it joins |
  | `Root` | Workspace | Only members under it count, so tagged templates in storage are never drawn on and cloned shaded |
  | `OnAdded` | | `(instance, binding)` for each member as it joins, e.g. `binding:SetInput('Index', instance:GetAttribute('Index'))`. Cannot yield |

  ```lua
  local underglow = Shading.BindQuery('Model.Car >> Part.Underglow', Shading.Material('Rainbow'), {
  	Emissive = true,
  	OnAdded = function(part, binding)
  		binding:SetInput('Index', part:GetAttribute('Index') or 0)
  	end,
  })
  ```
- `Shading.Apply(material, targets, options?, time?)` writes once with no binding. You can call it
  on the server, so the result replicates.
- `Shading.Evaluate(material, inputs?, time)` returns a material's output without drawing it, for
  previews and tests.
- Options take `Inputs`, `Emissive`, `Anchor`, and:
  - `PerTarget`: each target is evaluated on its own, with `Index` and `Count` filled in. A Chase
    along 20 parts is then one binding, not 20.
  - `TimeScale` and `TimeOffset`: the shader's clock is `serverTime * TimeScale + TimeOffset`.

  With `Emissive`, a lit part turns Neon in its colour, dimmed by Emission, and goes back to its
  authored look when dark. `Anchor` is the part distance is measured from.

**Writers:** `Shading.Writer(writer)` adds support for another instance class. Built in:

| Class | Writes |
|---|---|
| `BasePart` | `Color`, `Transparency`, `MaterialVariant`, and Neon while lit when `Emissive` |
| `Light` | `Color`, `Brightness` (authored brightness at full emission), `Enabled`; off past `LightRadius` |
| `Beam`, `Trail`, `ParticleEmitter` | `Color` and `Transparency` as flat sequences, `Brightness` by emission, off while dark |
| `Highlight` | `FillColor` and `OutlineColor`; both fade out as emission falls; `Transparency` is the fill's |
| `Decal` (and `Texture`) | `Color3` tint, dimmed by emission when `Emissive`; `Transparency` |

 A writer captures what it changes when a binding starts and restores
it when the binding is destroyed. `Write(target, out, cache, base, options, far, frame)` is given
`frame`, the output worked out once per draw: `Emission` and `Transparency` levelled, `ColorKey`
packed. A draw whose levelled output matches what the targets already show writes nothing. Any
key a shader sets on `out` beyond the built-in channels is compared as it is, so a game's own
writers are still redrawn when it changes.

**Loop:** `Shading.Stats()` returns `{ Bindings, Evaluated, Written }` for the last frame, where
`Written` counts targets. `Shading.Step(time, clock, cameraPosition, lookVector?)` runs the
renderer once by hand, which is how the tests drive it.

## Settings

`Shading.Config` is read live, so it can be changed at any time:

| Key | Default | Meaning |
|---|---|---|
| `LightRadius` | 150 | Studs from the camera past which lights switch off |
| `CullRadius` | 400 | Studs from the camera past which a binding holds its last look |
| `RangePeriod` | 0.25 | Seconds between distance checks (staggered per binding) |
| `FarRate` | 15 | Evaluations per second at most past `LightRadius`; `nil` for no cap |
| `ViewCull` | `true` | Bindings behind the camera hold their last look, unless they have a light that is still on |
| `ViewMargin` | 16 | Studs behind the camera plane an anchor must be before it is held |
| `Budget` | `nil` | Targets written per frame at most; bindings left waiting go first next frame |
| `Loudness` | `nil` | `() -> number`, read once a frame for the `Loudness` input, e.g. `function() return sound.PlaybackLoudness / 500 end` |
| `Profiler` | `debug.profilebegin` / `debug.profileend` | `{ Begin, End }` pair called around each frame's work |

## Development

Tools are pinned in `aftman.toml`. `rojo build -o Shading.rbxm` builds the model;
`stylua src` and `selene src` format and lint it. `lune run tests/run`, run from the repository
root, runs the test suite against fake instances.
