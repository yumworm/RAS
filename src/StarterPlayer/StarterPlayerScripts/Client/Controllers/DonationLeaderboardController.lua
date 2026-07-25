--!strict
-- DonationLeaderboardController: the top-bar Leaderboard button and the detailed
-- Top 100 donors panel. It is purely presentational -- it renders whatever server
-- snapshot arrives (GlobalDonorLeaderboardUpdated) and never invents rows, ranks, or
-- totals. Opening the panel asks the server for a fresh snapshot; the server serves
-- it from its 30s cache, so opening is cheap and never hits the OrderedDataStore
-- directly (the client cannot, and must not).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DonationConfig = require(ReplicatedStorage.Modules.Configuration.DonationConfig)
local NumberFormatter = require(ReplicatedStorage.Modules.Shared.NumberFormatter)
local UIFit = require(script.Parent.Parent.UI.UIFit)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestGlobalDonorLeaderboard = Remotes:WaitForChild("RequestGlobalDonorLeaderboard")

local player = Players.LocalPlayer

local DonationLeaderboardController = {}

local panel, rowsFrame, footerTotal, footerRank, refreshLabel
local topBarButton
local rowCache = {} -- rank -> Frame (reused across renders)
local rowClickHandler: ((number) -> ())? = nil -- set by bootstrap -> opens a profile card

