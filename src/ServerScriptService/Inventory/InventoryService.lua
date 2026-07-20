--!strict
-- InventoryService: owns the stacked streamer inventory. Duplicates never create
-- a second entry -- they increment `amount` on the existing one. The sorted view
-- is produced here (server-side) so the UI never has to sort: always Secret ->
-- Common by rarity, then highest popularity, then alphabetical.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configuration = ReplicatedStorage.Modules.Configuration
local RarityConfig = require(Configuration.RarityConfig)
local StreamerDatabase = require(Configuration.StreamerDatabase)

local Server = script.Parent.Parent
local ProfileTemplate = require(Server.Data.ProfileTemplate)
local StateSync = require(Server.Core.StateSync)
local ExpansionHooks = require(Server.Core.ExpansionHooks)

local InventoryService = {}
local Services: any

function InventoryService.Init(services)
	Services = services
end

-- Build the client-facing display row for one owned streamer. Income comes from
-- IncomeService so the formula lives in exactly one place.
local function buildDisplayEntry(streamerId: number, entry)
	local streamer = StreamerDatabase.Get(streamerId)
	local rarity = RarityConfig.Get(streamer.rarity_tier)
	return {
		id = streamerId,
		name = streamer.name,
		rarity = streamer.rarity_tier,
		popularity = streamer.popularity_score,
		priority = rarity.Priority,
		amount = entry.amount,
		income = Services.IncomeService.GetStreamerIncome(streamerId, entry.amount),
		firstPulled = entry.firstPulled,
		recentPull = entry.recentPull,
		favorite = entry.favorite,
		locked = entry.locked,
	}
end

-- Always-sorted inventory snapshot: rarity priority desc, popularity desc, name asc.
function InventoryService.GetSortedInventory(userId: number)
	local profile = Services.ProfileService.Get(userId)
	if not profile then
		return {}
	end
	local list = {}
	for streamerId, entry in pairs(profile.inventory) do
		table.insert(list, buildDisplayEntry(streamerId, entry))
	end
	table.sort(list, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		if a.popularity ~= b.popularity then
			return a.popularity > b.popularity
		end
		return a.name < b.name
	end)
	return list
end

-- Award one copy of a streamer (stacking duplicates). Updates first/recent pull,
-- best-pull stat, collection discovery, and income -- then flags the (small)
-- sorted inventory for the client. Returns entry, isNew, streamer.
function InventoryService.AddStreamer(userId: number, streamerId: number)
	local profile = Services.ProfileService.Get(userId)
	local streamer = StreamerDatabase.Get(streamerId)
	if not profile or not streamer then
		return nil, false, nil
	end

	local now = os.time()
	local entry = profile.inventory[streamerId]
	local isNew = false
	if entry then
		entry.amount += 1
		entry.recentPull = now
	else
		entry = ProfileTemplate.NewInventoryEntry(now)
		profile.inventory[streamerId] = entry
		isNew = true
	end

	-- Best pull = highest popularity ever obtained.
	local best = profile.stats.bestPull
	if streamer.popularity_score > best.popularity then
		best.streamerId = streamerId
		best.rarity = streamer.rarity_tier
		best.popularity = streamer.popularity_score
		StateSync.Mark(userId, "bestPull", {
			streamerId = streamerId,
			rarity = streamer.rarity_tier,
			popularity = streamer.popularity_score,
			name = streamer.name,
		})
	end

	Services.CollectionService.OnStreamerObtained(userId, streamerId, isNew)
	Services.IncomeService.Recompute(userId)

	-- Content seam (Collections/Challenges/etc.); no-op today.
	ExpansionHooks.Fire("OnStreamerObtained", userId, streamerId, isNew)

	StateSync.Mark(userId, "inventory", InventoryService.GetSortedInventory(userId))
	return entry, isNew, streamer
end

return InventoryService
