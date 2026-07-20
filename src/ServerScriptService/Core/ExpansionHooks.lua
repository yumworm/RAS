--!strict
-- ExpansionHooks: the registry of extension points future systems plug into
-- WITHOUT modifying core logic. Nothing here implements gameplay -- these are
-- empty seams. A future module calls Register(...) at startup and the relevant
-- core service consults the hook when the time comes.
--
-- Priority ordering intentionally favours CONTENT over monetization: the content
-- seams below are the primary roadmap, monetization is secondary.
local ExpansionHooks = {}

-- Content-first hooks (primary roadmap):
--   Collections, Banners, Regions, Featured Streamers, Limited Streamers,
--   Seasonal Collections, Content Rotation, Garage, Upgrades, Prestige,
--   Limited Content, Cosmetics, Challenges, New Spin Machines, Seasonal Events.
-- Monetization hooks (secondary):
--   Gamepasses, Developer Products, Analytics, Leaderboards.
local registries = {
	-- Each future system appends functions here; core consults them where marked.
	RollModifiers = {}, -- fn(userId, modifiers) -> mutate luck/event/pity (RNG)
	IncomeMultipliers = {}, -- fn(userId) -> number, multiplied into income total
	OnStreamerObtained = {}, -- fn(userId, streamerId, isNew) content reactions
	OnSpinCompleted = {}, -- fn(userId, winner) challenges / quests / analytics
	OnCurrencyChanged = {}, -- fn(userId, amount, source) leaderboards / analytics
	FeatureUnlockRules = {}, -- fn(profile) -> unlock evaluation (Garage/Prestige gating)
}

-- Register a callback against a named hook. Returns a disconnect function so a
-- system can cleanly remove itself.
function ExpansionHooks.Register(hookName: string, callback)
	local list = registries[hookName]
	assert(list, "Unknown expansion hook: " .. tostring(hookName))
	table.insert(list, callback)
	return function()
		local index = table.find(list, callback)
		if index then
			table.remove(list, index)
		end
	end
end

-- Fire every callback registered for a hook (order of registration). Safe: a
-- throwing hook is isolated and never breaks core flow.
function ExpansionHooks.Fire(hookName: string, ...)
	local list = registries[hookName]
	if not list then
		return
	end
	for _, callback in ipairs(list) do
		pcall(callback, ...)
	end
end

-- Reduce a set of numeric-returning hooks into a single product (used for future
-- income multipliers). Returns 1 when nothing is registered.
function ExpansionHooks.Product(hookName: string, ...): number
	local list = registries[hookName]
	local product = 1
	if not list then
		return product
	end
	for _, callback in ipairs(list) do
		local ok, value = pcall(callback, ...)
		if ok and type(value) == "number" then
			product *= value
		end
	end
	return product
end

return ExpansionHooks