local RANK_COLORS = {
	[1] = Color3.fromRGB(255, 215, 0),
	[2] = Color3.fromRGB(192, 192, 200),
	[3] = Color3.fromRGB(205, 127, 50),
}
local ROW_COLOR = Color3.fromRGB(30, 30, 38)
local SELF_COLOR = Color3.fromRGB(40, 70, 120)

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function styleCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function build(parent: ScreenGui)
	topBarButton = Instance.new("TextButton")
	topBarButton.Name = "LeaderboardButton"
	topBarButton.AnchorPoint = Vector2.new(1, 0)
	topBarButton.Position = UDim2.new(1, -144, 0, 11) -- just left of the Donate button
	topBarButton.Size = UDim2.fromOffset(132, 34)
	topBarButton.BackgroundColor3 = Color3.fromRGB(90, 110, 240)
	topBarButton.Font = Enum.Font.GothamBold
	topBarButton.TextSize = 16
	topBarButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	topBarButton.Text = DonationConfig.Text.LeaderboardButton
	topBarButton.ZIndex = 10
	topBarButton.Parent = parent
	styleCorner(topBarButton, 8)
	topBarButton.MouseButton1Click:Connect(function()
		DonationLeaderboardController.Toggle()
	end)

	panel = Instance.new("Frame")
	panel.Name = "DonationLeaderboardPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(DonationConfig.UI.LeaderboardPanelSize.X, DonationConfig.UI.LeaderboardPanelSize.Y)
	panel.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 30
	panel.Parent = parent
	styleCorner(panel, 14)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = DonationConfig.UI.LeaderboardPanelSize
	sizeConstraint.Parent = panel
	-- The Top 100 panel is large (580x650); uniformly scale it to fit phone/tablet
	-- viewports so it never overflows, without reworking its offset-based rows.
	UIFit.Fit(panel, DonationConfig.UI.LeaderboardPanelSize.X, DonationConfig.UI.LeaderboardPanelSize.Y)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 14)
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = DonationConfig.Text.LeaderboardTitle
	title.ZIndex = 31
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(0, 44)
	subtitle.Size = UDim2.new(1, 0, 0, 18)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 14
	subtitle.TextColor3 = Color3.fromRGB(180, 180, 195)
	subtitle.Text = DonationConfig.Text.LeaderboardSubtitle
	subtitle.ZIndex = 31
	subtitle.Parent = panel

	rowsFrame = Instance.new("ScrollingFrame")
	rowsFrame.Name = "Rows"
	rowsFrame.Position = UDim2.fromOffset(16, 74)
	rowsFrame.Size = UDim2.new(1, -32, 1, -150)
	rowsFrame.BackgroundTransparency = 1
	rowsFrame.BorderSizePixel = 0
	rowsFrame.ScrollBarThickness = 8
	rowsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	rowsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rowsFrame.ZIndex = 31
	rowsFrame.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rowsFrame

	-- Footer: own total + rank + refresh/stale indicator.
	footerTotal = Instance.new("TextLabel")
	footerTotal.Name = "FooterTotal"
	footerTotal.BackgroundTransparency = 1
	footerTotal.AnchorPoint = Vector2.new(0, 1)
	footerTotal.Position = UDim2.new(0, 16, 1, -46)
	footerTotal.Size = UDim2.new(0.5, -16, 0, 22)
	footerTotal.Font = Enum.Font.GothamMedium
	footerTotal.TextSize = 15
	footerTotal.TextXAlignment = Enum.TextXAlignment.Left
	footerTotal.TextColor3 = Color3.fromRGB(120, 255, 140)
	footerTotal.Text = DonationConfig.Text.FooterTotalPrefix .. " 0"
	footerTotal.ZIndex = 31
	footerTotal.Parent = panel

	footerRank = Instance.new("TextLabel")
	footerRank.Name = "FooterRank"
	footerRank.BackgroundTransparency = 1
	footerRank.AnchorPoint = Vector2.new(1, 1)
	footerRank.Position = UDim2.new(1, -16, 1, -46)
	footerRank.Size = UDim2.new(0.5, -16, 0, 22)
	footerRank.Font = Enum.Font.GothamMedium
	footerRank.TextSize = 15
	footerRank.TextXAlignment = Enum.TextXAlignment.Right
	footerRank.TextColor3 = Color3.fromRGB(220, 220, 230)
	footerRank.Text = DonationConfig.Text.FooterRankPrefix .. " " .. DonationConfig.Text.UnrankedText
	footerRank.ZIndex = 31
	footerRank.Parent = panel

	refreshLabel = Instance.new("TextLabel")
	refreshLabel.Name = "RefreshLabel"
	refreshLabel.BackgroundTransparency = 1
	refreshLabel.AnchorPoint = Vector2.new(0.5, 1)
	refreshLabel.Position = UDim2.new(0.5, 0, 1, -8)
	refreshLabel.Size = UDim2.new(1, -120, 0, 16)
	refreshLabel.Font = Enum.Font.Gotham
	refreshLabel.TextSize = 12
	refreshLabel.TextColor3 = Color3.fromRGB(120, 120, 135)
	refreshLabel.Text = ""
	refreshLabel.ZIndex = 31
	refreshLabel.Parent = panel

	local close = Instance.new("TextButton")
	close.Name = "CloseButton"
	close.AnchorPoint = Vector2.new(1, 1)
	close.Position = UDim2.new(1, -16, 1, -6)
	close.Size = UDim2.fromOffset(90, 30)
	close.BackgroundColor3 = Color3.fromRGB(44, 44, 54)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 14
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.Text = "Close"
	close.ZIndex = 32
	close.Parent = panel
	styleCorner(close, 8)
	close.MouseButton1Click:Connect(function()
		DonationLeaderboardController.Close()
	end)
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function makeRow(rank: number): Frame
	local row = Instance.new("Frame")
	row.Name = "Row_" .. rank
	row.Size = UDim2.new(1, 0, 0, 44)
	row.BackgroundColor3 = ROW_COLOR
	row.BorderSizePixel = 0
	row.ZIndex = 31
	styleCorner(row, 8)

	local rankLabel = Instance.new("TextLabel")
	rankLabel.Name = "Rank"
	rankLabel.BackgroundTransparency = 1
	rankLabel.Position = UDim2.fromOffset(8, 0)
	rankLabel.Size = UDim2.fromOffset(48, 44)
	rankLabel.Font = Enum.Font.GothamBold
	rankLabel.TextSize = 18
	rankLabel.TextXAlignment = Enum.TextXAlignment.Left
	rankLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
	rankLabel.ZIndex = 32
	rankLabel.Parent = row

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	avatar.Position = UDim2.fromOffset(58, 4)
	avatar.Size = UDim2.fromOffset(36, 36)
	avatar.ZIndex = 32
	avatar.Parent = row
	styleCorner(avatar, 18)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Username"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(102, 0)
	nameLabel.Size = UDim2.new(1, -240, 1, 0)
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.TextSize = 16
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.TextColor3 = Color3.fromRGB(235, 235, 240)
	nameLabel.ZIndex = 32
	nameLabel.Parent = row

	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "Amount"
	amountLabel.BackgroundTransparency = 1
	amountLabel.AnchorPoint = Vector2.new(1, 0)
	amountLabel.Position = UDim2.new(1, -12, 0, 0)
	amountLabel.Size = UDim2.fromOffset(130, 44)
	amountLabel.Font = Enum.Font.GothamBold
	amountLabel.TextSize = 16
	amountLabel.TextXAlignment = Enum.TextXAlignment.Right
	amountLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
	amountLabel.ZIndex = 32
	amountLabel.Parent = row

	-- Transparent click catcher: tapping a row opens that player's profile card. The
	-- target UserId is stored as an attribute and refreshed per snapshot, so this
	-- connection is wired once per cached row (never per render -> no growth).
	local clickCatcher = Instance.new("TextButton")
	clickCatcher.Name = "ClickCatcher"
	clickCatcher.BackgroundTransparency = 1
	clickCatcher.Text = ""
	clickCatcher.Size = UDim2.fromScale(1, 1)
	clickCatcher.ZIndex = 33
	clickCatcher.Parent = row
	clickCatcher.MouseButton1Click:Connect(function()
		local userId = row:GetAttribute("UserId")
		if rowClickHandler and type(userId) == "number" then
			rowClickHandler(userId)
		end
	end)

	return row
