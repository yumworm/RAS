--!strict
-- HUDController: the top bar (currency + income/sec) and floating "+N" popups.
-- Purely presentational -- it renders whatever StateController holds.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local NumberFormatter = require(ReplicatedStorage.Modules.Shared.NumberFormatter)
local GameConfig = require(ReplicatedStorage.Modules.Configuration.GameConfig)

local player = Players.LocalPlayer

local HUDController = {}

local currencyLabel, incomeLabel, floatingLayer
local lastCurrency = 0

local function build(parent: ScreenGui)
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 56)
	topBar.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	topBar.BorderSizePixel = 0
	topBar.Parent = parent

	currencyLabel = Instance.new("TextLabel")
	currencyLabel.Name = "CurrencyLabel"
	currencyLabel.BackgroundTransparency = 1
	currencyLabel.Position = UDim2.fromOffset(20, 0)
	-- Width is viewport-relative and leaves room for the top-right settings gear so
	-- long amounts never run under it on narrow phones.
	currencyLabel.Size = UDim2.new(1, -84, 0, 34)
	currencyLabel.Font = Enum.Font.GothamBold
	currencyLabel.TextSize = 22
	currencyLabel.TextXAlignment = Enum.TextXAlignment.Left
	currencyLabel.TextTruncate = Enum.TextTruncate.AtEnd
	currencyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	currencyLabel.Text = GameConfig.CurrencyName .. ": 0"
	currencyLabel.Parent = topBar

	incomeLabel = Instance.new("TextLabel")
	incomeLabel.Name = "IncomeLabel"
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.Position = UDim2.fromOffset(20, 32)
	incomeLabel.Size = UDim2.new(1, -84, 0, 20)
	incomeLabel.Font = Enum.Font.Gotham
	incomeLabel.TextSize = 14
	incomeLabel.TextXAlignment = Enum.TextXAlignment.Left
	incomeLabel.TextColor3 = Color3.fromRGB(150, 220, 160)
	incomeLabel.Text = "+0/sec"
	incomeLabel.Parent = topBar

	floatingLayer = Instance.new("Frame")
	floatingLayer.Name = "FloatingLayer"
	floatingLayer.BackgroundTransparency = 1
	floatingLayer.Position = UDim2.fromOffset(20, 0)
	floatingLayer.Size = UDim2.fromOffset(240, 56)
	floatingLayer.ClipsDescendants = false
	floatingLayer.ZIndex = 5
	floatingLayer.Parent = topBar
end

local function spawnFloatingNumber(amount: number)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = Color3.fromRGB(120, 255, 140)
	label.Text = "+" .. NumberFormatter.Format(amount)
	label.Size = UDim2.fromOffset(140, 20)
	label.Position = UDim2.fromOffset(200, 16)
	label.ZIndex = 5
	label.Parent = floatingLayer

	TweenService:Create(
		label,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = label.Position - UDim2.fromOffset(0, 36), TextTransparency = 1 }
	):Play()
	Debris:AddItem(label, 1)
end

local function onState(state, changed)
	if changed.currency then
		local delta = state.currency - lastCurrency
		lastCurrency = state.currency
		currencyLabel.Text = GameConfig.CurrencyName .. ": " .. NumberFormatter.Format(state.currency)
		if delta > 0 then
			spawnFloatingNumber(delta)
		end
	end
	if changed.income then
		incomeLabel.Text = "+" .. NumberFormatter.Format(state.income) .. "/sec"
	end
end

function HUDController.Init(parent: ScreenGui, StateController)
	build(parent)
	StateController.Subscribe(onState)
end

return HUDController
