--!strict
-- Validation: runs once at server startup to catch broken content/config BEFORE
-- players can hit it. It reports problems (it does not silently mutate data); the
-- game still boots and fails safe (bad rarities fall back to Common, etc.), but
-- every issue is logged loudly for developers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configuration = ReplicatedStorage.Modules.Configuration
local RarityConfig = require(Configuration.RarityConfig)
local StreamerDatabase = require(Configuration.StreamerDatabase)
local WorldConfig = require(Configuration.WorldConfig)
local NumberFormatter = require(ReplicatedStorage.Modules.Shared.NumberFormatter)

local Validation = {}

local EXPECTED_SUFFIXES = { "", "K", "M", "B", "T" }

local function validateFormatter(errors)
	-- The formatter must stop at T. No Qa/Qi/Sx/etc. -- ever.
	if #NumberFormatter.Suffixes ~= #EXPECTED_SUFFIXES then
		table.insert(errors, "NumberFormatter defines an unexpected number of suffixes (must be exactly K/M/B/T)")
		return
	end
	for i, suffix in ipairs(EXPECTED_SUFFIXES) do
		if NumberFormatter.Suffixes[i] ~= suffix then
			table.insert(
				errors,
				string.format(
					"NumberFormatter suffix %d is %q, expected %q",
					i,
					tostring(NumberFormatter.Suffixes[i]),
					suffix
				)
			)
		end
	end
end

local function validateDatabase(errors)
	local seenNames = {}
	for _, streamer in ipairs(StreamerDatabase.All) do
		local label = streamer.name or ("id " .. tostring(streamer.id))

		-- Duplicate names
		if streamer.name then
			if seenNames[streamer.name] then
				table.insert(errors, string.format("Duplicate streamer name: %q", streamer.name))
			end
			seenNames[streamer.name] = true
		else
			table.insert(errors, string.format("Streamer %s is missing a name", label))
		end

		-- Popularity 1-100
		local pop = streamer.popularity_score
		if type(pop) ~= "number" or pop < 1 or pop > 100 then
			table.insert(errors, string.format("%s has invalid popularity_score: %s", label, tostring(pop)))
		end

		-- Rarity present and known
		if not RarityConfig.IsValidTier(streamer.rarity_tier) then
			table.insert(errors, string.format("%s has unknown rarity_tier: %s", label, tostring(streamer.rarity_tier)))
		elseif type(pop) == "number" then
			-- Rarity must match the popularity-derived tier (no drift).
			local expected = RarityConfig.GetTierForPopularity(pop)
			if streamer.rarity_tier ~= expected then
				table.insert(
					errors,
					string.format(
						"%s rarity %s does not match popularity-derived %s",
						label,
						streamer.rarity_tier,
						expected
					)
				)
			end
		end

		-- Income present and positive
		if type(streamer.base_income) ~= "number" or streamer.base_income <= 0 then
			table.insert(errors, string.format("%s has missing/non-positive base_income", label))
		end

		-- Collection: exactly one, valid
		if not WorldConfig.IsValidCollection(streamer.collection) then
			table.insert(
				errors,
				string.format("%s has invalid/missing Collection: %s", label, tostring(streamer.collection))
			)
		end

		-- Banners: at least one, all valid
		if type(streamer.banners) ~= "table" or #streamer.banners < 1 then
			table.insert(errors, string.format("%s must belong to at least one Banner", label))
		else
			for _, banner in ipairs(streamer.banners) do
				if not WorldConfig.IsValidBanner(banner) then
					table.insert(errors, string.format("%s references invalid Banner: %s", label, tostring(banner)))
				end
			end
		end

		-- Region: valid
		if not WorldConfig.IsValidRegion(streamer.region) then
			table.insert(errors, string.format("%s has invalid/missing Region: %s", label, tostring(streamer.region)))
		end

		-- Presentation asset references must be strings (data-only for now).
		local pres = streamer.presentation
		if type(pres) ~= "table" then
			table.insert(errors, string.format("%s is missing presentation data", label))
		else
			for _, field in ipairs({
				"reveal_animation_id",
				"reveal_sound",
				"banner_asset",
				"card_background",
				"particle_preset",
			}) do
				if type(pres[field]) ~= "string" then
					table.insert(errors, string.format("%s presentation.%s must be a string", label, field))
				end
			end
		end

		-- Featured streamers must reference a real reveal animation asset.
		if streamer.is_featured and (type(pres) ~= "table" or pres.reveal_animation_id == "") then
			table.insert(errors, string.format("%s is Featured but has no reveal_animation_id", label))
		end
	end
end

-- Runs all checks. Returns an array of human-readable error strings (empty = OK).
function Validation.ValidateAll()
	local errors = {}
	validateFormatter(errors)
	validateDatabase(errors)
	return errors
end

return Validation
