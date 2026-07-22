--!strict
-- NetworkService: the boundary between untrusted clients and authoritative server
-- logic. The client may only *request* actions ("I want to spin"). The server
-- decides everything else -- what was rolled, how much it earned, whether it was
-- allowed. Currency, inventory, roll results, income and stats are never trusted
-- from the client.
--
-- Outbound, it sends the client only what changed (via StateSync deltas) plus one
-- full snapshot at init, rather than streaming the whole profile constantly.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = ReplicatedStorage.Modules.Configuration
local GameConfig = require(Configuration.GameConfig)
local StreamerDatabase = require(Configuration.StreamerDatabase)

local Server = script.Parent.Parent
local Runtime = require(Server.Core.Runtime)
local StateSync = require(Server.Core.StateSync)
local ExpansionHooks = require(Server.Core.ExpansionHooks)
local Logger = require(Server.Utilities.Logger)
local RNG = require(Server.Utilities.RNG)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local NetworkService = {}
local Services: any
local rng = RNG.new()

function NetworkService.Init(services)
	Services = services
end

--------------------------------------------------------------------------------
-- Outbound state
--------------------------------------------------------------------------------

-- Full snapshot, sent exactly once when the player finishes initializing.
function NetworkService.SendInitialState(player: Player)
	local userId = player.UserId
	local profile = Services.ProfileService.Get(userId)
	local runtime = Runtime.Get(userId)
	if not profile or not runtime then
		return
	end

	StateSync.Clear(userId) -- drop any deltas; the snapshot supersedes them

	Remotes.InitialState:FireClient(player, {
		currency = profile.economy.currency,
		income = runtime.incomePerSecond,
		inventory = Services.InventoryService.GetSortedInventory(userId),
		collection = Services.CollectionService.GetSummary(userId),
		session = Services.SessionTracker.GetSummary(userId),
		stats = {
			totalSpins = profile.stats.totalSpins,
			totalPlayTime = profile.stats.totalPlayTime,
			bestPull = profile.stats.bestPull,
		},
		settings = profile.settings,
		economyCap = GameConfig.EconomyCap,
		donation = {
			robuxDonatedLifetime = profile.donation.robuxDonatedLifetime,
			donationPurchaseCount = profile.donation.donationPurchaseCount,
			biggestRobuxDonation = profile.donation.biggestRobuxDonation,
		},
	})
end

-- Push pending deltas (if any) to the player. Called after actions and once per
-- income tick. No-op when nothing changed.
function NetworkService.FlushState(userId: number)
	local changes = StateSync.Flush(userId)
	if not changes then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	Remotes.StateUpdate:FireClient(player, changes)
end

--------------------------------------------------------------------------------
-- Inbound: spin request (validated + rate-limited + fully server-decided)
--------------------------------------------------------------------------------

-- Future luck/event/pity modifiers are assembled here per player; all neutral
-- today. Registered RollModifiers hooks (Luck Potions, Events, Gamepasses) get a
-- chance to mutate the table before it's used.
local function buildRollModifiers(userId: number)
	local modifiers = {
		luck = GameConfig.Multipliers.LuckDefault,
		event = GameConfig.Multipliers.EventDefault,
		pity = GameConfig.Multipliers.PityDefault,
	}
	ExpansionHooks.Fire("RollModifiers", userId, modifiers)
	return modifiers
end

local function handleSpinRequest(player: Player)
	local userId = player.UserId
	local runtime = Runtime.Get(userId)
	local profile = Services.ProfileService.Get(userId)

	-- Validation: player must be fully initialized with a loaded profile.
	if not runtime or not profile or not runtime.initialized then
		return -- ignore, don't crash
	end
	-- Reject duplicate requests while a roll is already resolving.
	if runtime.spinActive then
		return
	end
	-- Enforce cooldown (anti-spam; future Auto-Spin reuses this same path).
	local now = os.clock()
	if now - runtime.lastSpinAt < GameConfig.SpinCooldown then
		return
	end

	runtime.spinActive = true
	runtime.lastSpinAt = now

	local success, err = pcall(function()
		-- Server decides the winner. The client never influences this.
		local winner = rng:RollStreamer(StreamerDatabase.All, buildRollModifiers(userId))

		Services.InventoryService.AddStreamer(userId, winner.id)
		profile.stats.totalSpins += 1
		Services.SessionTracker.OnSpin(userId)

		-- Tell the client which streamer to reveal (authoritative id + rarity).
		Remotes.SpinResult:FireClient(player, {
			streamerId = winner.id,
			rarity = winner.rarity_tier,
		})
		-- Ship the resulting state changes (inventory/income/collection/bestPull).
		NetworkService.FlushState(userId)

		-- Seam for Challenges / Quests / Analytics; no-op today.
		ExpansionHooks.Fire("OnSpinCompleted", userId, winner)

		Logger.Info("Spin", string.format("%d rolled %s (%s)", userId, winner.name, winner.rarity_tier))
	end)

	if not success then
		Logger.Error("Spin", string.format("Spin failed for %d: %s", userId, tostring(err)))
	end

	runtime.spinActive = false
end

function NetworkService.Start()
	Remotes.SpinRequest.OnServerEvent:Connect(function(player)
		-- Wrap so a malformed request can never bubble an error up.
		local ok, err = pcall(handleSpinRequest, player)
		if not ok then
			Logger.Error("Network", string.format("SpinRequest handler error: %s", tostring(err)))
		end
	end)

	-- Handshake: the client fires ClientReady once its handlers are connected. If
	-- it's already initialized (its init-time snapshot may have raced ahead of the
	-- client), resend the snapshot so it's never missed.
	Remotes.ClientReady.OnServerEvent:Connect(function(player)
		local runtime = Runtime.Get(player.UserId)
		if runtime and runtime.initialized then
			NetworkService.SendInitialState(player)
		end
	end)
end

return NetworkService
