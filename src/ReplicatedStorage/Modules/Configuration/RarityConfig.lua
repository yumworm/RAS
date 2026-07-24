--!strict
-- RarityConfig: the single source of truth for rarity. Every system that cares
-- about rarity (income scaling, colors, sorting priority, reveal presentation)
-- reads from here. There should be no `if rarity == "Legendary"` checks anywhere
-- else in the codebase -- look the tier up and read its fields instead.
--
-- Rarity is about memorable pulls, not just bigger numbers: income scaling is
-- only one of many identity fields a tier carries.
local RarityConfig = {}

-- Ordered lowest -> highest. Used for iteration, sorting, and UI priority.
RarityConfig.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

-- Each tier definition. Presentation fields (CardStyle, RevealEffects,
-- AudioPreset, AnimationProfile, ParticlePreset, Cinematic/Announcement flags)
-- are data-only right now -- no visuals are implemented in this phase, they exist
-- so future reveal/cinematic systems have a config to read.
RarityConfig.Tiers = {
	Common = {
		DisplayName = "Common",
		Color = Color3.fromRGB(158, 158, 158),
		MinPopularity = 1,
		MaxPopularity = 30,
		IncomeScaling = 1,
		Priority = 1, -- visual + UI + sort priority (higher = shown first / rarer)
		CardStyle = "Flat",
		RevealEffects = "None",
		AudioPreset = "reveal_common",
		AnimationProfile = "basic",
		ParticlePreset = "none",
		CinematicFlag = false,
		AnnouncementFlag = false,
	},
	Uncommon = {
		DisplayName = "Uncommon",
		Color = Color3.fromRGB(46, 204, 113),
		MinPopularity = 31,
		MaxPopularity = 50,
		IncomeScaling = 4,
		Priority = 2,
		CardStyle = "Flat",
		RevealEffects = "SoftGlow",
		AudioPreset = "reveal_uncommon",
		AnimationProfile = "basic",
		ParticlePreset = "sparkle_low",
		CinematicFlag = false,
		AnnouncementFlag = false,
	},
	Rare = {
		DisplayName = "Rare",
		Color = Color3.fromRGB(52, 152, 219),
		MinPopularity = 51,
		MaxPopularity = 65,
		IncomeScaling = 15,
		Priority = 3,
		CardStyle = "Glossy",
		RevealEffects = "Glow",
		AudioPreset = "reveal_rare",
		AnimationProfile = "standard",
		ParticlePreset = "sparkle",
		CinematicFlag = false,
		AnnouncementFlag = false,
	},
	Epic = {
		DisplayName = "Epic",
		Color = Color3.fromRGB(155, 89, 182),
		MinPopularity = 66,
		MaxPopularity = 80,
		IncomeScaling = 60,
		Priority = 4,
		CardStyle = "Glossy",
		RevealEffects = "GlowBurst",
		AudioPreset = "reveal_epic",
		AnimationProfile = "standard",
		ParticlePreset = "burst",
		CinematicFlag = false,
		AnnouncementFlag = false,
	},
	Legendary = {
		DisplayName = "Legendary",
		Color = Color3.fromRGB(241, 196, 15),
		MinPopularity = 81,
		MaxPopularity = 90,
		IncomeScaling = 250,
		Priority = 5,
		CardStyle = "Prismatic",
		RevealEffects = "Radiant",
		AudioPreset = "reveal_legendary",
		AnimationProfile = "premium",
		ParticlePreset = "radiant",
		CinematicFlag = false,
		AnnouncementFlag = true,
	},
	Mythic = {
		DisplayName = "Mythic",
		Color = Color3.fromRGB(231, 76, 60),
		MinPopularity = 91,
		MaxPopularity = 97,
		IncomeScaling = 1200,
		Priority = 6,
		CardStyle = "Prismatic",
		RevealEffects = "Explosive",
		AudioPreset = "reveal_mythic",
		AnimationProfile = "premium",
		ParticlePreset = "explosive",
		CinematicFlag = true,
		AnnouncementFlag = true,
	},
	Secret = {
		DisplayName = "Secret",
		Color = Color3.fromRGB(255, 255, 255), -- base fallback; client cycles hue for rainbow
		IsRainbow = true,
		MinPopularity = 98,
		MaxPopularity = 100,
		IncomeScaling = 6000,
		Priority = 7,
		CardStyle = "Rainbow",
		RevealEffects = "Cinematic",
		AudioPreset = "reveal_secret",
		AnimationProfile = "cinematic",
		ParticlePreset = "rainbow_storm",
		CinematicFlag = true,
		AnnouncementFlag = true,
	},
}

-- Map a popularity score (1-100) to its rarity tier name.
function RarityConfig.GetTierForPopularity(popularity: number): string
	for _, tierName in ipairs(RarityConfig.Order) do
		local tier = RarityConfig.Tiers[tierName]
		if popularity >= tier.MinPopularity and popularity <= tier.MaxPopularity then
			return tierName
		end
	end
	return "Common"
end

-- Safe lookup that never returns nil (falls back to Common) so a bad rarity
-- string can never crash a caller.
function RarityConfig.Get(tierName: string)
	return RarityConfig.Tiers[tierName] or RarityConfig.Tiers.Common
end

function RarityConfig.IsValidTier(tierName): boolean
	return RarityConfig.Tiers[tierName] ~= nil
end

-- Canonical roll weight: inverse to popularity. Popularity 100 -> weight 1
-- (rarest), popularity 20 -> weight 81 (common). Popular streamers are hard to
-- pull; this is the core odds rule.
function RarityConfig.GetWeight(popularity: number): number
	return 101 - popularity
end

return RarityConfig
