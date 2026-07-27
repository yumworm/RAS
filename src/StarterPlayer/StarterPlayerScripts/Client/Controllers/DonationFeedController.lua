--!strict
-- DonationFeedController: a compact, non-blocking live feed of donations TO THE GAME.
-- It is purely presentational: it renders the server snapshot from the initial payload
-- and each DonationFeedPush, newest on top. It never invents rows and never appends --
-- only the server writes the feed.
--
-- It is deliberately click-through (Active = false, no input capture) and anchored
-- bottom-left, so it can never cover the Spin button. It is hidden when the feature
-- flag is off OR the player's ShowDonationFeed setting is off (the server still records
-- either way). Row text is donor display name only -- no receiver, no UserId.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LiveContentConfig = require(ReplicatedStorage.Modules.Configuration.LiveContentConfig)
local NumberFormatter = require(ReplicatedStorage.Modules.Shared.NumberFormatter)

local DonationFeedController = {}
local StateController: any

local container, listFrame, titleLabel
local rows: { Frame } = {} -- newest-first; capped at FeedMaxVisibleRows
local flagEnabled = true -- FeatureFlags.DonationFeedEnabled (from payload)
local showSetting = true -- Settings.showDonationFeed

local FeedCfg = LiveContentConfig.DonationFeed
local UICfg = LiveContentConfig.UI

local NORMAL_COLOR = Color3.fromRGB(200, 220, 205)
local LARGE_COLOR = Color3.fromRGB(255, 225, 120)

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function build(parent: ScreenGui)
	container = Instance.new("Frame")
	container.Name = "DonationFeed"
	container.AnchorPoint = Vector2.new(0, 1)
	container.Position = UDim2.new(0, 12, 1, -12)
	container.Size = UDim2.fromOffset(UICfg.FeedWidth, UICfg.FeedHeight + 26)
	container.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
	container.BackgroundTransparency = 0.25
	container.BorderSizePixel = 0
	container.Active = false -- never steal input; the feed is click-through
	container.Visible = false
	container.ZIndex = 4
	container.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = container

	titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromOffset(10, 4)
	titleLabel.Size = UDim2.new(1, -20, 0, 20)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = Color3.fromRGB(180, 180, 195)
	titleLabel.Text = LiveContentConfig.Text.FeedTitle
	titleLabel.ZIndex = 4
	titleLabel.Parent = container

	listFrame = Instance.new("Frame")
	listFrame.Name = "List"
	listFrame.BackgroundTransparency = 1
	listFrame.Position = UDim2.fromOffset(10, 26)
	listFrame.Size = UDim2.new(1, -20, 1, -32)
	listFrame.ClipsDescendants = true
	listFrame.ZIndex = 4
	listFrame.Parent = container
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listFrame
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function rowText(event): string
	local amount = NumberFormatter.FormatRobux(event.Amount)
	local text = FeedCfg.RowTemplate
	text = string.gsub(text, "{donor}", tostring(event.DonorName))
	text = string.gsub(text, "{amount}", amount)
	return text
end

local function makeRow(event): Frame
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 18)
	row.ZIndex = 4

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = event.Amount >= FeedCfg.LargeAmountThreshold and Enum.Font.GothamBold or Enum.Font.Gotham
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextColor3 = event.Amount >= FeedCfg.LargeAmountThreshold and LARGE_COLOR or NORMAL_COLOR
	label.Text = rowText(event)
	label.ZIndex = 4
	label.Parent = row
	return row
end

-- Insert one event at the top and evict rows beyond the visible cap.
local function pushRow(event)
	if type(event) ~= "table" or type(event.Amount) ~= "number" then
		return
	end
	local row = makeRow(event)
	row.Parent = listFrame
	table.insert(rows, 1, row)
	-- LayoutOrder ascending = top-to-bottom; newest gets the smallest order.
	for i, r in ipairs(rows) do
		r.LayoutOrder = i
	end
	while #rows > UICfg.FeedMaxVisibleRows do
		local old = table.remove(rows)
		if old then
			old:Destroy()
		end
	end
end

local function clearRows()
	for _, r in ipairs(rows) do
		r:Destroy()
	end
	table.clear(rows)
end

local function refreshVisibility()
	if container then
		container.Visible = flagEnabled and showSetting
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- A single pushed event (DonationFeedPush).
function DonationFeedController.OnPush(event)
	if not flagEnabled then
		return
	end
	pushRow(event)
end

-- Apply the initial snapshot (newest-first) from the join payload.
local function applySnapshot(snapshot)
	clearRows()
	if type(snapshot) ~= "table" or type(snapshot.entries) ~= "table" then
		return
	end
	-- Snapshot is newest-first; render oldest first so the newest ends up on top.
	for i = math.min(#snapshot.entries, UICfg.FeedMaxVisibleRows), 1, -1 do
		pushRow(snapshot.entries[i])
	end
end

local function onState(state, changed)
	if changed.featureFlags and type(state.featureFlags) == "table" then
		flagEnabled = state.featureFlags.DonationFeedEnabled ~= false
		refreshVisibility()
	end
	if changed.settings and type(state.settings) == "table" then
		showSetting = state.settings.showDonationFeed ~= false
		refreshVisibility()
	end
	if changed.donationFeed then
		applySnapshot(state.donationFeed)
	end
end

function DonationFeedController.Init(parent: ScreenGui, stateController)
	StateController = stateController
	build(parent)
	-- Seed from any snapshot that already arrived before we built.
	local state = StateController.state
	if state then
		if type(state.featureFlags) == "table" then
			flagEnabled = state.featureFlags.DonationFeedEnabled ~= false
		end
		if type(state.settings) == "table" then
			showSetting = state.settings.showDonationFeed ~= false
		end
		if state.donationFeed then
			applySnapshot(state.donationFeed)
		end
	end
	refreshVisibility()
	StateController.Subscribe(onState)
end

return DonationFeedController
