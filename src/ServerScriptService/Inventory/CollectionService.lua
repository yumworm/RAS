--!strict
-- CollectionService: tracks collection progress. Recomputes the summary only when
-- the inventory changes (never on a loop). Knows total vs collected vs missing,
-- completion %, first-discovery dates, duplicate count, and highest rarity owned.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configuration = ReplicatedStorage.Modules.Configuration
local RarityConfig = require(Configuration.RarityConfig)
local StreamerDatabase = require(Configuration.StreamerDatabase)

local Server = script.Parent.Parent
local StateSync = require(Server.Core.StateSync)

local CollectionService = {}
local Services: any

function CollectionService.Init(services)
	Services = services
end

-- Compute the full collection summary from the current inventory.
function CollectionService.GetSummary(userId: number)
	local profile = Services.ProfileService.Get(userId)
	local total = StreamerDatabase.Count
	if not profile then
		return { collected = 0, total = total, missing = total, percentage = 0, duplicates = 0, highestRarity = "" }
	end

	local collected = 0
	local totalCopies = 0
	local highestPriority = 0
	local highestRarity = ""
	for streamerId, entry in pairs(profile.inventory) do
		collected += 1
		totalCopies += entry.amount
		local streamer = StreamerDatabase.Get(streamerId)
		if streamer then
			local rarity = RarityConfig.Get(streamer.rarity_tier)
			if rarity.Priority > highestPriority then
				highestPriority = rarity.Priority
				highestRarity = streamer.rarity_tier
			end
		end
	end

	return {
		collected = collected,
		total = total,
		missing = total - collected,
		percentage = if total > 0 then (collected / total) * 100 else 0,
		duplicates = totalCopies - collected, -- extra copies beyond the first
		highestRarity = highestRarity,
	}
end

-- Called by InventoryService whenever a streamer is obtained. Records the first
-- discovery date and re-marks the (cheap) summary for the client.
function CollectionService.OnStreamerObtained(userId: number, streamerId: number, isNew: boolean)
	local profile = Services.ProfileService.Get(userId)
	if not profile then
		return
	end
	if isNew and not profile.collection.discovered[streamerId] then
		profile.collection.discovered[streamerId] = os.time()
	end
	StateSync.Mark(userId, "collection", CollectionService.GetSummary(userId))
end

return CollectionService
