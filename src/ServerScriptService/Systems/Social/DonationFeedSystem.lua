--!strict
-- DonationFeedSystem: a small in-memory ring buffer of the most recent successful
-- donations TO THE GAME, plus the broadcast that pushes each new one to every online
-- client. It is deliberately thin: it never runs purchase math, never credits a
-- profile, and never authors the leaderboard. RobuxDonationSystem calls Append EXACTLY
-- once per first-time durable grant (tied to the idempotent success path), so a
-- duplicate ProcessReceipt retry can never rebroadcast the same donation.
--
-- Security: the client can never append. There is no inbound remote here -- the only
-- writer is the server-side donation grant path. DonationFeedPush is server -> client
-- only. Rows carry display names only (never a UserId string), and never a receiver:
-- this is a donation to the game, not a player-to-player transfer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LiveContentConfig = require(ReplicatedStorage.Modules.Configuration.LiveContentConfig)

local Server = script.Parent.Parent.Parent
local Logger = require(Server.Utilities.Logger)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local DonationFeedSystem = {}
local Services: any

-- Newest-first ring buffer. Index 1 is the most recent event.
local entries: { { DonorName: string, Amount: number, Timestamp: number } } = {}

function DonationFeedSystem.Init(services)
	Services = services
end

local function maxEntries(): number
	return math.clamp(LiveContentConfig.DonationFeed.MaxEntries, 1, 100)
end

--------------------------------------------------------------------------------
-- Read APIs (snapshot for the initial payload + recent strip for the stand)
--------------------------------------------------------------------------------

-- Copy of the whole feed, newest-first. Consumers can never mutate the buffer.
function DonationFeedSystem.GetSnapshot()
	local copy = {}
	for i, e in ipairs(entries) do
		copy[i] = { DonorName = e.DonorName, Amount = e.Amount, Timestamp = e.Timestamp }
	end
	return { entries = copy }
end

-- The newest `count` events (for the stand's "Recent supporters" strip).
function DonationFeedSystem.GetRecent(count: number)
	local out = {}
	local limit = math.min(count, #entries)
	for i = 1, limit do
		local e = entries[i]
		out[i] = { DonorName = e.DonorName, Amount = e.Amount, Timestamp = e.Timestamp }
	end
	return out
end

--------------------------------------------------------------------------------
-- Append + broadcast (the only writer; gated by the feature flag)
--------------------------------------------------------------------------------

-- Record a confirmed donation and push it live to every client. No-op when the
-- feature flag is off (system fully disabled: no record, no broadcast). Called ONLY
-- from RobuxDonationSystem's first-time durable-grant path.
function DonationFeedSystem.Append(donorName: string, amount: number, timestamp: number)
	if not LiveContentConfig.FeatureFlags.DonationFeedEnabled then
		return
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	local event = {
		DonorName = (type(donorName) == "string" and donorName ~= "") and donorName or "A supporter",
		Amount = math.floor(amount),
		Timestamp = type(timestamp) == "number" and timestamp or os.time(),
	}

	table.insert(entries, 1, event) -- newest-first
	while #entries > maxEntries() do
		table.remove(entries) -- evict the oldest (tail)
	end

	-- Push to every online client (server -> client only).
	Remotes.DonationFeedPush:FireAllClients(event)

	-- Refresh the optional stand "Recent supporters" strip from the same cache.
	if Services.GlobalDonationStandSystem and Services.GlobalDonationStandSystem.OnDonationFeedUpdated then
		pcall(Services.GlobalDonationStandSystem.OnDonationFeedUpdated)
	end

	-- Developer-only telemetry (log-only; never affects the grant).
	if Services.AnalyticsMonitorSystem and Services.AnalyticsMonitorSystem.LogFeedBroadcast then
		Services.AnalyticsMonitorSystem.LogFeedBroadcast()
	end

	Logger.Info("Feed", string.format("donation feed append %s %d", event.DonorName, event.Amount))
end

-- Resolve a donor display name for a userId (online DisplayName preferred). Kept here
-- so the feed always shows a friendly name even if the donor just left.
function DonationFeedSystem.ResolveDonorName(userId: number): string
	local online = Players:GetPlayerByUserId(userId)
	if online then
		return online.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	return "A supporter"
end

return DonationFeedSystem
