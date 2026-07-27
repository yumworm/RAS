--!strict
-- PlayerManager: orchestrates the player lifecycle and the two background loops
-- (income + autosave). It enforces the strict initialization order so a player
-- can never spin before their data is ready, and guarantees a clean, leak-free
-- teardown on leave / shutdown.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Modules.Configuration.GameConfig)

local Server = script.Parent.Parent
local Runtime = require(Server.Core.Runtime)
local StateSync = require(Server.Core.StateSync)
local Logger = require(Server.Utilities.Logger)

local PlayerManager = {}
local Services: any

function PlayerManager.Init(services)
	Services = services
end

--------------------------------------------------------------------------------
-- Join: strict initialization order
--------------------------------------------------------------------------------
-- 1 create runtime -> 2 load+validate profile -> 3 compute income ->
-- 4 start session -> 5 mark initialized (gameplay enabled) -> 6 send initial state
local function onPlayerAdded(player: Player)
	local userId = player.UserId
	Logger.Info("Player", string.format("%s (%d) joined", player.Name, userId))

	local runtime = Runtime.Create(userId)

	local ok, err = pcall(function()
		local _, loadOk = Services.ProfileService.LoadAsync(userId)
		runtime.loadFailed = not loadOk

		Services.IncomeService.Recompute(userId) -- initial income from saved inventory
		Services.SessionTracker.Start(userId)

		runtime.initialized = true -- gameplay may begin only now
		Services.NetworkService.SendInitialState(player)

		-- Developer-only retention telemetry (log-only; also detects a zero-spin join).
		if Services.AnalyticsMonitorSystem then
			Services.AnalyticsMonitorSystem.LogSessionStarted(userId)
		end
	end)

	if not ok then
		-- Initialization must never crash the server. Leave the player
		-- un-initialized (spins stay rejected) and log it.
		Logger.Error("Player", string.format("Init failed for %d: %s", userId, tostring(err)))
	end
end

--------------------------------------------------------------------------------
-- Leave: save, then tear everything down
--------------------------------------------------------------------------------
local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	Logger.Info("Player", string.format("%s (%d) leaving", player.Name, userId))

	Services.SessionTracker.End(userId)
	-- Phase 6: server-stamp the logout time BEFORE the save so the next session can
	-- compute time away for the welcome-back summary. Client can never reach this.
	if Services.ReturnSummarySystem then
		Services.ReturnSummarySystem.StampLogout(userId)
	end
	Services.SaveManager.SaveNow(userId) -- blocking save + retry before we drop data

	Runtime.Destroy(userId) -- disconnects tracked connections
	Services.ProfileService.Unload(userId)
	Services.SaveManager.Forget(userId)
	StateSync.Clear(userId)
end

--------------------------------------------------------------------------------
-- Shutdown: prioritize data safety, wait for every save
--------------------------------------------------------------------------------
local function onClose()
	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end
	Logger.Warn("Shutdown", string.format("Server closing, saving %d player(s)", #players))

	local remaining = #players
	for _, player in ipairs(players) do
		task.spawn(function()
			pcall(function()
				-- Stamp logout on shutdown too, so a server close is a real "logout" for
				-- the returning-player summary (still zero economy writes).
				if Services.ReturnSummarySystem then
					Services.ReturnSummarySystem.StampLogout(player.UserId)
				end
				Services.SaveManager.SaveNow(player.UserId)
			end)
			remaining -= 1
		end)
	end
	while remaining > 0 do
		task.wait(0.05)
	end
	Logger.Warn("Shutdown", "All saves complete")
end

--------------------------------------------------------------------------------
-- Background loops: exactly one income accumulator + one autosave loop
--------------------------------------------------------------------------------
local function startIncomeLoop()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < GameConfig.IncomeTickInterval then
			return
		end
		local step = accumulator
		accumulator = 0

		for userId, runtime in pairs(Runtime.GetAll()) do
			if runtime.initialized then
				if runtime.incomePerSecond > 0 then
					-- All currency changes route through EconomyService.
					Services.EconomyService.AddCurrency(userId, runtime.incomePerSecond * step, "passive")
				end
				Services.SessionTracker.Tick(userId, step)
				-- Push only what changed (usually just currency) to the client.
				Services.NetworkService.FlushState(userId)
			end
		end
	end)
end

function PlayerManager.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	game:BindToClose(onClose)

	-- Handle players who joined before this script ran (Studio / hot reload).
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	startIncomeLoop()
	Services.SaveManager.StartAutosaveLoop()
end

return PlayerManager
