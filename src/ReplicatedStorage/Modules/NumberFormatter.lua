-- Formats currency for display. Phase 1 economy only needs K/M, but this scales to T.
local NumberFormatter = {}

local SUFFIXES = { "", "K", "M", "B", "T" }

function NumberFormatter.Format(value)
	value = math.floor(value or 0)
	local negative = value < 0
	value = math.abs(value)

	local tier = 1
	local scaled = value
	while scaled >= 1000 and tier < #SUFFIXES do
		scaled = scaled / 1000
		tier += 1
	end

	local formatted
	if tier == 1 then
		formatted = tostring(scaled)
	else
		formatted = string.format("%.2f%s", scaled, SUFFIXES[tier])
	end

	return (negative and "-" or "") .. formatted
end

return NumberFormatter
