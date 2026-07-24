--!strict
-- RNG: the single random system for the whole game. Nothing else generates
-- random streamers or rolls weighted outcomes -- if you need randomness for a
-- pull, it goes through here. This keeps odds auditable and gives future systems
-- (Lucky Spins, Luck Potions, Weekend Events, Gamepass luck, Admin events, pity)
-- one place to plug their modifiers into.
--
-- Server-authoritative: this module lives under ServerScriptService so clients
-- can never see or influence the roll.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configuration = ReplicatedStorage.Modules.Configuration
local GameConfig = require(Configuration.GameConfig)

local RNG = {}
RNG.__index = RNG

function RNG.new(seed: number?)
	return setmetatable({
		_random = if seed then Random.new(seed) else Random.new(),
	}, RNG)
end

function RNG:NextNumber(min: number?, max: number?): number
	if min and max then
		return self._random:NextNumber(min, max)
	end
	return self._random:NextNumber()
end

function RNG:NextInteger(min: number, max: number): number
	return self._random:NextInteger(min, max)
end

-- Generic weighted pick. `entries` is an array; `getWeight(entry)` returns a
-- positive weight. Returns the chosen entry (never nil for a non-empty pool).
function RNG:WeightedPick(entries, getWeight)
	local total = 0
	for _, entry in ipairs(entries) do
		local w = getWeight(entry)
		if w > 0 then
			total += w
		end
	end
	if total <= 0 then
		return entries[1]
	end

	local roll = self._random:NextNumber() * total
	local cumulative = 0
	for _, entry in ipairs(entries) do
		local w = getWeight(entry)
		if w > 0 then
			cumulative += w
			if roll <= cumulative then
				return entry
			end
		end
	end
	return entries[#entries]
end

-- The one weighted-selection hook every spin flows through.
--
-- `modifiers` is an optional table of future knobs, all defaulted to neutral
-- today so behaviour is exactly the base inverse-popularity odds:
--   luck    -> scales rare streamers' weight up (future Luck Potion / Gamepass)
--   event   -> global weekend/event multiplier on rare weights
--   pity     -> additive floor toward rares after dry streaks (future)
-- None of these change results while left at their defaults.
function RNG:RollStreamer(streamers, modifiers)
	modifiers = modifiers or {}
	local luck = modifiers.luck or GameConfig.Multipliers.LuckDefault
	local event = modifiers.event or GameConfig.Multipliers.EventDefault
	local pity = modifiers.pity or GameConfig.Multipliers.PityDefault

	local function weightFor(streamer)
		local baseWeight = streamer.weight -- inverse to popularity (see RarityConfig)
		-- Rarer streamers (higher popularity => lower baseWeight) get boosted by
		-- luck/event. With luck=event=1 and pity=0 this is exactly baseWeight.
		local rarityBoost = (luck * event)
		local boosted = baseWeight
		if rarityBoost ~= 1 then
			-- Boost is applied inversely to base weight so it favours rares.
			boosted = baseWeight + (baseWeight * (rarityBoost - 1) * (100 - baseWeight) / 100)
		end
		return math.max(boosted + pity, 0.0001)
	end

	return self:WeightedPick(streamers, weightFor)
end

return RNG
