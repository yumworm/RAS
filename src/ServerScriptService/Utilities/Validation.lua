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
local PresentationConfig = require(Configuration.PresentationConfig)
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

-- Phase 4 Two-Tier Presentation checks. Errors here are fatal (they disable the
-- gacha until fixed rather than let it roll on unsafe content); warnings are
-- logged but harmless (dev placeholder ids, stray fields ignored at runtime).
local function validatePresentation(errors, warnings)
	-- Roster sizing. Over the max is fatal (fail safe, never silently truncate);
	-- an empty roster is fatal; below the min is a soft warning.
	local count = StreamerDatabase.Count
	if count > PresentationConfig.MaxRosterSize then
		table.insert(
			errors,
			string.format(
				"Roster has %d streamers, above the max of %d (gacha disabled until fixed)",
				count,
				PresentationConfig.MaxRosterSize
			)
		)
	elseif count < 1 then
		table.insert(errors, "Roster is empty; gacha cannot roll")
	elseif count < PresentationConfig.MinRosterSize then
		table.insert(
			warnings,
			string.format(
				"Roster has %d streamers, below the target minimum of %d",
				count,
				PresentationConfig.MinRosterSize
			)
		)
	end

	for _, streamer in ipairs(StreamerDatabase.All) do
		local label = streamer.name or ("id " .. tostring(streamer.id))
		local rarity = streamer.rarity_tier
		local ptype = streamer.presentation_type

		-- PresentationType must be exactly one of the two strings.
		if ptype ~= "Flagship" and ptype ~= "Standard" then
			table.insert(errors, string.format("%s has invalid presentation_type: %s", label, tostring(ptype)))
		elseif RarityConfig.IsValidTier(rarity) then
			-- And it must agree with the rarity-derived tier (no drift).
			local expected = PresentationConfig.GetPresentationType(rarity)
			if ptype ~= expected then
				table.insert(
					errors,
					string.format("%s presentation_type %s does not match rarity-derived %s", label, ptype, expected)
				)
			end
		end

		local pres = streamer.presentation
		if type(pres) == "table" then
			if ptype == "Flagship" then
				-- Flagship required asset fields must be present (non-nil). Empty /
				-- placeholder ids are allowed in dev but warned so they are not
				-- forgotten before ship.
				local requiredByAsset = {
					RevealAnimId = pres.reveal_animation_id,
					RevealSoundId = pres.reveal_sound,
					CustomBannerId = pres.banner_asset,
					ParticlePreset = pres.particle_preset,
				}
				for _, fieldName in ipairs(PresentationConfig.Flagship.RequireFields) do
					local value = requiredByAsset[fieldName]
					if value == nil then
						table.insert(
							errors,
							string.format("%s (Flagship) is missing required asset %s", label, fieldName)
						)
					elseif fieldName == "ParticlePreset" then
						if not PresentationConfig.ParticlePresets[value] then
							table.insert(
								warnings,
								string.format(
									"%s (Flagship) ParticlePreset %q is not registered; will fall back to %s",
									label,
									tostring(value),
									PresentationConfig.DefaultParticlePreset
								)
							)
						end
					elseif not PresentationConfig.IsAssetSet(value) then
						table.insert(
							warnings,
							string.format(
								"%s (Flagship) %s is a placeholder id; supply a real asset before ship",
								label,
								fieldName
							)
						)
					end
				end
			elseif ptype == "Standard" then
				-- Standard streamers must not carry bespoke Flagship assets; if they
				-- do, warn and note they are ignored at runtime.
				if PresentationConfig.IsAssetSet(pres.reveal_animation_id) then
					table.insert(
						warnings,
						string.format("%s (Standard) has a reveal_animation_id; it will be ignored", label)
					)
				end
				if PresentationConfig.IsAssetSet(pres.banner_asset) then
					table.insert(warnings, string.format("%s (Standard) has a banner_asset; it will be ignored", label))
				end
				if PresentationConfig.IsAssetSet(pres.voice_line) then
					table.insert(warnings, string.format("%s (Standard) has a voice_line; it will be ignored", label))
				end
			end
		end
	end
end

-- Runs all checks. Returns two arrays: fatal `errors` (empty = OK) and non-fatal
-- `warnings`. Callers gate the gacha on errors and log warnings for developers.
function Validation.ValidateAll()
	local errors = {}
	local warnings = {}
	validateFormatter(errors)
	validateDatabase(errors)
	validatePresentation(errors, warnings)
	return errors, warnings
end

return Validation
