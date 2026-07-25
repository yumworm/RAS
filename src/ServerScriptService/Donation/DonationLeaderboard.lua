--!strict
-- DonationLeaderboard: owns the global, all-time Top 100 donors board. It is the
-- ONLY place the donor OrderedDataStore is read or written. RobuxDonationSystem
-- tells it a confirmed new lifetime total (SubmitScore); it never runs a purchase or
-- touches a profile.
--
-- Read strategy: the sorted board is fetched once per interval into an in-memory
-- cache. Every client request and the physical stand board are served from that
-- cache, so 10 players opening the board is 0 extra OrderedDataStore reads, not 10.
-- On an OrderedDataStore outage the last good cache is kept and flagged Stale rather
-- than hard-erroring gameplay.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DonationConfig = require(ReplicatedStorage.Modules.Configuration.DonationConfig)

local Server = script.Parent.Parent
local Logger = require(Server.Utilities.Logger)

local DonationLeaderboard = {}
local Services: any

local orderedStore = DataStoreService:GetOrderedDataStore(DonationConfig.OrderedDataStoreName)

-- In-memory cache of the current board snapshot.
local cache = {
	Entries = {}, -- array of { Rank, UserId, Username, RobuxDonated }
	GeneratedAt = 0,
	Stale = false,
}
local rankByUserId = {} -- userId -> rank, rebuilt each refresh (top-N only)
local usernameCache = {} -- userId -> resolved username string

-- userId -> pending lifetime value that still needs to land in the OrderedDataStore
-- (populated when a SubmitScore write fails; drained on the refresh tick).
local pendingScoreWrites = {}
local dirty = false -- set by MarkDirty to pull the next refresh forward

function DonationLeaderboard.Init(services)
	Services = services
end

--------------------------------------------------------------------------------
-- Username resolution (cached; never fatal)
--------------------------------------------------------------------------------

local function resolveUsername(userId: number): string
	local cached = usernameCache[userId]
	if cached then
		return cached
	end
	-- Prefer an online player's name (no API call needed).
	local online = Players:GetPlayerByUserId(userId)
	if online then
		usernameCache[userId] = online.Name
		return online.Name
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" and name ~= "" then
		usernameCache[userId] = name
		return name
	end
	-- Fallback: never break the board over a name lookup.
	return DonationConfig.Text.UsernameFallbackPrefix .. tostring(userId)
end

--------------------------------------------------------------------------------
-- OrderedDataStore write (never decreases a stored value)
--------------------------------------------------------------------------------

-- One write attempt: store max(existing, newLifetime) so a stale/retried write can
-- never lower someone's board score. Returns true on success.
local function writeScore(userId: number, newLifetime: number): boolean
	local key = tostring(userId)
	local target = math.floor(newLifetime)
	local ok, err = pcall(function()
		orderedStore:UpdateAsync(key, function(old)
			if type(old) == "number" and old >= target then
				return old -- keep the higher existing value
			end
			return target
		end)
	end)
	if not ok then
		Logger.Warn("Donation", string.format("OrderedDataStore write failed for %d: %s", userId, tostring(err)))
	end
	return ok
end

-- Called by RobuxDonationSystem after a durable profile credit. Best-effort: if the
-- write fails the value is queued and retried on the next refresh tick, so the board
-- eventually catches up without ever rolling back or double-applying the profile
-- credit (the profile is the source of truth; this store is only the ranking index).
function DonationLeaderboard.SubmitScore(userId: number, newLifetime: number)
	if not writeScore(userId, newLifetime) then
		-- Keep only the highest pending value for this user.
		local existing = pendingScoreWrites[userId]
		if not existing or newLifetime > existing then
			pendingScoreWrites[userId] = newLifetime
		end
	end
	DonationLeaderboard.MarkDirty()
end

-- Retry any queued score writes that previously failed.
local function drainPendingWrites()
	for userId, value in pairs(pendingScoreWrites) do
		if writeScore(userId, value) then
			pendingScoreWrites[userId] = nil
		end
	end
end

--------------------------------------------------------------------------------
-- Refresh the cached Top-N board
--------------------------------------------------------------------------------

