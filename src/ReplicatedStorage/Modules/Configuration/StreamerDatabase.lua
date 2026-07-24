--!strict
-- StreamerDatabase: the Phase 1 roster (25 recognizable streamers, no filler),
-- restructured to carry every field future phases will need.
--
-- Authoring model: each raw entry supplies the *identity* fields a designer
-- hand-tunes (name, popularity_score, region, is_featured, and the placeholder
-- presentation asset ids). Everything derivable -- rarity_tier, base_income,
-- roll weight -- is computed once here from popularity so it can never drift out
-- of sync with RarityConfig.
--
-- popularity_score is a gameplay-balance value (1-100), tuned by hand and loosely
-- inspired by each creator's real-world prominence circa 2025-2026. It is NOT a
-- live analytics feed.
--
-- Income model: base_income = popularity_score. Effective income is
-- base_income * rarity.IncomeScaling * amount, computed only in IncomeService.
-- Scaling is tuned so a maxed roster + future upgrade/prestige multipliers lands
-- endgame around the $10T cap, never beyond it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configuration = ReplicatedStorage.Modules.Configuration
local RarityConfig = require(Configuration.RarityConfig)
local PresentationConfig = require(Configuration.PresentationConfig)

-- Placeholder presentation defaults. Non-empty values would reference real
-- assets in a later phase; empty strings mean "use the rarity/default preset".
local function presentation(overrides)
	local base = {
		reveal_animation_id = "",
		reveal_sound = "",
		banner_asset = "",
		card_background = "",
		particle_preset = "",
		voice_line = "", -- future
		intro_camera_preset = "", -- future
	}
	if overrides then
		for k, v in pairs(overrides) do
			base[k] = v
		end
	end
	return base
end

-- Raw authored roster. collection is exactly one; banners is at least one.
local RawRoster = {
	{ name = "Kai Cenat", popularity_score = 100, region = "NA" },
	{ name = "Speed", popularity_score = 99, region = "NA" },
	{ name = "xQc", popularity_score = 98, region = "EU" },
	{ name = "MrBeast", popularity_score = 97, region = "NA" },
	{ name = "Adin Ross", popularity_score = 95, region = "NA" },
	{ name = "Jynxzi", popularity_score = 93, region = "NA" },
	{ name = "Duke Dennis", popularity_score = 91, region = "NA" },
	{ name = "CaseOh", popularity_score = 88, region = "NA" },
	{ name = "Fanum", popularity_score = 85, region = "NA" },
	{ name = "Ninja", popularity_score = 84, region = "NA" },
	{ name = "Stable Ronaldo", popularity_score = 82, region = "NA" },
	{ name = "Lacy", popularity_score = 75, region = "NA" },
	{ name = "JasonTheWeen", popularity_score = 72, region = "NA" },
	{ name = "Rakai", popularity_score = 70, region = "NA" },
	{ name = "Agent 00", popularity_score = 68, region = "NA" },
	{ name = "Sketch", popularity_score = 66, region = "NA" },
	{ name = "Plaqueboymax", popularity_score = 60, region = "NA" },
	{ name = "N3on", popularity_score = 58, region = "NA" },
	{ name = "Ludwig", popularity_score = 55, region = "NA" },
	{ name = "Valkyrae", popularity_score = 53, region = "NA" },
	{ name = "Pokimane", popularity_score = 52, region = "NA" },
	{ name = "Cinna", popularity_score = 40, region = "NA" },
	{ name = "Ranboo", popularity_score = 33, region = "EU" },
	{ name = "Punga", popularity_score = 22, region = "SA" },
	{ name = "Slime", popularity_score = 18, region = "Global" },
}

-- Default Flagship particle preset per tier (registered in PresentationConfig).
-- Flagship streamers with no authored particle_preset inherit their tier preset.
local FLAGSHIP_PARTICLE_BY_TIER = {
	Mythic = "MythicBurst",
	Secret = "SecretStorm",
}

-- Fill Flagship presentation placeholders. Real asset ids drop in during a later
-- content pass; rbxassetid://0 is a valid dev placeholder that the client treats
-- as "unset" and falls back from (never a soft-lock). Standard streamers keep the
-- empty presentation table: they use the shared rarity color + chime only.
local function applyFlagshipDefaults(pres, rarityTier: string)
	if pres.reveal_animation_id == "" then
		pres.reveal_animation_id = "rbxassetid://0"
	end
	if pres.reveal_sound == "" then
		pres.reveal_sound = "rbxassetid://0"
	end
	if pres.banner_asset == "" then
		pres.banner_asset = "rbxassetid://0"
	end
	if pres.particle_preset == "" then
		pres.particle_preset = FLAGSHIP_PARTICLE_BY_TIER[rarityTier] or PresentationConfig.DefaultParticlePreset
	end
	return pres
end

local StreamerDatabase = {}
StreamerDatabase.All = {} -- array, database order
StreamerDatabase.ById = {} -- [id] -> streamer

for index, entry in ipairs(RawRoster) do
	local popularity = entry.popularity_score
	local rarityTier = RarityConfig.GetTierForPopularity(popularity)
	local pres = presentation(entry.presentation)

	-- PresentationType is derived strictly from rarity (Mythic/Secret -> Flagship,
	-- everything else -> Standard). It is never hand-authored per streamer.
	local presentationType = PresentationConfig.GetPresentationType(rarityTier)
	if presentationType == "Flagship" then
		applyFlagshipDefaults(pres, rarityTier)
	end

	local streamer = {
		id = index,
		name = entry.name,
		popularity_score = popularity,

		-- Derived (never hand-edit these):
		rarity_tier = rarityTier,
		presentation_type = presentationType, -- "Flagship" | "Standard"
		base_income = popularity, -- see income model note above
		weight = RarityConfig.GetWeight(popularity),

		-- Content assignment (required, validated on startup):
		collection = "Originals", -- exactly one
		banners = { "Standard" }, -- at least one
		region = entry.region,
		is_featured = false, -- Featured Streamer flag (future)

		-- Presentation placeholders (data only; no visuals implemented yet):
		presentation = pres,
	}
	StreamerDatabase.All[index] = streamer
	StreamerDatabase.ById[streamer.id] = streamer
end

StreamerDatabase.Count = #StreamerDatabase.All

function StreamerDatabase.Get(id)
	return StreamerDatabase.ById[id]
end

return StreamerDatabase
