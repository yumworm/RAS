--!strict
-- SpinController: the central spin button + reel. It only *requests* a spin; the
-- server decides the winner and sends it back via SpinResult. The client's job is
-- purely cosmetic -- cycle a reel, then reveal the server's result with rarity
-- flair (scale pop, glow, particle burst, rainbow for Secret).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Configuration = ReplicatedStorage.Modules.Configuration
local RarityConfig = require(Configuration.RarityConfig)
local StreamerDatabase = require(Configuration.StreamerDatabase)
local GameConfig = require(Configuration.GameConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SpinRequest = Remotes:WaitForChild("SpinRequest")

local player = Players.LocalPlayer

local SpinController = {}
local StateController: any

local reelCard, reelName, reelRarity, glowFrame, spinButton
local spinning = false
local pendingResult = nil
local rainbowConnection = nil

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function build(parent: ScreenGui)
	local center = Instance.new("Frame")
	center.Name = "CenterPanel"
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.new(0.5, -140, 0.5, 0)
	center.Size = UDim2.fromOffset(320, 280)
	center.BackgroundTransparency = 1
	center.Parent = parent

	glowFrame = Instance.new("Frame")
	glowFrame.Name = "Glow"
	glowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	glowFrame.Position = UDim2.new(0.5, 0, 0.4, 0)
	glowFrame.Size = UDim2.fromOffset(340, 220)
	glowFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	glowFrame.BackgroundTransparency = 1
	glowFrame.BorderSizePixel = 0
	glowFrame.ZIndex = 1
	glowFrame.Parent = center
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(0, 24)
	glowCorner.Parent = glowFrame

	reelCard = Instance.new("Frame")
	reelCard.Name = "ReelCard"
	reelCard.AnchorPoint = Vector2.new(0.5, 0.5)
	reelCard.Position = UDim2.new(0.5, 0, 0.4, 0)
	reelCard.Size = UDim2.fromOffset(280, 160)
	reelCard.BackgroundColor3 = RarityConfig.Get("Common").Color
	reelCard.BorderSizePixel = 0
	reelCard.ZIndex = 2
	reelCard.Parent = center
	local reelCorner = Instance.new("UICorner")
	reelCorner.CornerRadius = UDim.new(0, 16)
	reelCorner.Parent = reelCard

	reelName = Instance.new("TextLabel")
	reelName.BackgroundTransparency = 1
	reelName.Size = UDim2.new(1, -20, 0, 40)
	reelName.Position = UDim2.fromOffset(10, 58)
	reelName.Font = Enum.Font.GothamBold
	reelName.TextSize = 26
	reelName.TextColor3 = Color3.fromRGB(255, 255, 255)
	reelName.Text = "Ready to Spin"
	reelName.ZIndex = 3
	reelName.Parent = reelCard

	reelRarity = Instance.new("TextLabel")
	reelRarity.BackgroundTransparency = 1
	reelRarity.Size = UDim2.new(1, -20, 0, 24)
	reelRarity.Position = UDim2.fromOffset(10, 102)
	reelRarity.Font = Enum.Font.Gotham
	reelRarity.TextSize = 16
	reelRarity.TextColor3 = Color3.fromRGB(240, 240, 240)
	reelRarity.Text = ""
	reelRarity.ZIndex = 3
	reelRarity.Parent = reelCard

	spinButton = Instance.new("TextButton")
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
	spinButton.Parent = center
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 12)
	btnCorner.Parent = spinButton
end

--------------------------------------------------------------------------------
-- Reel + reveal
--------------------------------------------------------------------------------

local function stopRainbow()
	if rainbowConnection then
		rainbowConnection:Disconnect()
		rainbowConnection = nil
	end
end

local function setReel(streamer)
	local rarity = RarityConfig.Get(streamer.rarity_tier)
	reelName.Text = streamer.name
	reelRarity.Text = rarity.DisplayName
	stopRainbow()
	reelCard.BackgroundColor3 = rarity.Color
end

local function particleBurst(color: Color3, rainbow: boolean)
	local count = 14
	for i = 1, count do
		local p = Instance.new("Frame")
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = UDim2.fromScale(0.5, 0.5)
		p.Size = UDim2.fromOffset(8, 8)
		p.BackgroundColor3 = rainbow and Color3.fromHSV(i / count, 1, 1) or color
		p.BorderSizePixel = 0
		p.ZIndex = 4
		p.Parent = reelCard
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = p

		local angle = (i / count) * math.pi * 2
		local distance = 90 + math.random(0, 30)
		TweenService
			:Create(p, TweenInfo.new(0.5 + math.random() * 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, math.cos(angle) * distance, 0.5, math.sin(angle) * distance),
				BackgroundTransparency = 1,
			})
			:Play()
		Debris:AddItem(p, 1)
	end
end

local function revealFlourish(streamer)
	local rarity = RarityConfig.Get(streamer.rarity_tier)

	if rarity.IsRainbow then
		rainbowConnection = RunService.Heartbeat:Connect(function()
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

	glowFrame.BackgroundColor3 = rarity.Color
	glowFrame.BackgroundTransparency = 0.35
	TweenService:Create(
		glowFrame,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()

	particleBurst(rarity.Color, rarity.IsRainbow == true)
end

local function runReel(duration: number)
	local startTime = os.clock()
	while os.clock() - startTime < duration do
		local streamer = StreamerDatabase.All[math.random(1, #StreamerDatabase.All)]
		setReel(streamer)
		local ratio = (os.clock() - startTime) / duration
		task.wait(0.04 + ratio * 0.22) -- fast -> slow
	end
end

--------------------------------------------------------------------------------
-- Flow
--------------------------------------------------------------------------------

-- Called by the bootstrap when SpinResult arrives.
function SpinController.OnResult(payload)
	pendingResult = payload
end

local function onClick()
	if spinning or not StateController.ready then
		return
	end
	spinning = true
	spinButton.Active = false
	spinButton.AutoButtonColor = false
	spinButton.Text = "..."

	pendingResult = nil
	SpinRequest:FireServer()

	runReel(GameConfig.SpinAnimationDuration)

	-- Wait for the server's authoritative result (bounded).
	local waited = 0
	while not pendingResult and waited < 5 do
		task.wait(0.05)
		waited += 0.05
	end

	local result = pendingResult
	pendingResult = nil
	if result then
		local streamer = StreamerDatabase.Get(result.streamerId)
		if streamer then
			setReel(streamer)
			revealFlourish(streamer)
		end
	end

	spinButton.Active = true
	spinButton.AutoButtonColor = true
	spinButton.Text = "SPIN"
	spinning = false
end

function SpinController.Init(parent: ScreenGui, stateController)
	StateController = stateController
	build(parent)
	spinButton.MouseButton1Click:Connect(onClick)
end

return SpinController
