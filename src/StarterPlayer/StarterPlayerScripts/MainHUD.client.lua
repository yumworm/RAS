-- Phase 1 client: builds the Main HUD (spin button + reel, currency bar, side inventory)
-- entirely in code, drives the cosmetic spin animation, and renders server-authoritative results.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Modules = ReplicatedStorage.Modules
local StreamerData = require(Modules.StreamerData)
local RarityConfig = require(Modules.RarityConfig)
local GameConfig = require(Modules.GameConfig)
local NumberFormatter = require(Modules.NumberFormatter)

local Remotes = ReplicatedStorage.Remotes
local SpinRequest = Remotes.SpinRequest
local SpinResult = Remotes.SpinResult

local player = Players.LocalPlayer

--------------------------------------------------------------------------------
-- UI construction
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Top bar: currency + income/sec
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 56)
topBar.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
topBar.BorderSizePixel = 0
topBar.Parent = screenGui

local currencyLabel = Instance.new("TextLabel")
currencyLabel.Name = "CurrencyLabel"
currencyLabel.BackgroundTransparency = 1
currencyLabel.Position = UDim2.fromOffset(20, 0)
currencyLabel.Size = UDim2.fromOffset(360, 56)
currencyLabel.Font = Enum.Font.GothamBold
currencyLabel.TextSize = 22
currencyLabel.TextXAlignment = Enum.TextXAlignment.Left
currencyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
currencyLabel.Text = GameConfig.CurrencyName .. ": 0"
currencyLabel.Parent = topBar

local incomeLabel = Instance.new("TextLabel")
incomeLabel.Name = "IncomeLabel"
incomeLabel.BackgroundTransparency = 1
incomeLabel.Position = UDim2.fromOffset(20, 30)
incomeLabel.Size = UDim2.fromOffset(360, 20)
incomeLabel.Font = Enum.Font.Gotham
incomeLabel.TextSize = 14
incomeLabel.TextXAlignment = Enum.TextXAlignment.Left
incomeLabel.TextColor3 = Color3.fromRGB(150, 220, 160)
incomeLabel.Text = "+0/sec"
incomeLabel.Parent = topBar

local floatingLayer = Instance.new("Frame")
floatingLayer.Name = "FloatingLayer"
floatingLayer.BackgroundTransparency = 1
floatingLayer.Position = UDim2.fromOffset(20, 0)
floatingLayer.Size = UDim2.fromOffset(200, 56)
floatingLayer.ClipsDescendants = false
floatingLayer.ZIndex = 5
floatingLayer.Parent = topBar

-- Center panel: reel card + spin button
local centerPanel = Instance.new("Frame")
centerPanel.Name = "CenterPanel"
centerPanel.AnchorPoint = Vector2.new(0.5, 0.5)
centerPanel.Position = UDim2.new(0.5, -140, 0.5, 0)
centerPanel.Size = UDim2.fromOffset(320, 280)
centerPanel.BackgroundTransparency = 1
centerPanel.Parent = screenGui

local glowFrame = Instance.new("Frame")
glowFrame.Name = "Glow"
glowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
glowFrame.Position = UDim2.new(0.5, 0, 0.4, 0)
glowFrame.Size = UDim2.fromOffset(340, 220)
glowFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
glowFrame.BackgroundTransparency = 1
glowFrame.BorderSizePixel = 0
glowFrame.ZIndex = 1
glowFrame.Parent = centerPanel

local glowCorner = Instance.new("UICorner")
glowCorner.CornerRadius = UDim.new(0, 24)
glowCorner.Parent = glowFrame

local reelCard = Instance.new("Frame")
reelCard.Name = "ReelCard"
reelCard.AnchorPoint = Vector2.new(0.5, 0.5)
reelCard.Position = UDim2.new(0.5, 0, 0.4, 0)
reelCard.Size = UDim2.fromOffset(280, 160)
reelCard.BackgroundColor3 = RarityConfig.Tiers.Common.Color
reelCard.BorderSizePixel = 0
reelCard.ZIndex = 2
reelCard.Parent = centerPanel

local reelCorner = Instance.new("UICorner")
reelCorner.CornerRadius = UDim.new(0, 16)
reelCorner.Parent = reelCard

