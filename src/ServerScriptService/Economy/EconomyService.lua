--!strict
-- EconomyService: the ONE gateway for changing a player's money. Passive income,
-- future rewards, Garage purchases, Gamepass payouts -- everything flows through
-- AddCurrency / SpendCurrency. Nothing edits `profile.economy.currency` directly.
--
-- All values respect the project-wide $10T cap: currency can never exceed it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Modules.Configuration.GameConfig)

local Server = script.Parent.Parent
local StateSync = require(Server.Core.StateSync)
local ExpansionHooks = require(Server.Core.ExpansionHooks)

local EconomyService = {}
local Services: any

function EconomyService.Init(services)
	Services = services
end

function EconomyService.GetCurrency(userId: number): number
	local profile = Services.ProfileService.Get(userId)
	return profile and profile.economy.currency or 0
end

-- Add money from any source. Clamps to the economy cap and keeps all the derived
-- "highest / lifetime" economy stats in sync. Returns the amount actually gained
-- (which can be less than `amount` if the cap was hit).
function EconomyService.AddCurrency(userId: number, amount: number, source: string?): number
	local profile = Services.ProfileService.Get(userId)
	if not profile or typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0
	end

	local eco = profile.economy
	local before = eco.currency
	eco.currency = math.min(before + amount, GameConfig.EconomyCap)
	local gained = eco.currency - before

	eco.lifetimeEarned += gained
	if amount > eco.highestSingleReward then
		eco.highestSingleReward = amount
	end
	if eco.currency > eco.highestCurrency then
		eco.highestCurrency = eco.currency
	end

	StateSync.Mark(userId, "currency", eco.currency)

	if Services.SessionTracker then
		Services.SessionTracker.OnEarned(userId, gained, eco.currency)
	end
	-- Seam for future leaderboards / analytics (no-op today).
	ExpansionHooks.Fire("OnCurrencyChanged", userId, gained, source)
	return gained
end

-- Spend money. Returns true only if the player could afford it (server-authoritative
-- affordability check for future purchases).
function EconomyService.SpendCurrency(userId: number, amount: number, reason: string?): boolean
	local profile = Services.ProfileService.Get(userId)
	if not profile or typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false
	end
	local eco = profile.economy
	if eco.currency < amount then
		return false
	end
	eco.currency -= amount
	eco.lifetimeSpent += amount
	if amount > eco.largestPurchase then
		eco.largestPurchase = amount
	end
	StateSync.Mark(userId, "currency", eco.currency)
	return true
end

return EconomyService
