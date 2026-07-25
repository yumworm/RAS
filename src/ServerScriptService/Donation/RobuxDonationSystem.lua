--!strict
-- RobuxDonationSystem: the ONLY system that awards Robux-donation credit. It gates
-- purchase prompts, owns MarketplaceService.ProcessReceipt for the donation
-- products, and credits the donor's permanent RobuxDonatedLifetime exactly once.
--
-- Security spine (never violated):
--   * The client may only REQUEST a prompt for an amount. It never sends a product
--     id, never claims a purchase, and can never set a total.
--   * The amount credited is resolved from server config (the product reverse map)
--     ONLY -- never from the client or the receipt payload.
--   * Credit happens ONLY inside ProcessReceipt, once per PurchaseId, and only when
--     the profile write is durable. Opening a prompt, a client "I paid" event, or
--     PromptProductPurchaseFinished never move a single point.
--   * Donations grant ZERO Streamer Bucks and never touch the capped Bucks economy.
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DonationConfig = require(ReplicatedStorage.Modules.Configuration.DonationConfig)
local NumberFormatter = require(ReplicatedStorage.Modules.Shared.NumberFormatter)

local Server = script.Parent.Parent
local Runtime = require(Server.Core.Runtime)
local StateSync = require(Server.Core.StateSync)
local Logger = require(Server.Utilities.Logger)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RobuxDonationSystem = {}
local Services: any

local receiptStore = DataStoreService:GetDataStore(DonationConfig.ReceiptDataStoreName)
local reverseMap: { [number]: number } = {} -- productId -> amount (non-zero ids only)

function RobuxDonationSystem.Init(services)
	Services = services

	reverseMap = DonationConfig.BuildReverseMap()

	-- Loudly warn about any amount whose product id is still 0. The game keeps
	-- running; prompts for those amounts are simply refused until a real id is set.
	for _, amount in ipairs(DonationConfig.DonationAmounts) do
		if not DonationConfig.IsAmountPromptable(amount) then
			Logger.Warn(
				"Donation",
				string.format(
					"Product id for %d Robux is not configured (0) -- prompts for this amount are blocked. "
						.. "Paste the real Developer Product id into DonationConfig.ProductIds.",
					amount
				)
			)
		end
	end
end

--------------------------------------------------------------------------------
-- Outbound helpers
--------------------------------------------------------------------------------

local function notify(player: Player, kind: string, message: string, amount: number?, newTotal: number?)
	Remotes.DonationNotification:FireClient(player, {
		Kind = kind,
		Amount = amount,
		NewTotal = newTotal,
		Message = message,
	})
end

-- Replicate the donor's fresh donation stats to their live session (read-only
-- mirror; StateController applies the `donation` key generically).
local function replicateDonationStats(userId: number)
	local stats = Services.ProfileService.GetDonationStats(userId)
	StateSync.Mark(userId, "donation", {
		robuxDonatedLifetime = stats.robuxDonatedLifetime,
		donationPurchaseCount = stats.donationPurchaseCount,
		biggestRobuxDonation = stats.biggestRobuxDonation,
	})
	Services.NetworkService.FlushState(userId)
end

--------------------------------------------------------------------------------
-- Prompt request (validated + rate-limited + pending-locked)
--------------------------------------------------------------------------------

local function reply(player: Player, ok: boolean, reason: string)
	Remotes.DonationPromptResult:FireClient(player, { ok = ok, reason = reason })
end

