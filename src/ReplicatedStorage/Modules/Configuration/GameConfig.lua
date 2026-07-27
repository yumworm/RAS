--!strict
-- GameConfig: the single home for every balancing / tuning value in the game.
-- Rule of thumb: if a number affects balance or behaviour, it lives here, not
-- inline in a service. Balancing the game should never require hunting through
-- dozens of files.
local RunService = game:GetService("RunService")

local GameConfig = {}

-- Identity
GameConfig.CurrencyName = "Streamer Bucks"

-- Economy (project-wide rule: the economy intentionally ends around $10T).
-- If a value ever needs a suffix past T, that is a balancing error to fix here,
-- not a reason to extend the formatter.
GameConfig.StartingCurrency = 0
GameConfig.EconomyCap = 10e12 -- $10,000,000,000,000 hard ceiling
GameConfig.GlobalIncomeMultiplier = 1 -- global tuning knob for all passive income

-- Progression bands (documentation + future gating; not enforced as walls).
GameConfig.ProgressionBands = {
	{ name = "Early", min = 0, max = 1e6 }, -- $0 - $1M
	{ name = "Mid", min = 1e6, max = 1e9 }, -- $1M - $1B
	{ name = "Late", min = 1e9, max = 100e9 }, -- $1B - $100B
	{ name = "End", min = 100e9, max = 10e12 }, -- $100B - $10T
}

-- Spin / rolling
GameConfig.SpinCooldown = 0.45 -- seconds between accepted spins (anti-spam)
GameConfig.SpinAnimationDuration = 2 -- cosmetic reel minimum, client-side only

-- Income accrual
GameConfig.IncomeTickInterval = 1 -- seconds between passive income payouts

-- Saving
GameConfig.AutosaveInterval = 60 -- seconds between background autosaves
GameConfig.SaveMaxRetries = 5
GameConfig.SaveRetryBaseDelay = 2 -- seconds; exponential backoff base

-- Offline income (placeholder for a future phase; not implemented yet).
GameConfig.OfflineIncomeCapSeconds = 8 * 60 * 60 -- cap offline earnings at 8h

-- Collection sizing: the base roster is intentionally small, but the whole
-- backend is designed to scale to this target without rewrites.
GameConfig.CollectionTargetSize = 150

-- Future multiplier defaults. These are the neutral values the RNG / economy
-- read today; future systems (Luck Potions, Events, Gamepasses, Upgrades,
-- Prestige) will override them per-player without touching core logic.
GameConfig.Multipliers = {
	LuckDefault = 1,
	EventDefault = 1,
	GamepassDefault = 1,
	UpgradeDefault = 1,
	PityDefault = 0,
}

-- Upgrade scaling placeholder (future Garage/Upgrade system).
GameConfig.UpgradeScaling = {
	CostBase = 100,
	CostGrowth = 1.15,
	IncomePerLevel = 0.10, -- +10% per level, applied by a future system
}

-- Developer logging toggle (never shown to players). Production default: on in
-- Studio, off in live/published servers so shipped games do not spam the console
-- or pay the cost of formatting log lines. To force logs on in a live server (for
-- a one-off investigation) set this to an explicit `true`.
GameConfig.LoggingEnabled = RunService:IsStudio()

return GameConfig