local reelNameLabel = Instance.new("TextLabel")
reelNameLabel.Name = "NameLabel"
reelNameLabel.BackgroundTransparency = 1
reelNameLabel.Size = UDim2.new(1, -20, 0, 40)
reelNameLabel.Position = UDim2.fromOffset(10, 60)
reelNameLabel.Font = Enum.Font.GothamBold
reelNameLabel.TextSize = 26
reelNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
reelNameLabel.TextScaled = false
reelNameLabel.Text = "..."
reelNameLabel.ZIndex = 3
reelNameLabel.Parent = reelCard

local reelRarityLabel = Instance.new("TextLabel")
reelRarityLabel.Name = "RarityLabel"
reelRarityLabel.BackgroundTransparency = 1
reelRarityLabel.Size = UDim2.new(1, -20, 0, 24)
reelRarityLabel.Position = UDim2.fromOffset(10, 104)
reelRarityLabel.Font = Enum.Font.Gotham
reelRarityLabel.TextSize = 16
reelRarityLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
reelRarityLabel.Text = ""
reelRarityLabel.ZIndex = 3
reelRarityLabel.Parent = reelCard

local spinButton = Instance.new("TextButton")
spinButton.Name = "SpinButton"
spinButton.AnchorPoint = Vector2.new(0.5, 0)
spinButton.Position = UDim2.new(0.5, 0, 1, -60)
spinButton.Size = UDim2.fromOffset(200, 52)
spinButton.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
spinButton.Font = Enum.Font.GothamBold
spinButton.TextSize = 22
spinButton.TextColor3 = Color3.fromRGB(255, 255, 255)
spinButton.Text = "SPIN"
spinButton.ZIndex = 2
spinButton.Parent = centerPanel

local spinButtonCorner = Instance.new("UICorner")
spinButtonCorner.CornerRadius = UDim.new(0, 12)
spinButtonCorner.Parent = spinButton

-- Sidebar: owned streamer inventory
local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.AnchorPoint = Vector2.new(1, 0.5)
sidebar.Position = UDim2.new(1, -16, 0.5, 0)
sidebar.Size = UDim2.fromOffset(280, 460)
sidebar.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
sidebar.BorderSizePixel = 0
sidebar.Parent = screenGui

local sidebarCorner = Instance.new("UICorner")
sidebarCorner.CornerRadius = UDim.new(0, 12)
sidebarCorner.Parent = sidebar

local sidebarTitle = Instance.new("TextLabel")
sidebarTitle.Name = "Title"
sidebarTitle.BackgroundTransparency = 1
sidebarTitle.Size = UDim2.new(1, -20, 0, 36)
sidebarTitle.Position = UDim2.fromOffset(10, 6)
sidebarTitle.Font = Enum.Font.GothamBold
sidebarTitle.TextSize = 18
sidebarTitle.TextXAlignment = Enum.TextXAlignment.Left
sidebarTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
sidebarTitle.Text = "Your Streamers"
sidebarTitle.Parent = sidebar

local inventoryList = Instance.new("ScrollingFrame")
inventoryList.Name = "InventoryList"
inventoryList.Position = UDim2.fromOffset(10, 46)
inventoryList.Size = UDim2.new(1, -20, 1, -56)
inventoryList.BackgroundTransparency = 1
inventoryList.BorderSizePixel = 0
inventoryList.ScrollBarThickness = 6
inventoryList.CanvasSize = UDim2.new(0, 0, 0, 0)
inventoryList.AutomaticCanvasSize = Enum.AutomaticSize.Y
inventoryList.Parent = sidebar

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = inventoryList

--------------------------------------------------------------------------------
-- Currency + floating numbers
--------------------------------------------------------------------------------

local function updateCurrencyLabel(value)
	currencyLabel.Text = GameConfig.CurrencyName .. ": " .. NumberFormatter.Format(value)
end

local function spawnFloatingNumber(amount)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = Color3.fromRGB(120, 255, 140)
	label.Text = "+" .. NumberFormatter.Format(amount)
	label.AnchorPoint = Vector2.new(0, 0)
	label.Size = UDim2.fromOffset(120, 20)
	label.Position = UDim2.fromOffset(180, 16)
	label.ZIndex = 5
	label.Parent = floatingLayer

	local tween = TweenService:Create(
		label,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = label.Position - UDim2.fromOffset(0, 36), TextTransparency = 1 }
	)
	tween:Play()
	Debris:AddItem(label, 1)