local function handleDonationPrompt(player: Player, amount: any)
	local userId = player.UserId
	local runtime = Runtime.Get(userId)
	local profile = Services.ProfileService.Get(userId)

	-- Player must be fully initialized with a loaded profile.
	if not runtime or not profile or not runtime.initialized then
		reply(player, false, "ProfileNotLoaded")
		return
	end
	-- Amount must be a configured amount.
	if not DonationConfig.IsKnownAmount(amount) then
		reply(player, false, "InvalidAmount")
		return
	end
	-- Amount must have a real (non-zero) product id.
	if not DonationConfig.IsAmountPromptable(amount) then
		reply(player, false, "ProductNotConfigured")
		return
	end

	local now = os.clock()

	-- Pending lock: one open prompt at a time, auto-expiring after the timeout so a
	-- prompt the player dismissed without any callback can never wedge them.
	if runtime.donationPending > 0 and (now - runtime.donationPending) < DonationConfig.PromptPendingTimeout then
		reply(player, false, "Pending")
		return
	end

	-- Cooldown between accepted prompts (anti-spam).
	if (now - runtime.lastDonationPromptAt) < DonationConfig.DonationPromptCooldown then
		reply(player, false, "Cooldown")
		return
	end

	local productId = DonationConfig.ProductIds[amount]
	runtime.donationPending = now
	runtime.lastDonationPromptAt = now

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not ok then
		runtime.donationPending = 0
		Logger.Error("Donation", string.format("PromptProductPurchase failed for %d: %s", userId, tostring(err)))
		reply(player, false, "PromptFailed")
		return
	end

	Logger.Info("Donation", string.format("%d prompted for %d Robux (product %d)", userId, amount, productId))
	-- Mid-funnel analytics (developer-only; log-only, never affects the purchase).
	if Services.AnalyticsMonitorSystem then
		Services.AnalyticsMonitorSystem.LogDonationPromptRequested(userId, productId)
	end
	reply(player, true, "Prompted")
end

--------------------------------------------------------------------------------
-- Leaderboard request (cached; cheap; rate-limited)
--------------------------------------------------------------------------------

local function handleLeaderboardRequest(player: Player)
	local userId = player.UserId
	local runtime = Runtime.Get(userId)
	if not runtime then
		return
	end
	local now = os.clock()
	if (now - runtime.lastLeaderboardRequestAt) < DonationConfig.LeaderboardRequestCooldown then
		return -- silently drop; the client already has a recent snapshot
	end
	runtime.lastLeaderboardRequestAt = now
	local snapshot = Services.DonationLeaderboard.GetSnapshotForPlayer(userId)
	Remotes.GlobalDonorLeaderboardUpdated:FireClient(player, snapshot)
end

-- Push the latest board to every online player (called after a refresh / donation).
function RobuxDonationSystem.BroadcastLeaderboard()
	for _, player in ipairs(Players:GetPlayers()) do
		local snapshot = Services.DonationLeaderboard.GetSnapshotForPlayer(player.UserId)
		Remotes.GlobalDonorLeaderboardUpdated:FireClient(player, snapshot)
	end
end

--------------------------------------------------------------------------------
-- Receipt persistence (idempotency audit record)
--------------------------------------------------------------------------------

local function receiptAlreadyGranted(purchaseId: string): (boolean, boolean)
	-- Returns (granted, checkOk). checkOk=false means the store read errored and the
	-- caller should fall through to the in-profile guard (which is authoritative).
	local ok, record = pcall(function()
		return receiptStore:GetAsync(purchaseId)
	end)
	if not ok then
		return false, false
	end
	return type(record) == "table" and record.Status == "Granted", true
end

local function saveReceiptRecord(purchaseId: string, userId: number, productId: number, amount: number)
	local record = {
		PurchaseId = purchaseId,
		DonorUserId = userId,
		ProductId = productId,
		Amount = amount,
		ProcessedAt = os.time(),
		Status = "Granted",
	}
	-- Best-effort with a couple of quick retries. A lost write is NOT a correctness
	-- problem: the in-profile recentReceipts guard already prevents double credit.
	for attempt = 1, 3 do
		local ok = pcall(function()
			receiptStore:SetAsync(purchaseId, record)
		end)
		if ok then
			return true
		end
		if attempt < 3 then
			task.wait(0.5 * attempt)
		end
	end
	Logger.Warn("Donation", string.format("Receipt record write failed for %s (credit is still safe)", purchaseId))
	return false
end

--------------------------------------------------------------------------------
-- ProcessReceipt: the single authoritative credit path
--------------------------------------------------------------------------------

