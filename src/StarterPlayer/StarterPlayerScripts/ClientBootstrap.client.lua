-- ClientBootstrap: the single client entry point. Connects the remote handlers
-- FIRST (before any server snapshot can arrive), then builds the HUD. All state
-- flows server -> StateController -> UI controllers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Client = script.Parent.Client
local StateController = require(Client.Controllers.StateController)
local SpinController = require(Client.Controllers.SpinController)
local DonationController = require(Client.Controllers.DonationController)
local DonationLeaderboardController = require(Client.Controllers.DonationLeaderboardController)
local AudioController = require(Client.Controllers.AudioController)
local SettingsController = require(Client.Controllers.SettingsController)
local FTUEController = require(Client.Controllers.FTUEController)
-- Phase 6 retention layer.
local DonationFeedController = require(Client.Controllers.DonationFeedController)
local ProfileCardController = require(Client.Controllers.ProfileCardController)
local ReturnSummaryController = require(Client.Controllers.ReturnSummaryController)
local StatsPanelController = require(Client.Controllers.StatsPanelController)
local HUDController = require(Client.UI.HUDController)
local InventoryController = require(Client.UI.InventoryController)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Connect inbound remotes immediately so we never miss the initial snapshot.
Remotes.InitialState.OnClientEvent:Connect(function(payload)
	StateController.ApplyInitial(payload)
end)
Remotes.StateUpdate.OnClientEvent:Connect(function(payload)
	StateController.ApplyUpdate(payload)
end)
Remotes.SpinResult.OnClientEvent:Connect(function(payload)
	SpinController.OnResult(payload)
	-- A server-confirmed spin also ends the FTUE first-spin pulse.
	FTUEController.OnSpinResult(payload)
end)

-- Donation remotes.
Remotes.OpenDonationPanel.OnClientEvent:Connect(function()
	DonationController.Open()
end)
Remotes.DonationPromptResult.OnClientEvent:Connect(function(payload)
	DonationController.OnPromptResult(payload)
end)
Remotes.DonationNotification.OnClientEvent:Connect(function(payload)
	DonationController.OnNotification(payload)
end)
Remotes.GlobalDonorLeaderboardUpdated.OnClientEvent:Connect(function(payload)
	DonationLeaderboardController.ApplySnapshot(payload)
end)

-- Phase 6 retention remotes.
Remotes.ProfileCardResult.OnClientEvent:Connect(function(payload)
	ProfileCardController.OnResult(payload)
end)
Remotes.DonationFeedPush.OnClientEvent:Connect(function(event)
	DonationFeedController.OnPush(event)
end)
-- Optional celebratory particle at the stand (safe no-op if the stand is absent).
Remotes.DonationStandEffect.OnClientEvent:Connect(function()
	local area = workspace:FindFirstChild("DonationArea")
	local stand = area and area:FindFirstChild("GlobalDonationStand")
	local anchor = stand and stand:FindFirstChild("EffectAnchor", true)
	if not anchor then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(6, 10)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Color = ColorSequence.new(Color3.fromRGB(120, 255, 140))
	emitter.Parent = anchor
	emitter:Emit(24)
	task.delay(1.5, function()
		emitter:Destroy()
	end)
end)

-- Start the audio bus before anything can play a sound, so early SFX / BGM route
-- through it and honour the Master/Music/SFX settings once they arrive.
AudioController.Init()

-- Build the HUD.
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.Parent = playerGui

HUDController.Init(screenGui, StateController)
InventoryController.Init(screenGui, StateController)
SpinController.Init(screenGui, StateController)
DonationLeaderboardController.Init(screenGui)
DonationController.Init(screenGui, StateController, DonationLeaderboardController)
SettingsController.Init(screenGui, StateController)
FTUEController.Init(screenGui, StateController, SpinController.GetSpinButton())

-- Phase 6 retention controllers.
DonationFeedController.Init(screenGui, StateController)
ProfileCardController.Init(screenGui, StateController)
ReturnSummaryController.Init(screenGui, StateController)
StatsPanelController.Init(screenGui, StateController)
-- Tapping a Top 100 leaderboard row opens that player's profile card.
DonationLeaderboardController.SetRowClickHandler(function(userId)
	ProfileCardController.OpenForUser(userId)
end)

-- Tell the server we're ready to receive state. This closes the race where the
-- server's init-time snapshot could fire before our handlers were connected.
Remotes.ClientReady:FireServer()
