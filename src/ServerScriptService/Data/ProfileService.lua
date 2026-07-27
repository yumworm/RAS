--!strict
-- ProfileService: the ONE owner of player save data. It loads, deeply validates
-- and repairs, caches in memory, and writes back. No other script touches the
-- DataStore or invents its own player data.
--
-- Validation philosophy: never trust a save. Every value is checked on load --
-- missing, wrong type, negative, out of range, or referencing an unknown streamer
-- is repaired automatically. A corrupted save can never crash the game; if a
-- field can't be salvaged it falls back to a safe default, and if the whole load
-- errors we hand back defaults AND flag the session so SaveManager won't overwrite
-- the real (possibly recoverable) data.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = ReplicatedStorage.Modules.Configuration
local GameConfig = require(Configuration.GameConfig)
local RarityConfig = require(Configuration.RarityConfig)
local StreamerDatabase = require(Configuration.StreamerDatabase)

local Data = script.Parent
local ProfileTemplate = require(Data.ProfileTemplate)
local Utilities = script.Parent.Parent.Utilities
local TableUtil = require(Utilities.TableUtil)
local Logger = require(Utilities.Logger)

local ProfileService = {}

local STORE_NAME = "RollAStream_Profiles_v2"
local profileStore = DataStoreService:GetDataStore(STORE_NAME)

-- userId -> profile
local profiles = {}

--------------------------------------------------------------------------------
-- Sanitizers
--------------------------------------------------------------------------------

local function sanitizeNumber(value, default: number, min: number?, max: number?): number
	if typeof(value) ~= "number" or value ~= value then -- not a number or NaN
		return default
	end
	if min and value < min then
		value = min
	end
	if max and value > max then
		value = max
	end
	return value
end

local function sanitizeInt(value, default: number, min: number?, max: number?): number
	return math.floor(sanitizeNumber(value, default, min, max))
end

--------------------------------------------------------------------------------
-- Per-subtree repair
--------------------------------------------------------------------------------

local function repairEconomy(economy)
	economy.currency = sanitizeNumber(economy.currency, 0, 0, GameConfig.EconomyCap)
	economy.lifetimeEarned = sanitizeNumber(economy.lifetimeEarned, 0, 0)
	economy.lifetimeSpent = sanitizeNumber(economy.lifetimeSpent, 0, 0)
	economy.highestCurrency = sanitizeNumber(economy.highestCurrency, 0, 0, GameConfig.EconomyCap)
	economy.highestIncome = sanitizeNumber(economy.highestIncome, 0, 0)
	economy.highestSingleReward = sanitizeNumber(economy.highestSingleReward, 0, 0)
	economy.largestPurchase = sanitizeNumber(economy.largestPurchase, 0, 0)
	economy.premiumCurrency = sanitizeNumber(economy.premiumCurrency, 0, 0)
	-- Keep the derived invariant sane.
	if economy.highestCurrency < economy.currency then
		economy.highestCurrency = economy.currency
	end
end

local function repairStats(stats)
	stats.totalSpins = sanitizeInt(stats.totalSpins, 0, 0)
	stats.totalPlayTime = sanitizeNumber(stats.totalPlayTime, 0, 0)

	local best = stats.bestPull
	best.streamerId = sanitizeInt(best.streamerId, 0, 0)
	best.popularity = sanitizeInt(best.popularity, 0, 0, 100)
	if best.streamerId ~= 0 and not StreamerDatabase.Get(best.streamerId) then
		-- Best pull references a streamer that no longer exists -> clear it.
		best.streamerId, best.rarity, best.popularity = 0, "", 0
	end
	if best.rarity ~= "" and not RarityConfig.IsValidTier(best.rarity) then
		best.rarity = ""
	end
end

-- Inventory is a dynamic map keyed by streamer id; TableUtil.Reconcile can't
-- handle it, so it's repaired entry-by-entry here.
local function repairInventory(rawInventory, now: number)
	local repaired = {}
	if type(rawInventory) ~= "table" then
		return repaired
	end
	for key, entry in pairs(rawInventory) do
		local id = tonumber(key)
		local streamer = id and StreamerDatabase.Get(id)
		if streamer and type(entry) == "table" then
			local clean = TableUtil.Reconcile(entry, ProfileTemplate.NewInventoryEntry(now))
			clean.amount = sanitizeInt(clean.amount, 1, 1) -- never 0 or negative
			clean.firstPulled = sanitizeNumber(clean.firstPulled, now, 0)
			clean.recentPull = sanitizeNumber(clean.recentPull, now, 0)
			clean.upgradeLevel = sanitizeInt(clean.upgradeLevel, 0, 0)
			clean.xp = sanitizeNumber(clean.xp, 0, 0)
			repaired[id] = clean
		end
	end
	return repaired
