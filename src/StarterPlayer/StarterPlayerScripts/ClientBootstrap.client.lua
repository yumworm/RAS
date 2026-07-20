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
end)

-- Build the HUD.
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.Parent = playerGui

HUDController.Init(screenGui, StateController)
InventoryController.Init(screenGui, StateController)
SpinController.Init(screenGui, StateController)

-- Tell the server we're ready to receive state. This closes the race where the
-- server's init-time snapshot could fire before our handlers were connected.
Remotes.ClientReady:FireServer()
