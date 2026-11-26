--!strict
--!native

--Output

local Common = require(`@self/Common`)

local Writers = {}

export type Options = Common.Options
export type Writer = Common.Writer
export type Frame = Common.Frame

Writers.Prepare = Common.Prepare

--// Broadest first: a later registration is tried before an earlier one
local effect = require(`@self/Effect`)

const BUILT_IN: { Writer } = {
	require(`@self/Part`),
	require(`@self/Light`),
	require(`@self/Decal`), -- Texture too
	require(`@self/Highlight`),
	effect('Beam'),
	effect('Trail'),
	effect('ParticleEmitter'),
}

local list: { Writer } = {}

--[[
	Adds a writer for a class of instance. Later registrations are tried first, so a narrower class
	can be given its own writer after a broader one.

	@param writer Writer
	@return nil
--]]
function Writers.Register(writer: Writer)
	table.insert(list, 1, writer)
end

--[[
	The writer for an instance, or nil when nothing can draw on it

	@param instance Instance
	@return Writer?
--]]
function Writers.For(instance: Instance): Writer?
	for _, writer in list do
		if instance:IsA(writer.Class) then return writer end
	end

	return nil
end

for _, writer in BUILT_IN do
	Writers.Register(writer)
end

return Writers
