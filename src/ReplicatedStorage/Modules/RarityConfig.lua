-- Rarity tier definitions shared by server (income math) and client (colors/animation).
local RarityConfig = {}

RarityConfig.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

RarityConfig.Tiers = {
	Common = {
		MinPopularity = 1,
		MaxPopularity = 30,
		Color = Color3.fromRGB(158, 158, 158),
		IncomeMultiplier = 1.0,
	},
	Uncommon = {
		MinPopularity = 31,
		MaxPopularity = 50,
		Color = Color3.fromRGB(46, 204, 113),
		IncomeMultiplier = 1.15,
	},
	Rare = {
		MinPopularity = 51,
		MaxPopularity = 65,
		Color = Color3.fromRGB(52, 152, 219),
		IncomeMultiplier = 1.35,
	},
	Epic = {
		MinPopularity = 66,
		MaxPopularity = 80,
		Color = Color3.fromRGB(155, 89, 182),
		IncomeMultiplier = 1.6,
	},
	Legendary = {
		MinPopularity = 81,
		MaxPopularity = 90,
		Color = Color3.fromRGB(241, 196, 15),
		IncomeMultiplier = 2.0,
	},
	Mythic = {
		MinPopularity = 91,
		MaxPopularity = 97,
		Color = Color3.fromRGB(231, 76, 60),
		IncomeMultiplier = 2.6,
	},
	Secret = {
		MinPopularity = 98,
		MaxPopularity = 100,
		-- Base fallback color; client cycles hue for the actual rainbow look.
		Color = Color3.fromRGB(255, 255, 255),
		IncomeMultiplier = 3.5,
		IsRainbow = true,
	},
}

function RarityConfig.GetTierForPopularity(popularity)
	for _, tierName in ipairs(RarityConfig.Order) do
		local tier = RarityConfig.Tiers[tierName]
		if popularity >= tier.MinPopularity and popularity <= tier.MaxPopularity then
			return tierName
		end
	end
	return "Common"
end

-- Inverse-to-popularity weight: popularity 100 -> weight 1 (rarest), popularity 20 -> weight 81 (common).
function RarityConfig.GetWeight(popularity)
	return 101 - popularity
end

return RarityConfig
