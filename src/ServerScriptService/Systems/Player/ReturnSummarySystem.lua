--!strict
-- ReturnSummarySystem: builds the welcome-back payload and owns the LastLogout stamp.
--
-- Hard rule: the return summary is FACTS ONLY. It grants zero Bucks, simulates zero
-- idle earnings, and never touches inventory. There is no offline income in this game.
-- Income keeps ticking under the panel; the client's Continue button only closes UI.
--
-- Mutual exclusion with the Phase 5 FTUE: the summary is suppressed on a true first
-- session (HasSeenWelcomeToast == false) so the P5 welcome toast / spin pulse owns the
-- first join, and the two are never competing blockers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = ReplicatedStorage.Modules.Configuration
local StreamerDatabase = require(Configuration.StreamerDatabase)
local LiveContentConfig = require(Configuration.LiveContentConfig)

local ReturnSummarySystem = {}
local Services: any

-- Per-session guard so the analytics counter is bumped at most once even though the
-- initial payload is built both at init and on the ClientReady resend. Cleared on
-- logout (a rejoin is a new session anyway).
local reported: { [number]: boolean } = {}

function ReturnSummarySystem.Init(services)
	Services = services
end

-- Server-stamp the logout time (unix seconds). Called on leave and on shutdown, right
-- before the profile is saved, so the next session can compute time away. The client
-- can never reach this path -- LastLogout is server-authored only.
function ReturnSummarySystem.StampLogout(userId: number)
	local profile = Services.ProfileService.Get(userId)
	if profile then
		profile.lastLogout = os.time()
	end
	reported[userId] = nil
end

local function resolveBestPull(profile): (string?, string?)
	local best = profile.stats.bestPull
	if not best or best.streamerId == 0 then
		return nil, nil
	end
	local streamer = StreamerDatabase.Get(best.streamerId)
	return streamer and streamer.name or nil, best.rarity ~= "" and best.rarity or nil
end

-- Build the welcome-back payload for a freshly-initialized player, or nil when the
-- player is not eligible (feature off, opted out, first session, or too-short absence).
-- Called by NetworkService while assembling the initial client payload.
function ReturnSummarySystem.BuildPayload(userId: number)
	local cfg = LiveContentConfig.ReturnSummary
	if not (cfg.Enabled and LiveContentConfig.FeatureFlags.ReturnSummaryEnabled) then
		return nil
	end
	local profile = Services.ProfileService.Get(userId)
	if not profile then
		return nil
	end
	-- Player opted out.
	if profile.settings and profile.settings.showReturnSummary == false then
		return nil
	end
	-- First session ever (no prior logout) -> let the FTUE own it.
	if profile.lastLogout == nil or profile.lastLogout <= 0 then
		return nil
	end
	-- Suppress on a true first-time-user session so it never competes with the P5 toast.
	if profile.settings and profile.settings.hasSeenWelcomeToast ~= true then
		return nil
	end

	local away = os.time() - profile.lastLogout
	if away < math.max(cfg.MinAwaySec, 1) then
		return nil
	end

	local collection = Services.CollectionService.GetSummary(userId)
	local donation = profile.donation
	local bestName, bestRarity = resolveBestPull(profile)

	-- Developer-only telemetry (log-only; the payload grants nothing). Guarded so the
	-- ClientReady resend of the initial payload does not double-count this return.
	if not reported[userId] and Services.AnalyticsMonitorSystem and Services.AnalyticsMonitorSystem.LogReturnSummaryShown then
		reported[userId] = true
		Services.AnalyticsMonitorSystem.LogReturnSummaryShown(userId, away)
	end

	return {
		TimeAwaySec = away,
		CurrentIncome = Services.IncomeService.GetIncome(userId),
		LifetimeSpins = profile.stats.totalSpins,
		CollectionCollected = collection.collected,
		CollectionTotal = collection.total,
		CollectionPercent = collection.percentage,
		RobuxDonatedLifetime = donation.robuxDonatedLifetime,
		DonationPurchaseCount = donation.donationPurchaseCount,
		BiggestRobuxDonation = donation.biggestRobuxDonation,
		BestPullName = bestName,
		BestPullRarity = bestRarity,
	}
end

return ReturnSummarySystem
