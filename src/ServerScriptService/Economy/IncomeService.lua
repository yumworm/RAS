--!strict
-- IncomeService: the ONE place income-per-second is calculated. It recomputes only
-- when the inventory actually changes (obtained / removed / future upgrade / boost),
-- caches the result in Runtime, and never recalculates unchanged values on a loop.
--
-- Formula (single source of truth):
--   perStreamer = base_income * rarity.IncomeScaling * amount
--   total       = sum(perStreamer) * GlobalIncomeMultiplier * futureMultipliers
-- Tuned so a maxed roster plus future upgrade/prestige multipliers approaches the
-- $10T endgame, never blowing past it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configuration = ReplicatedStorage.Modules.Configuration
local GameConfig = require(Configuration.GameConfig)
local RarityConfig = require(Configuration.RarityConfig)
local StreamerDatabase = require(Configuration.StreamerDatabase)

local Server = script.Parent.Parent
local Runtime = require(Server.Core.Runtime)
local StateSync = require(Server.Core.StateSync)
local ExpansionHooks = require(Server.Core.ExpansionHooks)

local IncomeService = {}
local Services: any

function IncomeService.Init(services)
	Services = services
end

-- Income contributed by owning `amount` copies of one streamer. Also used to
-- build per-row income for the client so display never re-derives the formula.
function IncomeService.GetStreamerIncome(streamerId: number, amount: number): number
	local streamer = StreamerDatabase.Get(streamerId)
	if not streamer or amount <= 0 then
		return 0
	end
	local rarity = RarityConfig.Get(streamer.rarity_tier)
	return streamer.base_income * rarity.IncomeScaling * amount
end

-- Recompute total income/sec from the current inventory, cache it, update the
-- lifetime high-water mark, and mark it for the client. Call this after any
-- inventory mutation.
function IncomeService.Recompute(userId: number): number
	local profile = Services.ProfileService.Get(userId)
	local runtime = Runtime.Get(userId)
	if not profile then
		return 0
	end

	local total = 0
	for streamerId, entry in pairs(profile.inventory) do
		total += IncomeService.GetStreamerIncome(streamerId, entry.amount)
	end

	-- Future per-player multipliers (upgrades, boosts, events, gamepasses) fold in
	-- here through the IncomeMultipliers hook; it returns 1 while nothing is
	-- registered, so today this is exactly the global multiplier.
	total *= GameConfig.GlobalIncomeMultiplier
	total *= ExpansionHooks.Product("IncomeMultipliers", userId)

	if runtime then
		runtime.incomePerSecond = total
	end
	if total > profile.economy.highestIncome then
		profile.economy.highestIncome = total
	end

	StateSync.Mark(userId, "income", total)
	return total
end

function IncomeService.GetIncome(userId: number): number
	local runtime = Runtime.Get(userId)
	return runtime and runtime.incomePerSecond or 0
end

return IncomeService
