-- The Phase 1 roster: 25 recognizable streamers. Kept intentionally small -- no filler.
-- popularity_score is a gameplay-balance value (not a live analytics feed) used to derive
-- rarity_tier, roll weight, and base_income.
local RarityConfig = require(script.Parent.RarityConfig)

local RawRoster = {
	{ name = "Kai Cenat", popularity_score = 100 },
	{ name = "Speed", popularity_score = 99 },
	{ name = "xQc", popularity_score = 98 },
	{ name = "MrBeast", popularity_score = 97 },
	{ name = "Adin Ross", popularity_score = 95 },
	{ name = "Jynxzi", popularity_score = 93 },
	{ name = "Duke Dennis", popularity_score = 91 },
	{ name = "CaseOh", popularity_score = 88 },
	{ name = "Fanum", popularity_score = 85 },
	{ name = "Ninja", popularity_score = 84 },
	{ name = "Stable Ronaldo", popularity_score = 82 },
	{ name = "Lacy", popularity_score = 75 },
	{ name = "JasonTheWeen", popularity_score = 72 },
	{ name = "Rakai", popularity_score = 70 },
	{ name = "Agent 00", popularity_score = 68 },
	{ name = "Sketch", popularity_score = 66 },
	{ name = "Plaqueboymax", popularity_score = 60 },
	{ name = "N3on", popularity_score = 58 },
	{ name = "Ludwig", popularity_score = 55 },
	{ name = "Valkyrae", popularity_score = 53 },
	{ name = "Pokimane", popularity_score = 52 },
	{ name = "Cinna", popularity_score = 40 },
	{ name = "Ranboo", popularity_score = 33 },
	{ name = "Punga", popularity_score = 22 },
	{ name = "Slime", popularity_score = 18 },
}

local StreamerData = {}
StreamerData.Streamers = {}
StreamerData.ById = {}

for index, entry in ipairs(RawRoster) do
	local popularity = entry.popularity_score
	local streamer = {
		id = index,
		name = entry.name,
		popularity_score = popularity,
		rarity_tier = RarityConfig.GetTierForPopularity(popularity),
		base_income = popularity * 2,
		weight = RarityConfig.GetWeight(popularity),

		-- Placeholders for future phases only -- no visuals/logic use these yet.
		collection = "",
		banner = "",
		region = "",
		is_featured = false,
		reveal_animation_id = "",
		reveal_sound = "",
		card_background = "",
		particle_preset = "",
	}
	StreamerData.Streamers[index] = streamer
	StreamerData.ById[streamer.id] = streamer
end

function StreamerData.GetById(id)
	return StreamerData.ById[id]
end

return StreamerData
