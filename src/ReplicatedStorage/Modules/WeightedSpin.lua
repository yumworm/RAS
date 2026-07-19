-- Server-authoritative weighted roll. Weight is inverse to popularity (see RarityConfig).
local WeightedSpin = {}

function WeightedSpin.Roll(streamers)
	local totalWeight = 0
	for _, streamer in ipairs(streamers) do
		totalWeight += streamer.weight
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, streamer in ipairs(streamers) do
		cumulative += streamer.weight
		if roll <= cumulative then
			return streamer
		end
	end

	return streamers[#streamers]
end

return WeightedSpin