end

-- Load an avatar headshot asynchronously so a slow thumbnail never blocks the render.
local function loadAvatar(image: ImageLabel, userId: number)
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok and content and image and image.Parent then
			image.Image = content
		end
	end)
end

local function applySnapshot(snapshot)
	if type(snapshot) ~= "table" or not rowsFrame then
		return
	end
	local entries = snapshot.Entries or {}
	local localUserId = snapshot.LocalUserId

	-- Hide all cached rows first; re-show the ones this snapshot fills.
	for _, row in pairs(rowCache) do
		row.Visible = false
	end

	for _, entry in ipairs(entries) do
		local row = rowCache[entry.Rank]
		if not row then
			row = makeRow(entry.Rank)
			row.Parent = rowsFrame
			rowCache[entry.Rank] = row
		end
		row.Visible = true
		row.LayoutOrder = entry.Rank
		row:SetAttribute("UserId", entry.UserId) -- target for the row click -> profile card

		local podium = RANK_COLORS[entry.Rank]
		local isSelf = localUserId ~= nil and entry.UserId == localUserId
		row.BackgroundColor3 = isSelf and SELF_COLOR or (podium and podium:Lerp(ROW_COLOR, 0.6) or ROW_COLOR)

		row.Rank.Text = "#" .. entry.Rank
		row.Rank.TextColor3 = podium or Color3.fromRGB(220, 220, 230)
		row.Username.Text = entry.Username
		row.Username.TextColor3 = podium or (isSelf and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(235, 235, 240))
		row.Amount.Text = NumberFormatter.FormatRobux(entry.RobuxDonated)
		loadAvatar(row.Avatar, entry.UserId)
	end

	-- Footer: own total + rank.
	local total = snapshot.LocalTotal or 0
	footerTotal.Text = DonationConfig.Text.FooterTotalPrefix .. " " .. NumberFormatter.FormatRobux(total)
	if snapshot.LocalRank then
		footerRank.Text = DonationConfig.Text.FooterRankPrefix .. " #" .. snapshot.LocalRank
	else
		footerRank.Text = DonationConfig.Text.FooterRankPrefix .. " " .. DonationConfig.Text.UnrankedText
	end

	-- Refresh / stale indicator.
	local staleSuffix = snapshot.Stale and (" " .. DonationConfig.Text.StaleSuffix) or ""
	if #entries == 0 then
		refreshLabel.Text = DonationConfig.Text.EmptyBoardText
	elseif snapshot.GeneratedAt and snapshot.GeneratedAt > 0 then
		refreshLabel.Text = string.format("Updated %s%s", os.date("!%H:%M:%S UTC", snapshot.GeneratedAt), staleSuffix)
	else
		refreshLabel.Text = staleSuffix
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function DonationLeaderboardController.ApplySnapshot(snapshot)
	applySnapshot(snapshot)
end

function DonationLeaderboardController.Open()
	if not panel then
		return
	end
	panel.Visible = true
	RequestGlobalDonorLeaderboard:FireServer() -- ask for a fresh (cached) snapshot
end

function DonationLeaderboardController.Close()
	if panel then
		panel.Visible = false
	end
end

function DonationLeaderboardController.Toggle()
	if panel then
		if panel.Visible then
			DonationLeaderboardController.Close()
		else
			DonationLeaderboardController.Open()
		end
	end
end

-- Register a handler invoked with a UserId when a leaderboard row is tapped (the
-- bootstrap wires this to ProfileCardController.OpenForUser).
function DonationLeaderboardController.SetRowClickHandler(fn: (number) -> ())
	rowClickHandler = fn
end

function DonationLeaderboardController.Init(parent: ScreenGui)
	build(parent)
end

return DonationLeaderboardController