local function refresh()
	drainPendingWrites()

	local limit = math.clamp(DonationConfig.MaxLeaderboardEntries, 1, 100)
	local ok, pages = pcall(function()
		return orderedStore:GetSortedAsync(false, limit) -- descending
	end)

	if not ok then
		-- Keep the last good cache; just flag it stale so the UI can say so.
		cache.Stale = true
		Logger.Warn("Donation", string.format("Leaderboard refresh failed: %s", tostring(pages)))
		return
	end

	local entries = {}
	local newRankByUserId = {}
	local okPage, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if okPage and type(page) == "table" then
		for index, item in ipairs(page) do
			local userId = tonumber(item.key)
			local value = tonumber(item.value)
			if userId and value then
				local rank = index
				table.insert(entries, {
					Rank = rank,
					UserId = userId,
					Username = resolveUsername(userId),
					RobuxDonated = value,
				})
				newRankByUserId[userId] = rank
			end
		end
	end

	cache = {
		Entries = entries,
		GeneratedAt = os.time(),
		Stale = false,
	}
	rankByUserId = newRankByUserId
end

--------------------------------------------------------------------------------
-- Snapshots served to clients + the stand board
--------------------------------------------------------------------------------

-- Shallow board snapshot (shared by every viewer). Entries are copied so a consumer
-- can never mutate the cache.
function DonationLeaderboard.GetSnapshot()
	local entriesCopy = {}
	for i, entry in ipairs(cache.Entries) do
		entriesCopy[i] = {
			Rank = entry.Rank,
			UserId = entry.UserId,
			Username = entry.Username,
			RobuxDonated = entry.RobuxDonated,
		}
	end
	return {
		Entries = entriesCopy,
		GeneratedAt = cache.GeneratedAt,
		Stale = cache.Stale,
	}
end

-- Per-player snapshot: the shared board plus this player's own total and rank. Rank
-- is resolved from the cached Top-N only (no expensive full-store scan); a donor
-- outside the Top-N gets a nil rank, which the UI shows as "Unranked".
function DonationLeaderboard.GetSnapshotForPlayer(userId: number)
	local snapshot = DonationLeaderboard.GetSnapshot()
	local stats = Services.ProfileService.GetDonationStats(userId)
	snapshot.LocalUserId = userId
	snapshot.LocalTotal = stats.robuxDonatedLifetime
	snapshot.LocalRank = rankByUserId[userId] -- nil when outside the cached Top-N
	return snapshot
end

-- Global donor rank for a userId, resolved from the cached Top-N ONLY (no store
-- scan). Returns nil for anyone outside the cached board. Used by the profile card.
function DonationLeaderboard.GetRankFor(userId: number): number?
	return rankByUserId[userId]
end

-- Cached public donor snapshot for a userId (name, donated, rank) drawn purely from
-- the in-memory board -- no DataStore read, no profile load. Returns nil when the
-- user is not in the cached Top-N. This is what backs an OFFLINE player's minimal
-- public profile card opened from a leaderboard row.
function DonationLeaderboard.GetCachedDonor(userId: number)
	local rank = rankByUserId[userId]
	if not rank then
		return nil
	end
	for _, entry in ipairs(cache.Entries) do
		if entry.UserId == userId then
			return { Username = entry.Username, RobuxDonated = entry.RobuxDonated, Rank = entry.Rank }
		end
	end
	return nil
end

-- Pull the next scheduled refresh forward (e.g. right after a confirmed donation) so
-- the board updates faster than the fixed interval without spamming the store.
function DonationLeaderboard.MarkDirty()
	dirty = true
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function DonationLeaderboard.Start()
	-- Prime the cache once immediately, then loop.
	task.spawn(function()
		refresh()
		-- Push the primed cache to the stand + any online clients right away, rather
		-- than making them wait a full interval for the first loop tick.
		if Services.GlobalDonationStandSystem then
			pcall(Services.GlobalDonationStandSystem.OnLeaderboardUpdated)
		end
		local interval = math.max(DonationConfig.LeaderboardUpdateInterval, 10)
		while true do
			-- Wait up to `interval`, but wake early if MarkDirty was called. Poll in
			-- short slices so a dirty flag is honoured within ~1s.
			local waited = 0
			while waited < interval and not dirty do
				task.wait(1)
				waited += 1
			end
			dirty = false
			local ok, err = pcall(refresh)
			if not ok then
				Logger.Error("Donation", string.format("Leaderboard refresh errored: %s", tostring(err)))
			end
			-- Notify the stand + any interested systems that fresh data is ready.
			if Services.GlobalDonationStandSystem then
				Services.GlobalDonationStandSystem.OnLeaderboardUpdated()
			end
		end
	end)
end

return DonationLeaderboard
