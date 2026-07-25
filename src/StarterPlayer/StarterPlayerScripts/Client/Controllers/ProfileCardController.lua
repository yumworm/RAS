--!strict
-- ProfileCardController: the top-bar Profile button and the read-only profile card.
-- It renders whatever server-authored ProfileCardResult arrives; it never invents a
-- stat. Own card and in-server other cards are full; an offline leaderboard target
-- comes back as a minimal public donor card (name, Robux donated, rank).
--
-- Opened from: the Profile button (own card) and a Top 100 leaderboard row click
-- (that player's card). Both routes call OpenForUser and let the server decide what
-- is safe to return.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = ReplicatedStorage.Modules.Configuration
local RarityConfig = require(Configuration.RarityConfig)
local LiveContentConfig = require(Configuration.LiveContentConfig)
local NumberFormatter = require(ReplicatedStorage.Modules.Shared.NumberFormatter)
local UIFit = require(script.Parent.Parent.UI.UIFit)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestProfileCard = Remotes:WaitForChild("RequestProfileCard")

local player = Players.LocalPlayer

local ProfileCardController = {}
local StateController: any

local topBarButton, panel, avatar, nameLabel, statusLabel, statusPill
local rowsFrame
local statRows: { [string]: TextLabel } = {}
local featureEnabled = true

local Text = LiveContentConfig.Text
local UICfg = LiveContentConfig.UI

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function styleCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

-- One "Label ......... value" row in the stat list. Cached by key so re-rendering
-- reuses instances instead of rebuilding (no growth over repeated opens).
local function ensureStatRow(key: string, order: number): TextLabel
	local existing = statRows[key]
	if existing then
		return existing
	end
	local row = Instance.new("Frame")
	row.Name = "Stat_" .. key
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 24)
	row.LayoutOrder = order
	row.Parent = rowsFrame

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.BackgroundTransparency = 1
	caption.Size = UDim2.new(0.5, 0, 1, 0)
	caption.Font = Enum.Font.Gotham
	caption.TextSize = 14
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextColor3 = Color3.fromRGB(170, 170, 185)
	caption.Text = key
	caption.Parent = row

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.fromScale(1, 0)
	value.Size = UDim2.new(0.5, 0, 1, 0)
	value.Font = Enum.Font.GothamMedium
	value.TextSize = 14
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextTruncate = Enum.TextTruncate.AtEnd
	value.TextColor3 = Color3.fromRGB(235, 235, 240)
	value.Text = ""
	value.Parent = row

	statRows[key] = value
	return value
end

local function build(parent: ScreenGui)
	-- Top-bar Profile button (top-left, below the currency bar; clear of the top-right
	-- Settings/Leaderboard/Donate cluster and the right-side inventory sidebar).
	topBarButton = Instance.new("TextButton")
	topBarButton.Name = "ProfileButton"
	topBarButton.AnchorPoint = Vector2.new(0, 0)
	topBarButton.Position = UDim2.fromOffset(12, 64)
	topBarButton.Size = UDim2.fromOffset(96, 34)
	topBarButton.BackgroundColor3 = Color3.fromRGB(70, 130, 180)
	topBarButton.Font = Enum.Font.GothamBold
	topBarButton.TextSize = 15
	topBarButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	topBarButton.Text = Text.ProfileButton
	topBarButton.ZIndex = 10
	topBarButton.Parent = parent
	styleCorner(topBarButton, 8)
	topBarButton.MouseButton1Click:Connect(function()
		ProfileCardController.OpenOwn()
	end)

	panel = Instance.new("Frame")
	panel.Name = "ProfileCardPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UICfg.ProfileCardSize
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 40
	panel.Parent = parent
	styleCorner(panel, 14)
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(UICfg.ProfileCardSize.X.Offset, UICfg.ProfileCardSize.Y.Offset)
	sizeConstraint.Parent = panel
	UIFit.Fit(panel, UICfg.ProfileCardSize.X.Offset, UICfg.ProfileCardSize.Y.Offset)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 12)
	title.Size = UDim2.new(1, 0, 0, 26)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = Text.ProfileTitle
	title.ZIndex = 41
	title.Parent = panel

	avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	avatar.AnchorPoint = Vector2.new(0.5, 0)
	avatar.Position = UDim2.new(0.5, 0, 0, 46)
	avatar.Size = UDim2.fromOffset(72, 72)
	avatar.ZIndex = 41
	avatar.Parent = panel
	styleCorner(avatar, 36)

	nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(0, 124)
	nameLabel.Size = UDim2.new(1, 0, 0, 24)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 18
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Text = ""
	nameLabel.ZIndex = 41
	nameLabel.Parent = panel

	statusPill = Instance.new("Frame")
	statusPill.Name = "StatusPill"
	statusPill.AnchorPoint = Vector2.new(0.5, 0)
	statusPill.Position = UDim2.new(0.5, 0, 0, 150)
	statusPill.Size = UDim2.fromOffset(88, 20)
	statusPill.BackgroundColor3 = Color3.fromRGB(60, 60, 72)
	statusPill.ZIndex = 41
	statusPill.Parent = panel
	styleCorner(statusPill, 10)
	statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.Size = UDim2.fromScale(1, 1)
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.TextSize = 12
	statusLabel.TextColor3 = Color3.fromRGB(235, 235, 240)
	statusLabel.Text = ""
	statusLabel.ZIndex = 42
	statusLabel.Parent = statusPill

	rowsFrame = Instance.new("Frame")
	rowsFrame.Name = "Rows"
	rowsFrame.BackgroundTransparency = 1
	rowsFrame.Position = UDim2.fromOffset(20, 182)
	rowsFrame.Size = UDim2.new(1, -40, 1, -240)
	rowsFrame.ZIndex = 41
	rowsFrame.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rowsFrame

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -12)
	close.Size = UDim2.new(1, -40, 0, UICfg.MinTouchPx)
	close.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.Text = Text.Close
	close.ZIndex = 41
	close.Parent = panel
	styleCorner(close, 10)
	close.MouseButton1Click:Connect(function()
		ProfileCardController.Close()
	end)
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function loadAvatar(userId: number)
	avatar.Image = ""
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and content and avatar and avatar.Parent then
			avatar.Image = content
		end
	end)
