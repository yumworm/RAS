--!strict
-- AnalyticsMonitorSystem: developer-only, server-side observability. It never
-- touches gameplay, never clamps or grants anything, and is never shown to players.
-- Everything it emits goes through Logger (gated by GameConfig.LoggingEnabled) with
-- a consistent "[Analytics]" category so funnel and economy lines are easy to grep.
--
-- What it watches:
--   1. Economy soft cap. Hooked onto EconomyService's OnCurrencyChanged seam (no
--      per-frame polling), it warns when a player's Bucks cross ~10T, debounced so
--      it logs on the crossing and at most once per window thereafter.
--   2. Donation funnel (Phase 3). A small Log API (panel opened / prompt requested
--      / grant) with a rate limit on the noisy "panel opened" event. The Phase 3
--      donation systems call these: the client fires AnalyticsDonationPanelOpened on
--      open, RobuxDonationSystem reports prompt requests and grants.
--   3. Periodic snapshot. Every SnapshotIntervalSec it logs player count and the
--      running cap-warning count. In-memory only; no DataStore.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = ReplicatedStorage.Modules.Configuration
local GameSettingsConfig = require(Configuration.GameSettingsConfig)
local LiveContentConfig = require(Configuration.LiveContentConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Server = script.Parent.Parent.Parent
local ExpansionHooks = require(Server.Core.ExpansionHooks)
local Logger = require(Server.Utilities.Logger)

local AnalyticsMonitorSystem = {}
local Services: any

local Analytics = GameSettingsConfig.Analytics

-- Per-player monitor state, cleared on leave so nothing references a departed user.
--   cap[userId]   = { lastWarnAt: number, above: boolean }
--   funnel[userId] = { lastPanelOpenAt: number }
local capState: { [number]: { lastWarnAt: number, above: boolean } } = {}
local funnelState: { [number]: { lastPanelOpenAt: number, lastUiPingAt: number? } } = {}

-- Running counters for the snapshot line (all since server start, in-memory only --
-- no DataStore, never shown to players). Phase 6 expands this from a single cap count
-- to a small funnel + retention picture; every increment is log-only.
local counters = {
	cap_warnings = 0,
	sessions_started = 0,
	ftue_zero_spin_joins = 0,
	return_summaries_shown = 0,
	spins_completed = 0,
	donation_prompt_requested = 0,
	donation_prompt_success = 0,
	profile_cards_opened = 0,
	feed_events_broadcast = 0,
	stats_panel_opened = 0,
}
-- Optional per-rarity award tally (streamers_awarded_by_rarity).
local awardsByRarity: { [string]: number } = {}

function AnalyticsMonitorSystem.Init(services)
	Services = services
end

--------------------------------------------------------------------------------
-- Economy soft-cap monitor
--------------------------------------------------------------------------------

local function checkEconomyCap(userId: number)
	if not Analytics.LogEconomyCap then
		return
	end
	local current = Services.EconomyService.GetCurrency(userId)
	local state = capState[userId]
	if not state then
		state = { lastWarnAt = 0, above = false }
		capState[userId] = state
	end

	if current > Analytics.EconomyCapSoft then
		local now = os.clock()
		local crossing = not state.above
		if crossing or (now - state.lastWarnAt) >= Analytics.CapWarnDebounceSec then
			state.lastWarnAt = now
			counters.cap_warnings += 1
			Logger.Warn(
				"Analytics",
				string.format(
					"economy_soft_cap userId=%d value=%d cap=%d",
					userId,
					math.floor(current),
					math.floor(Analytics.EconomyCapSoft)
				)
			)
		end
		state.above = true
	elseif current <= Analytics.EconomyCapSoft then
		-- Reset so a later re-cross logs again (and clears the debounce).
		state.above = false
	end
end

--------------------------------------------------------------------------------
-- Donation funnel API (called by the Phase 3 donation systems)
--------------------------------------------------------------------------------

-- Rate-limited: the donation panel can be opened repeatedly, so only log at most
-- once per LogPanelOpenRateLimitSec per player. Validates the player still exists.
function AnalyticsMonitorSystem.LogDonationPanelOpened(userId: number)
	if not Analytics.LogDonationFunnel then
		return
	end
	if not Players:GetPlayerByUserId(userId) then
		return
	end
	local state = funnelState[userId]
	if not state then
		state = { lastPanelOpenAt = 0 }
		funnelState[userId] = state
	end
	local now = os.clock()
	if (now - state.lastPanelOpenAt) < Analytics.LogPanelOpenRateLimitSec then
		return
	end
	state.lastPanelOpenAt = now
	Logger.Info("Analytics", string.format("donation_panel_opened userId=%d", userId))
end

-- A Robux donation purchase prompt was requested (Phase 3 RobuxDonationSystem).
function AnalyticsMonitorSystem.LogDonationPromptRequested(userId: number, productId: number?)
	counters.donation_prompt_requested += 1
	if not Analytics.LogDonationFunnel then
		return
	end
	Logger.Info(
		"Analytics",
		string.format("donation_prompt_requested userId=%d product=%s", userId, tostring(productId))
	)
end

-- A donation was granted in ProcessReceipt (Phase 3). Log only; never re-grant. This
-- is the bottom of the funnel (donation_prompt_success in the Phase 6 counter set).
function AnalyticsMonitorSystem.LogDonationGranted(userId: number, robuxAmount: number)
	counters.donation_prompt_success += 1
	if not Analytics.LogDonationFunnel then
		return
	end
	Logger.Info("Analytics", string.format("donation_granted userId=%d robux=%s", userId, tostring(robuxAmount)))
end

--------------------------------------------------------------------------------
-- Phase 6 retention / social telemetry (all developer-only, log-only)
--------------------------------------------------------------------------------

-- A player finished initializing this session. Also detects a zero-spin (FTUE) join.
function AnalyticsMonitorSystem.LogSessionStarted(userId: number)
	counters.sessions_started += 1
	local profile = Services.ProfileService.Get(userId)
	local spins = profile and profile.stats.totalSpins or 0
	if spins == 0 then
		counters.ftue_zero_spin_joins += 1
	end
	Logger.Info("Analytics", string.format("session_started userId=%d lifetime_spins=%d", userId, spins))
end

-- The server attached a welcome-back payload for a returning player.
function AnalyticsMonitorSystem.LogReturnSummaryShown(userId: number, awaySec: number)
	counters.return_summaries_shown += 1
	if not LiveContentConfig.Analytics.LogReturnSummary then
		return
	end
	Logger.Info("Analytics", string.format("return_summary_shown userId=%d away=%d", userId, math.floor(awaySec)))
end

-- A profile card was requested/built for a viewer.
function AnalyticsMonitorSystem.LogProfileCardOpened(userId: number)
	counters.profile_cards_opened += 1
	if not LiveContentConfig.Analytics.LogProfileCardOpen then
		return
	end
	Logger.Info("Analytics", string.format("profile_card_opened userId=%d", userId))
end

-- A donation feed event was broadcast to all clients.
function AnalyticsMonitorSystem.LogFeedBroadcast()
	counters.feed_events_broadcast += 1
	if not LiveContentConfig.Analytics.LogFeedBroadcast then
		return
	end
	Logger.Info("Analytics", string.format("feed_broadcast total=%d", counters.feed_events_broadcast))
end

-- A player opened the legacy stats panel (client ping, rate-limited at the remote).
function AnalyticsMonitorSystem.LogStatsPanelOpened(userId: number)
	counters.stats_panel_opened += 1
	if not LiveContentConfig.Analytics.LogStatsPanelOpen then
		return
	end
	Logger.Info("Analytics", string.format("stats_panel_opened userId=%d", userId))
end

--------------------------------------------------------------------------------
-- Snapshot loop
--------------------------------------------------------------------------------

-- A spin resolved on the server (fired via the OnSpinCompleted expansion hook, so no
-- extra call site in NetworkService). Tallies total spins + per-rarity awards.
local function onSpinCompleted(_userId: number, winner: any)
	counters.spins_completed += 1
	local rarity = winner and winner.rarity_tier
	if type(rarity) == "string" and rarity ~= "" then
		awardsByRarity[rarity] = (awardsByRarity[rarity] or 0) + 1
	end
end

-- Compact "streamers_awarded_by_rarity" string for the snapshot line.
local function awardsSummary(): string
	local parts = {}
	for rarity, n in pairs(awardsByRarity) do
		table.insert(parts, string.format("%s=%d", rarity, n))
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, ",") or "none"
end

