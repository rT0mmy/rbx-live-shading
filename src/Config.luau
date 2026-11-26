--!strict

local Config = {}

--// Light bindings LOD OUT distance (camera)
Config.LightRadius = 150

--// Global Binding LOD OUT distance (camera)
Config.CullRadius = 400

--// Distance check frequency
Config.RangePeriod = 0.25

--// Brackets the renderer's work each frame; a game can set its own pair on Shading.Config
Config.Profiler = {
	Begin = debug.profilebegin :: (label: string) -> (),
	End = debug.profileend :: () -> (),
}

return Config
