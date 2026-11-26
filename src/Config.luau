--!strict

local Config = {}

--// Light bindings LOD OUT distance (camera)
Config.LightRadius = 150

--// Global Binding LOD OUT distance (camera)
Config.CullRadius = 400

--// Distance check frequency
Config.RangePeriod = 0.25

--// Evaluations per second at most past LightRadius; nil for no cap
Config.FarRate = 15 :: number?

--// Bindings behind the camera hold their last look, unless they have a light that is still on
Config.ViewCull = true

--// Studs behind the camera plane a binding's anchor must be before it is held
Config.ViewMargin = 16

--// Targets written per frame at most; due bindings past it wait for the next frame, in turn. nil for no cap.
Config.Budget = nil :: number?

--// Read once a frame for shaders with a Loudness input, 0..1; e.g. function() return sound.PlaybackLoudness / 500 end
Config.Loudness = nil :: (() -> number)?

--// Brackets the renderer's work each frame; a game can set its own pair on Shading.Config
Config.Profiler = {
	Begin = debug.profilebegin :: (label: string) -> (),
	End = debug.profileend :: () -> (),
}

return Config