end

local leaderstats = player:WaitForChild("leaderstats")
local cashValue = leaderstats:WaitForChild(GameConfig.CurrencyName)

local lastCash = cashValue.Value
updateCurrencyLabel(lastCash)

cashValue.Changed:Connect(function(newValue)
	local delta = newValue - lastCash
	lastCash = newValue
	updateCurrencyLabel(newValue)
	if delta > 0 then
		spawnFloatingNumber(delta)
	end
end)

local function updateIncomeLabel(incomePerSecond)
	incomeLabel.Text = "+" .. NumberFormatter.Format(incomePerSecond) .. "/sec"
end

--------------------------------------------------------------------------------
-- Sidebar inventory rendering
--------------------------------------------------------------------------------

local inventoryRows = {}

local function upsertInventoryRow(streamerId, count)
	local streamer = StreamerData.GetById(streamerId)
	if not streamer then
		return
	end
	local tier = RarityConfig.Tiers[streamer.rarity_tier]

	local row = inventoryRows[streamerId]
	if not row then
		row = Instance.new("Frame")
		row.Name = "Row_" .. streamerId
		row.Size = UDim2.new(1, 0, 0, 48)
		row.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
		row.BorderSizePixel = 0
		row.LayoutOrder = -streamer.popularity_score
		row.Parent = inventoryList

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 8)
		rowCorner.Parent = row

		local stroke = Instance.new("UIStroke")
		stroke.Color = tier.Color
		stroke.Thickness = 2
		stroke.Parent = row

		local icon = Instance.new("Frame")
		icon.Name = "Icon"
		icon.Size = UDim2.fromOffset(36, 36)
		icon.Position = UDim2.fromOffset(6, 6)
		icon.BackgroundColor3 = tier.Color
		icon.BorderSizePixel = 0
		icon.Parent = row

		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(1, 0)
		iconCorner.Parent = icon

		local initial = Instance.new("TextLabel")
		initial.Name = "Initial"
		initial.BackgroundTransparency = 1
		initial.Size = UDim2.fromScale(1, 1)
		initial.Font = Enum.Font.GothamBold
		initial.TextSize = 18
		initial.TextColor3 = Color3.fromRGB(255, 255, 255)
		initial.Text = string.sub(streamer.name, 1, 1)
		initial.Parent = icon

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.fromOffset(50, 4)
		nameLabel.Size = UDim2.new(1, -100, 0, 20)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 14
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = tier.Color
		nameLabel.Text = streamer.name
		nameLabel.Parent = row

		local incomeRowLabel = Instance.new("TextLabel")
		incomeRowLabel.Name = "IncomeLabel"
		incomeRowLabel.BackgroundTransparency = 1
		incomeRowLabel.Position = UDim2.fromOffset(50, 24)
		incomeRowLabel.Size = UDim2.new(1, -100, 0, 18)
		incomeRowLabel.Font = Enum.Font.Gotham
		incomeRowLabel.TextSize = 12
		incomeRowLabel.TextXAlignment = Enum.TextXAlignment.Left
		incomeRowLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		incomeRowLabel.Parent = row

		local countLabel = Instance.new("TextLabel")
		countLabel.Name = "CountLabel"
		countLabel.BackgroundTransparency = 1
		countLabel.AnchorPoint = Vector2.new(1, 0)
		countLabel.Position = UDim2.new(1, -6, 0, 0)
		countLabel.Size = UDim2.fromOffset(40, 48)
		countLabel.Font = Enum.Font.GothamBold
		countLabel.TextSize = 14
		countLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		countLabel.Parent = row

		inventoryRows[streamerId] = row
	end

	local perCopyIncome = streamer.base_income * tier.IncomeMultiplier
	row.IncomeLabel.Text = NumberFormatter.Format(perCopyIncome * count) .. "/sec"
	row.CountLabel.Text = "x" .. count
end

local function renderInventory(ownedArray)
	for _, entry in ipairs(ownedArray) do
		upsertInventoryRow(entry.id, entry.count)
	end
end

