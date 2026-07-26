--!strict
-- LiveContentConfig: the single home for every Phase 6 post-1.0 retention tuning
-- value (return summary, profile cards, live donation feed, stats panel, feature
-- flags, the cosmetic Featured Streamer highlight, and P6-specific analytics/UI/copy).
-- Like GameConfig / GameSettingsConfig, if a Phase 6 number or string affects
-- behaviour or presentation it lives here, never inline in a controller.
--
-- Scope guardrails baked in:
--   * FeatureFlags are booleans only. They hide UI cleanly; they never grant anything.
--   * Featured is cosmetic-only. Its resolver below NEVER touches roll weights, income,
--     or the RNG -- it only decides whether a small text badge is shown.
--   * The donation feed records donations TO THE GAME. RowTemplate has {donor} and
--     {amount} tokens only -- there is no receiver token (this is not P2P).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StreamerDatabase = require(ReplicatedStorage.Modules.Configuration.StreamerDatabase)

local LiveContentConfig = {}

-- Welcome-back panel. Facts only, zero economy writes (see ReturnSummarySystem).
LiveContentConfig.ReturnSummary = {
	Enabled = true,
	MinAwaySec = 300, -- only show if the player was away at least this long
	PanelTitle = "Welcome back",
	ContinueText = "Continue",
}

-- Read-only server-authored profile card (own + in-server others).
LiveContentConfig.ProfileCard = {
	Enabled = true,
	RequestCooldownSec = 1, -- min seconds between accepted card requests per player
	AllowOtherPlayers = true,
	InServerOnly = true, -- full cards only for in-server targets; offline leaderboard
	-- rows fall back to a minimal public donor snapshot (name, donated, rank).
}

-- Live global feed of successful donations TO THE GAME (not to players).
LiveContentConfig.DonationFeed = {
	Enabled = true,
	MaxEntries = 30, -- ring buffer size (1..100)
	SnapshotOnJoin = true, -- fold the current feed into the initial client payload
	LargeAmountThreshold = 500, -- rows at/above this get a highlight (color/weight only)
	-- {donor} and {amount} tokens only. No receiver token: the donation is to the game.
	RowTemplate = "{donor} donated {amount} Robux",
	StandRecentCount = 3, -- "Recent supporters" lines on the stand SurfaceGui
}

-- Live feature flags, folded into the initial client payload. The server reads them
-- to gate systems; the client hides the matching UI cleanly when a flag is false.
LiveContentConfig.FeatureFlags = {
	ReturnSummaryEnabled = true,
	ProfileCardsEnabled = true,
	DonationFeedEnabled = true,
	FeaturedHighlightEnabled = true,
	StatsPanelEnabled = true,
}

-- Cosmetic Featured Streamer highlight. Purely a badge. Never affects the RNG.
--   StreamerName: must match a roster name exactly, or "" for none.
--   EndTimestamp: 0 = no expiry; if > 0 and os.time() > EndTimestamp, treated as off.
LiveContentConfig.Featured = {
	Enabled = false,
	StreamerName = "",
	BadgeText = "Featured",
	EndTimestamp = 0,
}

-- Phase 6 developer-only analytics toggles. The economy soft-cap + snapshot cadence
-- still live in GameSettingsConfig.Analytics (Phase 5); these gate the new P6 logs.
LiveContentConfig.Analytics = {
	LogReturnSummary = true,
	LogProfileCardOpen = true,
	LogFeedBroadcast = true,
	LogStatsPanelOpen = true,
}

-- UI sizing knobs for the new P6 panels.
LiveContentConfig.UI = {
	ReturnSummarySize = UDim2.fromOffset(400, 340),
	ProfileCardSize = UDim2.fromOffset(380, 420),
	StatsPanelSize = UDim2.fromOffset(420, 480),
	FeedWidth = 260,
	FeedHeight = 120,
	FeedMaxVisibleRows = 5,
	MinTouchPx = 48, -- primary buttons should be at least this tall/wide on mobile
}

-- Player-facing copy. No emojis, standard hyphens only.
LiveContentConfig.Text = {
	ProfileButton = "Profile",
	StatsButton = "Stats",
	FeedTitle = "Recent Donations",
	PlayerNotInServer = "Player not in this server",
	Unranked = "Unranked",
	TimeAwayLabel = "Time Away",
	ProfileTitle = "Profile",
	StatsTitle = "Legacy Stats",
	Close = "Close",
	Online = "Online",
	Offline = "Offline",
	FeedEmpty = "No donations yet",
}

--------------------------------------------------------------------------------
-- Featured resolver (cosmetic only; never touches RNG / income)
--------------------------------------------------------------------------------

-- Resolve the effective Featured state right now. Returns (active, reason):
--   active = false when the master flag is off, the feature flag is off, the name is
--   empty/unknown, or the EndTimestamp has passed. reason is a short string for the
--   one-time startup log. This is the ONLY place expiry + name validity are decided.
function LiveContentConfig.IsFeaturedActive(): (boolean, string)
	local featured = LiveContentConfig.Featured
	if not LiveContentConfig.FeatureFlags.FeaturedHighlightEnabled then
		return false, "feature flag off"
	end
	if featured.Enabled ~= true then
		return false, "disabled"
	end
	if type(featured.StreamerName) ~= "string" or featured.StreamerName == "" then
		return false, "no name set"
	end
	if not StreamerDatabase.GetByName(featured.StreamerName) then
		return false, "unknown streamer name"
	end
	local endAt = featured.EndTimestamp
	if type(endAt) == "number" and endAt > 0 and os.time() > endAt then
		return false, "expired"
	end
	return true, "active"
end

-- The client-safe Featured payload folded into the initial state. When inactive it
-- ships Enabled=false so the client renders no badge. The client re-checks
-- EndTimestamp too, so an expiry mid-session hides the badge without a rejoin.
function LiveContentConfig.ResolveFeatured()
	local active = LiveContentConfig.IsFeaturedActive()
	local featured = LiveContentConfig.Featured
	return {
		Enabled = active,
		StreamerName = active and featured.StreamerName or "",
		BadgeText = type(featured.BadgeText) == "string" and featured.BadgeText ~= "" and featured.BadgeText
			or "Featured",
		EndTimestamp = type(featured.EndTimestamp) == "number" and featured.EndTimestamp or 0,
	}
end

return LiveContentConfig
