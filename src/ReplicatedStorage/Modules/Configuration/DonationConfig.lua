--!strict
-- DonationConfig: the single source of truth for the Global Donation Stand -- the
-- fixed Robux amounts, their Developer Product IDs, cooldowns, DataStore names,
-- board limits, UI sizes, and every player-facing string. Systems read from here;
-- they never hardcode an amount, a product id, or a copy string.
--
-- Robux donations are a real-money support path. They increase the donor's own
-- permanent RobuxDonatedLifetime flex stat and rank them on a global Top 100 board.
-- They are NOT gameplay currency: donations grant zero Streamer Bucks and never
-- touch the capped Bucks economy.
--
-- HUMAN STEP (see Section 18 of the Phase 3 spec): before a live release a human
-- must create eight Developer Products (one per amount) on the Creator Dashboard
-- and paste the real ids into ProductIds below. Until an id is non-zero the server
-- refuses to prompt that amount (and logs a warning at startup).
local DonationConfig = {}

-- Prompt anti-spam + leaderboard cadence.
DonationConfig.DonationPromptCooldown = 5 -- seconds between accepted prompt requests
DonationConfig.PromptPendingTimeout = 120 -- seconds a pending prompt lock can live before it auto-clears
DonationConfig.LeaderboardUpdateInterval = 30 -- seconds between OrderedDataStore refreshes
DonationConfig.LeaderboardRequestCooldown = 3 -- seconds between accepted client board requests
DonationConfig.MaxLeaderboardEntries = 100 -- Top N board size (spec requires 100)

-- DataStore names. OrderedDataStore ranks donors globally; the receipt store gives
-- ProcessReceipt idempotency across retries and sessions.
DonationConfig.OrderedDataStoreName = "RobuxDonatedGlobalV1"
DonationConfig.ReceiptDataStoreName = "DonationReceiptsV1"

-- The only donation amounts the game offers. Server always maps amount -> product
-- id from ProductIds; the client only ever sends an amount, never a product id.
DonationConfig.DonationAmounts = { 5, 10, 25, 50, 100, 250, 500, 1000 }

-- TODO(human): replace each 0 with the real Developer Product id from the Creator
-- Dashboard. A zero id means "not configured": the server blocks prompts for that
-- amount and logs a startup warning. Never ship to production with a 0 here.
DonationConfig.ProductIds = {
	[5] = 0,
	[10] = 0,
	[25] = 0,
	[50] = 0,
	[100] = 0,
	[250] = 0,
	[500] = 0,
	[1000] = 0,
}

DonationConfig.UI = {
	DonationPanelSize = Vector2.new(420, 440),
	LeaderboardPanelSize = Vector2.new(580, 650),
	AnimationSpeed = 0.2,
}

DonationConfig.Text = {
	StandTitle = "SUPPORT STREAMER GACHA IDLE",
	BoardHeader = "TOP 100 DONORS - ALL TIME",
	PanelTitle = "Support Streamer Gacha Idle",
	PanelSubtitle = "Donate Robux and join the all-time Top 100 Donors",
	PersonalStatPrefix = "Your Robux Donated:",
	ThanksFormat = "Thank you for donating %s Robux!", -- %s = formatted amount
	FailText = "Purchase was not completed",
	CancelText = "Purchase cancelled",
	LeaderboardTitle = "Global Robux Donated",
	LeaderboardSubtitle = "All-time Top 100 Supporters",
	FooterTotalPrefix = "Your Total:",
	FooterRankPrefix = "Your Rank:",
	UnrankedText = "Unranked",
	StaleSuffix = "(refresh delayed)",
	UsernameFallbackPrefix = "User ",
	TopDonorsButton = "Top Donors",
	DonateButton = "Donate",
	LeaderboardButton = "Leaderboard",
	EmptyBoardText = "No donors yet. Be the first to support the game!",
	NotConfiguredText = "Donations are not set up yet",
}

DonationConfig.Prompt = {
	ActionText = "Donate",
	ObjectText = "Global Donation Stand",
	HoldDuration = 0,
	MaxActivationDistance = 12,
}

DonationConfig.Effects = {
	SuccessSoundId = "", -- optional asset id; empty means no sound
	SuccessParticleEnabled = true,
}

DonationConfig.Logging = {
	Enabled = true,
}

-- Builds a reverse lookup { [productId] = amount } from the configured non-zero
-- product ids. ProcessReceipt and prompt validation both resolve the amount for a
-- product exclusively through this map -- the amount is NEVER read from the client
-- or from the receipt. Zero (unconfigured) ids are intentionally excluded.
function DonationConfig.BuildReverseMap(): { [number]: number }
	local reverse = {}
	for _, amount in ipairs(DonationConfig.DonationAmounts) do
		local productId = DonationConfig.ProductIds[amount]
		if type(productId) == "number" and productId > 0 then
			reverse[productId] = amount
		end
	end
	return reverse
end

-- True only when the amount is one of the configured amounts AND its product id is
-- a real (non-zero) id -- i.e. safe to actually prompt.
function DonationConfig.IsAmountPromptable(amount: number): boolean
	if type(amount) ~= "number" or amount ~= amount then
		return false
	end
	local productId = DonationConfig.ProductIds[amount]
	return type(productId) == "number" and productId > 0
end

-- True if the amount is part of the offered set (regardless of whether its product
-- id is configured yet). Used for UI button generation.
function DonationConfig.IsKnownAmount(amount: number): boolean
	if type(amount) ~= "number" then
		return false
	end
	for _, value in ipairs(DonationConfig.DonationAmounts) do
		if value == amount then
			return true
		end
	end
	return false
end

return DonationConfig
