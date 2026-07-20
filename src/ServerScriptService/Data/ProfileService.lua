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

	local profile = TableUtil.Reconcile(rawData, ProfileTemplate.Default())

	profile.schemaVersion = ProfileTemplate.CURRENT_VERSION
	repairEconomy(profile.economy)
	repairStats(profile.stats)
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