end

-- Hide every cached stat row, then the caller re-shows only the ones it fills.
local function hideAllRows()
	for _, value in pairs(statRows) do
		local row = value.Parent
		if row then
			(row :: Frame).Visible = false
		end
	end
end

local function setRow(key: string, order: number, caption: string, valueText: string, color: Color3?)
	local value = ensureStatRow(key, order)
	local row = value.Parent :: Frame
	row.Visible = true
	row.LayoutOrder = order
	local captionLabel = row:FindFirstChild("Caption") :: TextLabel
	captionLabel.Text = caption
	value.Text = valueText
	value.TextColor3 = color or Color3.fromRGB(235, 235, 240)
end

local function render(card)
	if type(card) ~= "table" then
		return
	end
	hideAllRows()

	nameLabel.Text = tostring(card.DisplayName or "Player")
	loadAvatar(card.UserId)

	local online = card.IsOnline == true
	statusLabel.Text = online and Text.Online or Text.Offline
	statusPill.BackgroundColor3 = online and Color3.fromRGB(50, 120, 70) or Color3.fromRGB(70, 60, 60)

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	if card.IsMinimalPublic then
		-- Offline / not-in-server minimal public donor card.
		if card.NotInServer then
			setRow("note", nextOrder(), Text.PlayerNotInServer, "")
		end
		setRow("donated", nextOrder(), "Robux Donated", NumberFormatter.FormatRobux(card.RobuxDonatedLifetime or 0), Color3.fromRGB(120, 255, 140))
		setRow("rank", nextOrder(), "Donor Rank", card.GlobalDonorRank and ("#" .. card.GlobalDonorRank) or Text.Unranked)
		return
	end

	-- Full card.
	setRow(
		"collection",
		nextOrder(),
		"Collection",
		string.format("%d / %d (%d%%)", card.CollectionCollected or 0, card.CollectionTotal or 0, math.floor(card.CollectionPercent or 0))
	)
	setRow("spins", nextOrder(), "Total Spins", tostring(card.TotalSpins or 0))
	if card.CurrentIncome ~= nil then
		setRow("income", nextOrder(), "Income / sec", NumberFormatter.Format(card.CurrentIncome) .. "/sec", Color3.fromRGB(150, 220, 160))
	end
	setRow("donated", nextOrder(), "Robux Donated", NumberFormatter.FormatRobux(card.RobuxDonatedLifetime or 0), Color3.fromRGB(120, 255, 140))
	setRow("purchases", nextOrder(), "Donations", tostring(card.DonationPurchaseCount or 0))
	setRow("biggest", nextOrder(), "Biggest Donation", NumberFormatter.FormatRobux(card.BiggestRobuxDonation or 0), Color3.fromRGB(120, 255, 140))
	if card.GlobalDonorRank then
		setRow("rank", nextOrder(), "Donor Rank", "#" .. card.GlobalDonorRank)
	end
	if card.BestPullName then
		local color = Color3.fromRGB(235, 235, 240)
		if card.BestPullRarity and RarityConfig.IsValidTier(card.BestPullRarity) then
			color = RarityConfig.Get(card.BestPullRarity).Color
		end
		setRow("bestpull", nextOrder(), "Best Pull", tostring(card.BestPullName), color)
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function ProfileCardController.OnResult(card)
	render(card)
end

-- Open the card for a specific user (own or another). Server decides what is safe.
function ProfileCardController.OpenForUser(userId: number)
	if not featureEnabled or not panel then
		return
	end
	if type(userId) ~= "number" then
		return
	end
	hideAllRows()
	nameLabel.Text = "Loading..."
	statusLabel.Text = ""
	avatar.Image = ""
	panel.Visible = true
	RequestProfileCard:FireServer(userId)
end

function ProfileCardController.OpenOwn()
	ProfileCardController.OpenForUser(player.UserId)
end

function ProfileCardController.Close()
	if panel then
		panel.Visible = false
	end
end

local function applyFlags(state)
	if type(state.featureFlags) == "table" then
		featureEnabled = state.featureFlags.ProfileCardsEnabled ~= false
		if topBarButton then
			topBarButton.Visible = featureEnabled
		end
		if not featureEnabled then
			ProfileCardController.Close()
		end
	end
end

function ProfileCardController.Init(parent: ScreenGui, stateController)
	StateController = stateController
	build(parent)
	if StateController.state then
		applyFlags(StateController.state)
	end
	StateController.Subscribe(function(state, changed)
		if changed.featureFlags then
			applyFlags(state)
		end
	end)
end

return ProfileCardController
