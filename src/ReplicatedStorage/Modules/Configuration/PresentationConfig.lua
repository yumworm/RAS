--!strict
-- PresentationConfig: the single source of truth for the Phase 4 Two-Tier
-- Presentation System. It decides ONLY how a pull is shown, never what is rolled
-- or how much it earns. Rolls stay pure inverse-popularity RNG (RNG.lua) and
-- income stays in IncomeService; presentation fields must never feed either.
--
-- Two tiers, split strictly by rarity:
--   Flagship (Mythic, Secret only): premium cinematic reveal with per-streamer
--     banner, animation, sound and particles.
--   Standard (Common through Legendary): instant static pop-in, a shared rarity
--     color, and a shared rarity chime. No winner-card motion at all.
--
-- Rarity COLORS intentionally are not duplicated here. They live in RarityConfig
-- (the one rarity source of truth); the Standard reveal reads Color from there so
-- the two can never drift. This module owns only presentation-specific data:
-- caps, tier routing, timeouts, chimes, and particle preset keys.
local PresentationConfig = {}

-- Roster sizing. The roster is deliberately small and hand-picked; validation
-- fails safe (disables gacha) above the max, and warns below the min.
PresentationConfig.MaxRosterSize = 30
PresentationConfig.MinRosterSize = 20

-- The hard tier split. A rarity is Flagship if and only if it is listed here.
PresentationConfig.FlagshipRarities = {
	Mythic = true,
	Secret = true,
}

PresentationConfig.StandardRarities = {
	Common = true,
	Uncommon = true,
	Rare = true,
	Epic = true,
	Legendary = true,
}

-- Flagship reveal rules.
PresentationConfig.Flagship = {
	InputLock = true, -- lock spin input during the cinematic
	MaxSequenceSeconds = 8, -- hard timeout so the UI can never soft-lock
	FallbackToStandardOnMissingAssets = true,
	-- Fields a Flagship streamer must define (may be placeholder ids in dev).
	RequireFields = { "RevealAnimId", "RevealSoundId", "ParticlePreset", "CustomBannerId" },
}

-- Standard reveal rules. Every motion knob is off by design: the winning card
-- must appear instantly with no tween, bounce, flip, or fade.
PresentationConfig.Standard = {
	AllowTweens = false,
	AllowParticles = false,
	AllowCustomBanner = false,
	AllowPerStreamerSound = false,
	UseRarityChime = true,
	UseRarityColorTemplate = true,
}

-- Shared Standard rarity chimes (one short sound per tier, not per streamer).
-- Placeholder ids (rbxassetid://0) are allowed in development; the client treats
-- 0/empty as "no sound" and simply stays silent rather than erroring.
PresentationConfig.RarityChimes = {
	Common = "rbxassetid://0",
	Uncommon = "rbxassetid://0",
	Rare = "rbxassetid://0",
	Epic = "rbxassetid://0",
	Legendary = "rbxassetid://0",
	-- Fallback chimes for the Flagship tiers (used only if a streamer's own
	-- RevealSoundId is missing).
	Mythic = "rbxassetid://0",
	Secret = "rbxassetid://0",
}

-- Particle preset registry. Keys are referenced by Flagship streamers' Assets;
-- anything unresolved falls back to DefaultFlagship (see ResolveParticlePreset).
-- Values are preset names a future particle module can switch on; today they are
-- data-only labels the client uses to pick a procedural burst style.
PresentationConfig.ParticlePresets = {
	DefaultFlagship = "DefaultFlagship",
	MythicBurst = "MythicBurst",
	SecretStorm = "SecretStorm",
}

PresentationConfig.DefaultParticlePreset = "DefaultFlagship"

-- The one derivation used everywhere: rarity name -> "Flagship" | "Standard".
-- This is the only correct way to assign a PresentationType; nothing should
-- hardcode the string per streamer.
function PresentationConfig.GetPresentationType(rarityName: string): string
	if PresentationConfig.FlagshipRarities[rarityName] then
		return "Flagship"
	end
	return "Standard"
end

function PresentationConfig.IsFlagship(rarityName: string): boolean
	return PresentationConfig.FlagshipRarities[rarityName] == true
end

-- Resolve a particle preset key to a registered one, falling back to the default
-- so a missing/typo'd key can never error at reveal time.
function PresentationConfig.ResolveParticlePreset(key: string?): string
	if key and PresentationConfig.ParticlePresets[key] then
		return key
	end
	return PresentationConfig.DefaultParticlePreset
end

-- A shared "is this asset id actually set" helper. Placeholder 0 ids and empty
-- strings count as unset so callers fall back safely.
function PresentationConfig.IsAssetSet(assetId: any): boolean
	return type(assetId) == "string" and assetId ~= "" and assetId ~= "rbxassetid://0"
end

return PresentationConfig