end

-- Donation stats are uncapped flex values (never clamped to the Bucks economy cap)
-- and only ever increase. `recentReceipts` is a dynamic array of PurchaseId strings
-- so, like inventory/discovered, it is repaired explicitly rather than via Reconcile
-- (which -- given an empty-array template -- would silently wipe it and destroy the
-- ProcessReceipt idempotency guard).
local RECENT_RECEIPTS_CAP = 50

local function repairDonation(donation, raw)
	local source = type(raw) == "table" and raw or {}
	donation.robuxDonatedLifetime = sanitizeInt(source.robuxDonatedLifetime, 0, 0)
	donation.donationPurchaseCount = sanitizeInt(source.donationPurchaseCount, 0, 0)
	donation.biggestRobuxDonation = sanitizeInt(source.biggestRobuxDonation, 0, 0)

	-- Rebuild the recent-receipt ring: string entries only, keep the last N.
	local receipts = {}
	local rawReceipts = source.recentReceipts
	if type(rawReceipts) == "table" then
		for _, id in ipairs(rawReceipts) do
			if type(id) == "string" then
				table.insert(receipts, id)
			elseif type(id) == "number" then
				table.insert(receipts, tostring(id))
			end
		end
	end
	while #receipts > RECENT_RECEIPTS_CAP do
		table.remove(receipts, 1)
	end
	donation.recentReceipts = receipts

	-- Keep the derived invariant sane: biggest can't exceed the lifetime total.
	if donation.biggestRobuxDonation > donation.robuxDonatedLifetime then
		donation.biggestRobuxDonation = donation.robuxDonatedLifetime
	end
end

local function repairCollection(collection, inventory, now: number)
	local discovered = {}
	local raw = collection.discovered
	if type(raw) == "table" then
		for key, ts in pairs(raw) do
			local id = tonumber(key)
			if id and StreamerDatabase.Get(id) then
				discovered[id] = sanitizeNumber(ts, now, 0)
			end
		end
	end
	-- Anything owned must count as discovered (repair inconsistent saves).
	for id in pairs(inventory) do
		if not discovered[id] then
			discovered[id] = now
		end
	end
	collection.discovered = discovered
end

--------------------------------------------------------------------------------
-- Full validate + repair
--------------------------------------------------------------------------------

function ProfileService.ValidateAndRepair(rawData)
	local now = os.time()
	-- Reconcile the fixed-shape parts against the template (adds missing fields,
	-- drops junk, fixes types) -- but preserve dynamic maps to repair separately.
	local rawInventory = (type(rawData) == "table") and rawData.inventory or nil
	local rawDiscovered = (type(rawData) == "table" and type(rawData.collection) == "table")
			and rawData.collection.discovered
		or nil
	local rawDonation = (type(rawData) == "table") and rawData.donation or nil

	local profile = TableUtil.Reconcile(rawData, ProfileTemplate.Default())

	profile.schemaVersion = ProfileTemplate.CURRENT_VERSION
	-- lastLogout (Phase 6): a unix second stamp. Clamp to [0, now] so a corrupt,
	-- negative, NaN, inf, or future value can never produce a bogus "time away"
	-- (a future logout would yield negative away time). A capped value just means the
	-- welcome-back panel is skipped, never that inventory/currency is touched.
	profile.lastLogout = sanitizeInt(profile.lastLogout, 0, 0, now)
	repairEconomy(profile.economy)
	repairStats(profile.stats)
	repairDonation(profile.donation, rawDonation)
	profile.inventory = repairInventory(rawInventory, now)
	profile.collection.discovered = rawDiscovered
	repairCollection(profile.collection, profile.inventory, now)

	return profile
end

--------------------------------------------------------------------------------
-- Load / Save / cache
--------------------------------------------------------------------------------

-- Returns (profile, ok). ok=false means the underlying load errored and the
-- profile is a *safe default* -- callers should refuse to save over it.
function ProfileService.LoadAsync(userId: number)
	local key = "Player_" .. userId
	local success, result = pcall(function()
		return profileStore:GetAsync(key)
	end)

	if not success then
		Logger.Error("Profile", string.format("Load failed for %d: %s", userId, tostring(result)))
		local safe = ProfileService.ValidateAndRepair(nil)
		profiles[userId] = safe
		return safe, false
	end

	-- result may be nil (brand new player) -> validate produces clean defaults.
	local profile = ProfileService.ValidateAndRepair(result)
	profiles[userId] = profile
	Logger.Info("Profile", string.format("Loaded profile for %d (new=%s)", userId, tostring(result == nil)))
	return profile, true