--------------------------------------------------------------------------------
-- Spin animation
--------------------------------------------------------------------------------

local rainbowConnection = nil

local function stopRainbow()
	if rainbowConnection then
		rainbowConnection:Disconnect()
		rainbowConnection = nil
	end
end

local function setReelCard(streamer, tierName)
	local tier = RarityConfig.Tiers[tierName]
	reelNameLabel.Text = streamer.name
	reelRarityLabel.Text = tierName
	stopRainbow()
	reelCard.BackgroundColor3 = tier.Color
end

local function spawnParticleBurst(color, rainbow)
	local particleCount = 14
	for i = 1, particleCount do
		local particle = Instance.new("Frame")
		particle.AnchorPoint = Vector2.new(0.5, 0.5)
		particle.Position = UDim2.fromScale(0.5, 0.5)
		particle.Size = UDim2.fromOffset(8, 8)
		particle.BackgroundColor3 = rainbow and Color3.fromHSV(i / particleCount, 1, 1) or color
		particle.BorderSizePixel = 0
		particle.ZIndex = 4
		particle.Parent = reelCard

		local particleCorner = Instance.new("UICorner")
		particleCorner.CornerRadius = UDim.new(1, 0)
		particleCorner.Parent = particle

		local angle = (i / particleCount) * math.pi * 2
		local distance = 90 + math.random(0, 30)
		local targetPos = UDim2.new(0.5, math.cos(angle) * distance, 0.5, math.sin(angle) * distance)

		local tween = TweenService:Create(
			particle,
			TweenInfo.new(0.5 + math.random() * 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = targetPos, BackgroundTransparency = 1 }
		)
		tween:Play()
		Debris:AddItem(particle, 1)
	end
end

local function playLandingFlourish(tierName)
	local tier = RarityConfig.Tiers[tierName]

	if tier.IsRainbow then
		rainbowConnection = game:GetService("RunService").Heartbeat:Connect(function()
			reelCard.BackgroundColor3 = Color3.fromHSV((os.clock() * 0.5) % 1, 0.85, 1)
		end)
		task.delay(1.6, stopRainbow)
	end

	local pop = TweenService:Create(
		reelCard,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(310, 178) }
	)
	pop:Play()
	pop.Completed:Wait()
	TweenService:Create(
		reelCard,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(280, 160) }
	):Play()

	glowFrame.BackgroundColor3 = tier.Color
	glowFrame.BackgroundTransparency = 0.35
	TweenService:Create(
		glowFrame,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()

	spawnParticleBurst(tier.Color, tier.IsRainbow)
end

local function pickRandomDisplayStreamer()
	return StreamerData.Streamers[math.random(1, #StreamerData.Streamers)]
end

local function runCosmeticReel(minDuration)
	local startTime = os.clock()
	while os.clock() - startTime < minDuration do
		local streamer = pickRandomDisplayStreamer()
		setReelCard(streamer, streamer.rarity_tier)
		local elapsedRatio = (os.clock() - startTime) / minDuration
		task.wait(0.04 + elapsedRatio * 0.22) -- ramps from fast to slow
	end
end

--------------------------------------------------------------------------------
-- Spin flow
--------------------------------------------------------------------------------

local spinning = false
local pendingResult = nil

SpinResult.OnClientEvent:Connect(function(payload)
	pendingResult = payload
end)

spinButton.MouseButton1Click:Connect(function()
	if spinning then
		return
	end
	spinning = true
	spinButton.Active = false
	spinButton.AutoButtonColor = false
	spinButton.Text = "..."

	pendingResult = nil
	SpinRequest:FireServer()

	runCosmeticReel(GameConfig.SpinAnimationDuration)

	local waited = 0
	while not pendingResult and waited < 5 do
		task.wait(0.05)
		waited += 0.05
	end

	local result = pendingResult
	pendingResult = nil

	if result then
		local winner = StreamerData.GetById(result.wonId)
		setReelCard(winner, winner.rarity_tier)
		playLandingFlourish(winner.rarity_tier)
		renderInventory(result.owned)
		updateIncomeLabel(result.incomePerSecond)
	end

	spinButton.Active = true
	spinButton.AutoButtonColor = true
	spinButton.Text = "SPIN"
	spinning = false
end)
