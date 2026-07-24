--!strict
-- WorldConfig: defines the valid "content buckets" a streamer can be assigned to.
-- Startup validation checks every streamer against these sets. Future content
-- (new Collections, Banners, seasonal rotations, Regions) is added by editing
-- these lists + the database -- no core logic changes.
local WorldConfig = {}

-- Every streamer belongs to exactly ONE collection.
WorldConfig.Collections = {
	Originals = { DisplayName = "Originals", Description = "The launch roster." },
}

-- Every streamer appears in AT LEAST ONE banner. Banners are how spin machines
-- will later filter their pools.
WorldConfig.Banners = {
	Standard = { DisplayName = "Standard", Description = "The default spin pool." },
}

-- Every streamer has a valid region.
WorldConfig.Regions = {
	NA = { DisplayName = "North America" },
	EU = { DisplayName = "Europe" },
	SA = { DisplayName = "South America" },
	Global = { DisplayName = "Global" },
}

function WorldConfig.IsValidCollection(name): boolean
	return name ~= nil and WorldConfig.Collections[name] ~= nil
end

function WorldConfig.IsValidBanner(name): boolean
	return name ~= nil and WorldConfig.Banners[name] ~= nil
end

function WorldConfig.IsValidRegion(name): boolean
	return name ~= nil and WorldConfig.Regions[name] ~= nil
end

return WorldConfig
