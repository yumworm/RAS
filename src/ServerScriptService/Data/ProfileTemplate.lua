--!strict
-- ProfileTemplate: the canonical shape of a saved player profile. This doubles as
-- the default for brand-new players AND the reconcile target for old saves --
-- adding a field here makes it auto-appear (with its default) on every existing
-- profile the next time they load, without wiping anything.
--
-- Only persistent data lives here. Runtime-only values (current session, cached
-- income-per-second, connections) live in Core/Runtime instead.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameSettingsConfig = require(ReplicatedStorage.Modules.Configuration.GameSettingsConfig)

local ProfileTemplate = {}

ProfileTemplate.CURRENT_VERSION = 2

-- Returns a fresh deep default profile. Dynamic maps (inventory, discovered) start
-- empty and are filled/validated per-entry by ProfileService.
function ProfileTemplate.Default()
	return {
		schemaVersion = ProfileTemplate.CURRENT_VERSION,

		-- Centralized economy state. Nothing edits these except EconomyService.
		economy = {
			currency = 0,
			lifetimeEarned = 0,
			lifetimeSpent = 0,
			highestCurrency = 0,
			highestIncome = 0,
			highestSingleReward = 0,
			largestPurchase = 0,
			premiumCurrency = 0, -- placeholder, not implemented
		},

		-- Lifetime stats (session stats live in Runtime and roll up into these).
		stats = {
			totalSpins = 0,
			totalPlayTime = 0, -- seconds, lifetime
			bestPull = {
				streamerId = 0, -- 0 = none yet
				rarity = "",
				popularity = 0,
			},
		},

		-- Stacked inventory. Dynamic map: [streamerId] = entry. Filled by
		-- ProfileService.RepairInventory; entry shape documented there.
		inventory = {},

		-- Collection progress. `discovered` is a dynamic map [streamerId] = timestamp.
		collection = {
			discovered = {},
		},

		-- Feature gates future systems flip on. All off at start.
		unlockedFeatures = {
			garage = false,
			luckySpins = false,
			trading = false,
			prestige = false,
		},

		-- Player-controlled settings. Audio + FTUE defaults come from
		-- GameSettingsConfig so there is one source of truth for them; reducedMotion
		-- is a pre-existing accessibility flag kept here. All booleans -- the
		-- Reconcile on load repairs missing/wrong-typed keys back to these defaults
		-- without ever touching economy or inventory.
		settings = (function()
			local settings = GameSettingsConfig.DefaultSettings()
			settings.reducedMotion = false
			return settings
		end)(),

		-- Open-ended bag for future one-off flags so we never need a migration
		-- just to remember a boolean.
		futureFlags = {},
	}
end

-- The shape of a single inventory entry (documentation + default factory).
function ProfileTemplate.NewInventoryEntry(now: number)
	return {
		amount = 1,
		firstPulled = now,
		recentPull = now,
		upgradeLevel = 0, -- future
		xp = 0, -- future
		favorite = false, -- future
		locked = false, -- future
	}
end

return ProfileTemplate
