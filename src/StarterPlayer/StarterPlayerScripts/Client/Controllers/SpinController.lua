--!strict
-- SpinController: the central spin button + reel. It only *requests* a spin; the
-- server decides the winner and sends it back via SpinResult. The client's job is
-- purely cosmetic: cycle a reel (shared pre-result anticipation), then hand the
-- server's result to the RevealController, which routes it to the correct tier.
--
-- Phase 4 split: SpinController no longer decides how the winner looks. The reel
-- is anticipation only; the winning card's presentation is owned by the Standard
-- (instant) or Flagship (cinematic) handler, chosen from the server's
-- PresentationType. This module never animates the winning card itself.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = ReplicatedStorage.Modules.Configuration
local RarityConfig = require(Configuration.RarityConfig)
local StreamerDatabase = require(Configuration.StreamerDatabase)
local GameConfig = require(Configuration.GameConfig)

local RevealController = require(script.Parent.RevealController)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SpinRequest = Remotes:WaitForChild("SpinRequest")

local player = Players.LocalPlayer

local SpinController = {}
local StateController: any

local reelCard, reelName, reelRarity, glowFrame, spinButton
local spinning = false
local pendingResult = nil
local rainbowConnection = nil

local DEFAULT_CARD_SIZE = UDim2.fromOffset(280, 160)

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
	reelCard.Size = DEFAULT_CARD_SIZE
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
	-- Keep the primary action a comfortable touch target on every device.
	local btnSize = Instance.new("UISizeConstraint")
	btnSize.MinSize = Vector2.new(160, 48)
	btnSize.Parent = spinButton
end

--------------------------------------------------------------------------------
-- Reveal surface (shared by the Standard / Flagship handlers via RevealController)
--------------------------------------------------------------------------------

local function stopRainbow()
	if rainbowConnection then
		rainbowConnection:Disconnect()
		rainbowConnection = nil
	end
end

local function setInputLocked(locked: boolean)
	spinButton.Active = not locked
	spinButton.AutoButtonColor = not locked
end

-- Reset the winning card to its resting size. There are no persistent winner
-- tweens on this path (the reel uses timed color swaps, not tweens), so this is a
-- cheap safety snap the Standard handler calls before painting the result.
local function cancelWinnerTweens()
	reelCard.Size = DEFAULT_CARD_SIZE
end

local function buildView()
	return {
		card = reelCard,
		name = reelName,
		rarity = reelRarity,
		glow = glowFrame,
		defaultCardSize = DEFAULT_CARD_SIZE,
		setInputLocked = setInputLocked,
		stopRainbow = stopRainbow,
		cancelWinnerTweens = cancelWinnerTweens,
	}
end

--------------------------------------------------------------------------------
-- Reel (pre-result anticipation only)
--------------------------------------------------------------------------------

local function setReel(streamer)
	local rarity = RarityConfig.Get(streamer.rarity_tier)
	reelName.Text = streamer.name
	reelRarity.Text = rarity.DisplayName
	stopRainbow()
	reelCard.BackgroundColor3 = rarity.Color
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
	setInputLocked(true)
	spinButton.Text = "..."

	pendingResult = nil
	SpinRequest:FireServer()

	-- Shared anticipation cycle (Phase 1). This runs BEFORE the result branch; the
	-- winner's own presentation is decided by tier, not here.
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
		-- Route by server-provided PresentationType. Standard snaps static;
		-- Flagship takes over cinematically (and manages its own input lock).
		RevealController.Reveal(result)
	end

	setInputLocked(false)
	spinButton.Text = "SPIN"
	spinning = false
end

-- Exposed so the FTUE controller can attach its first-spin pulse to the real
-- button instance (rather than searching the GUI tree for it).
function SpinController.GetSpinButton(): TextButton
	return spinButton
end

function SpinController.Init(parent: ScreenGui, stateController)
	StateController = stateController
	build(parent)
	RevealController.Init(buildView())
	spinButton.MouseButton1Click:Connect(onClick)
end

return SpinController