local function startSnapshotLoop()
	task.spawn(function()
		while true do
			task.wait(Analytics.SnapshotIntervalSec)
			Logger.Info(
				"Analytics",
				string.format(
					"snapshot players=%d sessions=%d ftue_zero=%d spins=%d returns=%d "
						.. "cards=%d feed=%d stats=%d donate_req=%d donate_ok=%d cap_warnings=%d awards=[%s]",
					#Players:GetPlayers(),
					counters.sessions_started,
					counters.ftue_zero_spin_joins,
					counters.spins_completed,
					counters.return_summaries_shown,
					counters.profile_cards_opened,
					counters.feed_events_broadcast,
					counters.stats_panel_opened,
					counters.donation_prompt_requested,
					counters.donation_prompt_success,
					counters.cap_warnings,
					awardsSummary()
				)
			)
		end
	end)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function clearPlayer(userId: number)
	capState[userId] = nil
	funnelState[userId] = nil
end

function AnalyticsMonitorSystem.Start()
	-- Sample the cap off the centralized currency-change seam (event-driven, never
	-- per-frame). A throwing hook is already isolated by ExpansionHooks.
	ExpansionHooks.Register("OnCurrencyChanged", function(userId: number)
		checkEconomyCap(userId)
	end)

	-- Donation funnel: the client tells us when it opens the Global Donation Stand
	-- panel (top of the funnel). The log itself is rate-limited per player, and the
	-- handler is pcall-wrapped so a malformed fire can never fault the system. This
	-- remote carries no gameplay authority -- it only marks "panel opened".
	Remotes.AnalyticsDonationPanelOpened.OnServerEvent:Connect(function(player)
		local ok, err = pcall(function()
			AnalyticsMonitorSystem.LogDonationPanelOpened(player.UserId)
		end)
		if not ok then
			Logger.Warn("Analytics", string.format("panel-open log error: %s", tostring(err)))
		end
	end)

	-- Tally spins + per-rarity awards off the existing spin-completed seam (no extra
	-- call site in the roll path). A throwing hook is isolated by ExpansionHooks.
	ExpansionHooks.Register("OnSpinCompleted", onSpinCompleted)

	-- Optional client UI ping (developer-only). The client can only send a kind from a
	-- small server-side allowlist; anything else is ignored. It carries no authority --
	-- it just bumps a log-only counter, and is rate-limited per player so it can never
	-- flood. Used for stats_panel_opened (a purely client-side panel with no other
	-- server touch point).
	local uiPingAllow = { stats_panel_opened = true }
	local uiPingRateLimit = 2 -- seconds between accepted pings per player
	Remotes.AnalyticsUIEvent.OnServerEvent:Connect(function(player, kind)
		local ok, err = pcall(function()
			if type(kind) ~= "string" or not uiPingAllow[kind] then
				return
			end
			local state = funnelState[player.UserId]
			if not state then
				state = { lastPanelOpenAt = 0 }
				funnelState[player.UserId] = state
			end
			local now = os.clock()
			if (now - (state.lastUiPingAt or 0)) < uiPingRateLimit then
				return
			end
			state.lastUiPingAt = now
			if kind == "stats_panel_opened" then
				AnalyticsMonitorSystem.LogStatsPanelOpened(player.UserId)
			end
		end)
		if not ok then
			Logger.Warn("Analytics", string.format("ui-ping error: %s", tostring(err)))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		clearPlayer(player.UserId)
	end)

	startSnapshotLoop()
end

return AnalyticsMonitorSystem
