--!strict
-- NumberFormatter: the ONE formatter every number in the game passes through.
--
-- It intentionally supports only K, M, B, T. This is a deliberate design
-- constraint, not an oversight: the economy is capped at ~$10T, so no larger
-- suffix should ever be needed. If a value comes in above the T range it is
-- clamped for display -- that situation means the economy has a balancing bug to
-- fix, NOT that a Qa/Qi/Sx suffix should be added here.
local NumberFormatter = {}

-- The complete, intentional suffix set. Startup validation asserts this exact
-- list so nobody quietly extends it.
NumberFormatter.Suffixes = { "", "K", "M", "B", "T" }

function NumberFormatter.Format(value: number): string
	if typeof(value) ~= "number" or value ~= value then -- nil-safe + NaN guard
		return "0"
	end

	local negative = value < 0
	value = math.floor(math.abs(value))

	local tier = 1
	local scaled = value
	while scaled >= 1000 and tier < #NumberFormatter.Suffixes do
		scaled = scaled / 1000
		tier += 1
	end

	local formatted
	if tier == 1 then
		formatted = tostring(scaled) -- whole numbers below 1K: no decimals
	else
		formatted = string.format("%.2f%s", scaled, NumberFormatter.Suffixes[tier])
	end

	return (negative and "-" or "") .. formatted
end

-- Extended, UNCAPPED suffix set used ONLY by FormatRobux. This is intentionally
-- separate from Suffixes above: Streamer Bucks stop at T (a capped economy), but
-- RobuxDonatedLifetime is an uncapped flex stat that may legitimately climb past T
-- (Qa, Qi, Sx, ...). Startup validation asserts Suffixes stays K/M/B/T; it does not
-- constrain this list, so extending the two never collides.
NumberFormatter.RobuxSuffixes =
	{ "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "UDc", "DDc" }

-- Format a Robux-donated total. Never clamps to the Bucks economy cap and never
-- routes through Format() (which would flatten anything above T into "T"). Used for
-- the donation panel personal stat, the Top 100 board, and notification amounts.
function NumberFormatter.FormatRobux(value: number): string
	if typeof(value) ~= "number" or value ~= value then -- nil-safe + NaN guard
		return "0"
	end

	local negative = value < 0
	value = math.floor(math.abs(value))

	local tier = 1
	local scaled = value
	while scaled >= 1000 and tier < #NumberFormatter.RobuxSuffixes do
		scaled = scaled / 1000
		tier += 1
	end

	local formatted
	if tier == 1 then
		formatted = tostring(scaled) -- whole numbers below 1K: no decimals
	else
		formatted = string.format("%.2f%s", scaled, NumberFormatter.RobuxSuffixes[tier])
	end

	return (negative and "-" or "") .. formatted
end

return NumberFormatter