local function processReceipt(receiptInfo)
	local purchaseId = tostring(receiptInfo.PurchaseId)
	local userId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId

	-- Resolve the amount from server config ONLY. The receipt payload's currency
	-- amount is deliberately ignored.
	local amount = reverseMap[productId]
	if not amount then
		-- Not one of our donation products. This game has no other ProcessReceipt
		-- owner, so an unknown product means a misconfiguration. We grant (rather than
		-- NotProcessedYet) so Roblox does not retry the same bad receipt forever; no
		-- donation stat is touched. If another system ever needs receipts, route here.
		Logger.Warn("Donation", string.format("Receipt for unknown product %s -> granting without credit", tostring(productId)))
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Fast path: if we already have a Granted record, stop before any write.
	local granted, checkOk = receiptAlreadyGranted(purchaseId)
	if checkOk and granted then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Apply the credit exactly once (works whether the donor is online or offline).
	local newLifetime, applied, ok = Services.ProfileService.CreditDonation(userId, amount, purchaseId)
	if not ok then
		-- Transient DataStore failure -> tell Roblox to retry later. The credit was
		-- NOT applied, so no double-credit risk.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Persist the audit/idempotency record (best-effort; guard already protects us).
	saveReceiptRecord(purchaseId, userId, productId, amount)

	-- Update the global board (best-effort; retried by the leaderboard if it fails).
	Services.DonationLeaderboard.SubmitScore(userId, newLifetime)

	if applied then
		Logger.Info(
			"Donation",
			string.format("Granted %d Robux to %d (lifetime %d, receipt %s)", amount, userId, newLifetime, purchaseId)
		)
		-- Bottom-of-funnel analytics (developer-only). Log-only; the grant already
		-- happened above and is never re-run here.
		if Services.AnalyticsMonitorSystem then
			Services.AnalyticsMonitorSystem.LogDonationGranted(userId, amount)
		end
		-- Phase 6: append to the live global feed EXACTLY here -- inside the first-time
		-- `applied` branch, after the durable credit. A duplicate receipt lands in the
		-- `else` branch below and never reaches this line, so it can never rebroadcast.
		-- The feed is a donation-to-the-game record: donor display name only, no receiver.
		if Services.DonationFeedSystem then
			local donorName = Services.DonationFeedSystem.ResolveDonorName(userId)
			Services.DonationFeedSystem.Append(donorName, amount, os.time())
		end
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local runtime = Runtime.Get(userId)
			if runtime then
				runtime.donationPending = 0 -- clear any pending lock
			end
			replicateDonationStats(userId)
			local thanks = string.format(DonationConfig.Text.ThanksFormat, NumberFormatter.FormatRobux(amount))
			notify(player, "Success", thanks, amount, newLifetime)
			-- Ask the stand for a celebratory effect near it.
			if Services.GlobalDonationStandSystem then
				Services.GlobalDonationStandSystem.PlayDonationEffect(player, amount)
			end
		end
	else
		-- Guard caught a duplicate we didn't have a record for. Ensure the record and
		-- board now reflect reality; no notification (nothing changed this time).
		Logger.Info("Donation", string.format("Duplicate receipt %s for %d -> already credited", purchaseId, userId))
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function RobuxDonationSystem.Start()
	Remotes.RequestDonationPrompt.OnServerEvent:Connect(function(player, amount)
		local ok, err = pcall(handleDonationPrompt, player, amount)
		if not ok then
			Logger.Error("Donation", string.format("Prompt handler error: %s", tostring(err)))
		end
	end)

	Remotes.RequestGlobalDonorLeaderboard.OnServerEvent:Connect(function(player)
		local ok, err = pcall(handleLeaderboardRequest, player)
		if not ok then
			Logger.Error("Donation", string.format("Leaderboard request error: %s", tostring(err)))
		end
	end)

	-- Own ProcessReceipt for the whole game. Wrapped so a throw never becomes an
	-- uncaught error (which Roblox would treat as "not processed" anyway); we return
	-- NotProcessedYet explicitly so the purchase is retried rather than lost.
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local ok, result = pcall(processReceipt, receiptInfo)
		if not ok then
			Logger.Error("Donation", string.format("ProcessReceipt error: %s", tostring(result)))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return result
	end
end

return RobuxDonationSystem
