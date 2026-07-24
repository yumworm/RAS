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
local funnelState: { [number]: { lastPanelOpenAt: number } } = {}

-- Running counters for the snapshot line (since server start).
local capWarningCount = 0

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
			capWarningCount += 1
			Logger.Warn(
				"Analytics",
				string.format("economy_soft_cap userId=%d value=%d cap=%d", userId, math.floor(current), math.floor(Analytics.EconomyCapSoft))
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
	if not Analytics.LogDonationFunnel then
		return
	end
	Logger.Info("Analytics", string.format("donation_prompt_requested userId=%d product=%s", userId, tostring(productId)))
end

-- A donation was granted in ProcessReceipt (Phase 3). Log only; never re-grant.
function AnalyticsMonitorSystem.LogDonationGranted(userId: number, robuxAmount: number)
	if not Analytics.LogDonationFunnel then
		return
	end
	Logger.Info("Analytics", string.format("donation_granted userId=%d robux=%s", userId, tostring(robuxAmount)))
end

--------------------------------------------------------------------------------
-- Snapshot loop
--------------------------------------------------------------------------------

local function startSnapshotLoop()
	task.spawn(function()
		while true do
			task.wait(Analytics.SnapshotIntervalSec)
			Logger.Info(
				"Analytics",
				string.format("snapshot players=%d cap_warnings=%d", #Players:GetPlayers(), capWarningCount)
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

	Players.PlayerRemoving:Connect(function(player)
		clearPlayer(player.UserId)
	end)

	startSnapshotLoop()
end

return AnalyticsMonitorSystem
