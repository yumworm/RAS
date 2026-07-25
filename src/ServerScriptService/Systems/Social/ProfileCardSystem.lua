--!strict
-- ProfileCardSystem: builds read-only, server-authored profile cards. The client can
-- only ASK for a card (RequestProfileCard(targetUserId)); every number in the reply is
-- read from the authoritative server profile / economy / leaderboard cache. The client
-- never sends a stat and can never influence one.
--
-- Targeting rules (Phase 6 defaults):
--   * Self, or any IN-SERVER player  -> full card (collection, spins, donor stats).
--   * Offline target (e.g. a leaderboard row for a player not in this server) -> a
--     MINIMAL public donor card from the leaderboard cache (name, Robux donated, rank).
--     No profile is loaded for an offline target; if they are not in the cached board
--     we return a safe "not in this server" minimal card.
--
-- Never exposed on other-player cards: Settings, private flags, or any RobuxReceived /
-- booth field (those do not exist in this game).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = ReplicatedStorage.Modules.Configuration
local StreamerDatabase = require(Configuration.StreamerDatabase)
local LiveContentConfig = require(Configuration.LiveContentConfig)

local Server = script.Parent.Parent.Parent
local Runtime = require(Server.Core.Runtime)
local Logger = require(Server.Utilities.Logger)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local ProfileCardSystem = {}
local Services: any

function ProfileCardSystem.Init(services)
	Services = services
end

--------------------------------------------------------------------------------
-- Snapshot builders
--------------------------------------------------------------------------------

local function resolveBestPull(profile): (string?, string?)
	local best = profile.stats.bestPull
	if not best or best.streamerId == 0 then
		return nil, nil
	end
	local streamer = StreamerDatabase.Get(best.streamerId)
	return streamer and streamer.name or nil, best.rarity ~= "" and best.rarity or nil
end

-- Full card for an in-server player (self or another online player). CurrentIncome is
-- included only for the requester's own card (recommended by the spec).
local function buildFullCard(targetUserId: number, requesterUserId: number)
	local profile = Services.ProfileService.Get(targetUserId)
	if not profile then
		return nil
	end
	local player = Players:GetPlayerByUserId(targetUserId)
	local collection = Services.CollectionService.GetSummary(targetUserId)
	local donation = profile.donation
	local bestName, bestRarity = resolveBestPull(profile)
	local isOwn = targetUserId == requesterUserId

	return {
		UserId = targetUserId,
		DisplayName = player and player.DisplayName or ("User " .. tostring(targetUserId)),
		CollectionCollected = collection.collected,
		CollectionTotal = collection.total,
		CollectionPercent = collection.percentage,
		TotalSpins = profile.stats.totalSpins,
		CurrentIncome = isOwn and Services.IncomeService.GetIncome(targetUserId) or nil,
		RobuxDonatedLifetime = donation.robuxDonatedLifetime,
		DonationPurchaseCount = donation.donationPurchaseCount,
		BiggestRobuxDonation = donation.biggestRobuxDonation,
		BestPullName = bestName,
		BestPullRarity = bestRarity,
		GlobalDonorRank = Services.DonationLeaderboard.GetRankFor(targetUserId),
		IsOnline = player ~= nil,
		IsMinimalPublic = false,
	}
end

-- Minimal public card for an OFFLINE target, drawn only from the leaderboard cache.
-- Returns a name-only "not in server" card when the user is not on the cached board.
local function buildMinimalCard(targetUserId: number)
	local cached = Services.DonationLeaderboard.GetCachedDonor(targetUserId)
	if cached then
		return {
			UserId = targetUserId,
			DisplayName = cached.Username,
			RobuxDonatedLifetime = cached.RobuxDonated,
			GlobalDonorRank = cached.Rank,
			IsOnline = false,
			IsMinimalPublic = true,
		}
	end
	return {
		UserId = targetUserId,
		DisplayName = "User " .. tostring(targetUserId),
		RobuxDonatedLifetime = 0,
		IsOnline = false,
		IsMinimalPublic = true,
		NotInServer = true,
	}
end

--------------------------------------------------------------------------------
-- Inbound request (validated + rate-limited)
--------------------------------------------------------------------------------

local function handleRequest(player: Player, targetUserId: any)
	if not (LiveContentConfig.ProfileCard.Enabled and LiveContentConfig.FeatureFlags.ProfileCardsEnabled) then
		return
	end
	local userId = player.UserId
	local runtime = Runtime.Get(userId)
	if not runtime or not runtime.initialized then
		return
	end
	if type(targetUserId) ~= "number" or targetUserId ~= targetUserId or targetUserId <= 0 then
		return -- ignore malformed target
	end
	targetUserId = math.floor(targetUserId)

	-- Rate limit per requester (default 1s).
	local now = os.clock()
	if (now - (runtime.lastProfileCardAt or 0)) < LiveContentConfig.ProfileCard.RequestCooldownSec then
		return
	end
	runtime.lastProfileCardAt = now

	-- Others require the allow flag; self is always permitted.
	if targetUserId ~= userId and not LiveContentConfig.ProfileCard.AllowOtherPlayers then
		return
	end

	-- In-server (self or online other) -> full card; otherwise minimal public card.
	local targetOnline = Players:GetPlayerByUserId(targetUserId)
	local snapshot
	if targetOnline then
		snapshot = buildFullCard(targetUserId, userId)
	end
	if not snapshot then
		snapshot = buildMinimalCard(targetUserId)
	end

	Remotes.ProfileCardResult:FireClient(player, snapshot)

	-- Developer-only telemetry (log-only; never trusts the client).
	if Services.AnalyticsMonitorSystem and Services.AnalyticsMonitorSystem.LogProfileCardOpened then
		Services.AnalyticsMonitorSystem.LogProfileCardOpened(userId)
	end
end

function ProfileCardSystem.Start()
	Remotes.RequestProfileCard.OnServerEvent:Connect(function(player, targetUserId)
		local ok, err = pcall(handleRequest, player, targetUserId)
		if not ok then
			Logger.Warn("ProfileCard", string.format("request handler error: %s", tostring(err)))
		end
	end)
end

return ProfileCardSystem