end

function ProfileService.Get(userId: number)
	return profiles[userId]
end

-- Actual write. SaveManager owns *when* this is called (dedupe, retry); this just
-- performs one attempt and returns whether it succeeded.
function ProfileService.SaveAsync(userId: number): boolean
	local profile = profiles[userId]
	if not profile then
		return false
	end
	local key = "Player_" .. userId
	local success, err = pcall(function()
		profileStore:SetAsync(key, profile)
	end)
	if not success then
		Logger.Warn("Profile", string.format("Save attempt failed for %d: %s", userId, tostring(err)))
	end
	return success
end

-- Credit a confirmed Robux donation to a player, exactly once, whether they are
-- online or offline. Idempotency is guaranteed atomically: the PurchaseId is
-- checked against (and appended to) the profile's recentReceipts ring INSIDE the
-- same OrderedDataStore-style UpdateAsync transaction that applies the credit, so a
-- duplicate ProcessReceipt retry can never double-credit even if the separate
-- receipt-store write was lost.
--
-- Returns (newLifetime, applied, ok):
--   ok=false     -> transient DataStore failure; the caller must return
--                   NotProcessedYet so Roblox retries later.
--   applied=false-> this PurchaseId was already credited earlier (no change made).
--   applied=true -> the credit was freshly applied; newLifetime is the new total.
function ProfileService.CreditDonation(userId: number, amount: number, purchaseId: string)
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0, false, false
	end
	amount = math.floor(amount)

	local key = "Player_" .. userId
	local newLifetime = 0
	local applied = false

	local success, err = pcall(function()
		profileStore:UpdateAsync(key, function(old)
			-- Repair defends against a nil (brand-new) or corrupt on-disk save and
			-- guarantees the donation subtree (incl. recentReceipts) exists.
			local profile = ProfileService.ValidateAndRepair(old)
			local donation = profile.donation

			-- Idempotency guard: already processed -> abort the write, no credit.
			for _, id in ipairs(donation.recentReceipts) do
				if id == purchaseId then
					applied = false
					newLifetime = donation.robuxDonatedLifetime
					return nil -- cancel UpdateAsync; on-disk value is unchanged
				end
			end

			donation.robuxDonatedLifetime += amount
			donation.donationPurchaseCount += 1
			if amount > donation.biggestRobuxDonation then
				donation.biggestRobuxDonation = amount
			end
			table.insert(donation.recentReceipts, purchaseId)
			while #donation.recentReceipts > RECENT_RECEIPTS_CAP do
				table.remove(donation.recentReceipts, 1)
			end

			applied = true
			newLifetime = donation.robuxDonatedLifetime
			return profile
		end)
	end)

	if not success then
		Logger.Error("Donation", string.format("CreditDonation UpdateAsync failed for %d: %s", userId, tostring(err)))
		return 0, false, false
	end

	-- If the donor is online, mirror the credit into their live in-memory profile so
	-- the running session (and its next autosave) reflect the new totals and keep the
	-- idempotency guard consistent with disk.
	local live = profiles[userId]
	if live and applied then
		local d = live.donation
		d.robuxDonatedLifetime = newLifetime
		d.donationPurchaseCount += 1
		if amount > d.biggestRobuxDonation then
			d.biggestRobuxDonation = amount
		end
		table.insert(d.recentReceipts, purchaseId)
		while #d.recentReceipts > RECENT_RECEIPTS_CAP do
			table.remove(d.recentReceipts, 1)
		end
	end

	return newLifetime, applied, true
end

-- Read-only donation snapshot for an online player (safe defaults if absent).
function ProfileService.GetDonationStats(userId: number)
	local profile = profiles[userId]
	if not profile then
		return { robuxDonatedLifetime = 0, donationPurchaseCount = 0, biggestRobuxDonation = 0 }
	end
	local d = profile.donation
	return {
		robuxDonatedLifetime = d.robuxDonatedLifetime,
		donationPurchaseCount = d.donationPurchaseCount,
		biggestRobuxDonation = d.biggestRobuxDonation,
	}
end

function ProfileService.Unload(userId: number)
	profiles[userId] = nil
end

function ProfileService.GetActiveUserIds()
	local ids = {}
	for userId in pairs(profiles) do
		table.insert(ids, userId)
	end
	return ids
end

return ProfileService
