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
local GameSettingsConfig = require(Configuration.GameSettingsConfig)
local StreamerDatabase = require(Configuration.StreamerDatabase)
local PresentationConfig = require(Configuration.PresentationConfig)

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

-- Gacha gate. Set by Bootstrap from startup validation: when content is unsafe
-- (e.g. roster over cap) spins are refused rather than rolled. Defaults to true
-- so a caller that never sets it still works.
local spinEnabled = true
-- One-time guard so a DB presentation_type mismatch logs once, not per spin.
local loggedPresentationMismatch = false

function NetworkService.Init(services)
	Services = services
end

-- Enable or disable accepting spin requests. Called once at boot.
function NetworkService.SetSpinEnabled(enabled: boolean)
	spinEnabled = enabled ~= false
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

-- Resolve the authoritative PresentationType for a winner. The DB value is the
-- source of truth, but we re-derive from rarity as a safety net so a hand-edited
-- mismatch can never send the client down the wrong reveal path. Logs once.
local function resolvePresentationType(winner): string
	local derived = PresentationConfig.GetPresentationType(winner.rarity_tier)
	if winner.presentation_type ~= derived then
		if not loggedPresentationMismatch then
			loggedPresentationMismatch = true
			Logger.Warn(
				"Presentation",
				string.format(
					"%s presentation_type %s != rarity-derived %s; using derived",
					tostring(winner.name),
					tostring(winner.presentation_type),
					derived
				)
			)
		end
		return derived
	end
	return derived
end

-- Flagship asset subset echoed to the client (read-only display instructions).
-- Nil for Standard, which uses the shared rarity template + chime only.
local function buildFlagshipAssets(winner, presentationType: string)
	if presentationType ~= "Flagship" then
		return nil
	end
	local pres = winner.presentation or {}
	return {
		RevealAnimId = pres.reveal_animation_id,
		RevealSoundId = pres.reveal_sound,
		ParticlePreset = PresentationConfig.ResolveParticlePreset(pres.particle_preset),
		CustomBannerId = pres.banner_asset,
	}
end

local function handleSpinRequest(player: Player)
	local userId = player.UserId
	local runtime = Runtime.Get(userId)
	local profile = Services.ProfileService.Get(userId)

	-- Refuse to roll when the gacha is gated off by failed startup validation.
	if not spinEnabled then
		return
	end
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

		local entry, isNew = Services.InventoryService.AddStreamer(userId, winner.id)
		profile.stats.totalSpins += 1
		Services.SessionTracker.OnSpin(userId)

		-- PresentationType (and, for Flagship, the asset refs) are decided here on
		-- the server. The client only routes visuals from them; it can never pick
		-- its own tier or force a Flagship reveal for a Standard pull.
		local presentationType = resolvePresentationType(winner)

		-- Tell the client which streamer to reveal (authoritative id + rarity +
		-- presentation instructions). Inventory/income truth still flows via state
		-- sync below; these fields are display-only.
		Remotes.SpinResult:FireClient(player, {
			streamerId = winner.id,
			rarity = winner.rarity_tier,
			presentationType = presentationType,
			isNew = isNew == true,
			duplicateCount = entry and entry.amount or 1,
			assets = buildFlagshipAssets(winner, presentationType),
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

--------------------------------------------------------------------------------
-- Inbound: settings update (preferences only, validated + rate-limited)
--------------------------------------------------------------------------------

-- The client may only change its own preference booleans. Every key is checked
-- against GameSettingsConfig.MutableSettingKeys and every value must be the exact
-- type declared there, so currency, inventory, spins or donor totals can never be
-- smuggled through this remote. Unknown keys and wrong types are ignored silently.
local function handleSettingsUpdate(player: Player, payload: any)
	local userId = player.UserId
	local runtime = Runtime.Get(userId)
	local profile = Services.ProfileService.Get(userId)
	if not runtime or not profile or not runtime.initialized then
		return
	end
	if type(payload) ~= "table" then
		return
	end

	-- Rate limit: drop bursts so a spammer can't hammer saves.
	local now = os.clock()
	if now - (runtime.lastSettingsAt or 0) < GameSettingsConfig.SettingsUpdateRateLimitSec then
		return
	end

	local applied = false
	for key, expectedType in pairs(GameSettingsConfig.MutableSettingKeys) do
		local value = payload[key]
		if value ~= nil and typeof(value) == expectedType then
			if profile.settings[key] ~= value then
				profile.settings[key] = value
				applied = true
			end
		end
	end

	if not applied then
		return -- nothing valid changed; don't touch the rate-limit clock or save
	end

	runtime.lastSettingsAt = now

	-- Echo the authoritative settings back as a normal state delta and persist.
	StateSync.Mark(userId, "settings", profile.settings)
	NetworkService.FlushState(userId)
	Services.SaveManager.RequestSave(userId)
end

function NetworkService.Start()
	Remotes.RequestUpdateSettings.OnServerEvent:Connect(function(player, payload)
		local ok, err = pcall(handleSettingsUpdate, player, payload)
		if not ok then
			Logger.Error("Network", string.format("Settings handler error: %s", tostring(err)))
		end
	end)

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
