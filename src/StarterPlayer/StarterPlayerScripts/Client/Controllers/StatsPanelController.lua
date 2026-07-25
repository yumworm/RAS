--!strict
-- StatsPanelController: a read-only legacy stats panel. Every number comes from the
-- server-replicated StateController mirror -- currency and income arrive live via
-- deltas, the slow "highest / lifetime" figures come from the join snapshot's economy
-- block, and the panel composes accurate live values from both (e.g. lifetime earnings
-- = snapshot lifetime + this session's earnings). There are no edit buttons, no shop,
-- and zero local economy simulation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = ReplicatedStorage.Modules.Configuration
local StreamerDatabase = require(Configuration.StreamerDatabase)
local RarityConfig = require(Configuration.RarityConfig)
local GameConfig = require(Configuration.GameConfig)
local LiveContentConfig = require(Configuration.LiveContentConfig)
local NumberFormatter = require(ReplicatedStorage.Modules.Shared.NumberFormatter)
local UIFit = require(script.Parent.Parent.UI.UIFit)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AnalyticsUIEvent = Remotes:WaitForChild("AnalyticsUIEvent")

local StatsPanelController = {}
local StateController: any

local topBarButton, panel, listFrame
local statRows: { [string]: TextLabel } = {}
local featureEnabled = true

local Text = LiveContentConfig.Text
local UICfg = LiveContentConfig.UI

local function styleCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function formatDuration(seconds: number): string
	seconds = math.max(math.floor(seconds), 0)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm", minutes)
	end
	return string.format("%ds", seconds)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function ensureRow(key: string, order: number, caption: string): TextLabel
	local existing = statRows[key]
	if existing then
		return existing
	end
	local row = Instance.new("Frame")
	row.Name = "Stat_" .. key
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 24)
	row.LayoutOrder = order
	row.Parent = listFrame

	local captionLabel = Instance.new("TextLabel")
	captionLabel.Name = "Caption"
	captionLabel.BackgroundTransparency = 1
	captionLabel.Size = UDim2.new(0.55, 0, 1, 0)
	captionLabel.Font = Enum.Font.Gotham
	captionLabel.TextSize = 14
	captionLabel.TextXAlignment = Enum.TextXAlignment.Left
	captionLabel.TextColor3 = Color3.fromRGB(170, 170, 185)
	captionLabel.Text = caption
	captionLabel.Parent = row

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.fromScale(1, 0)
	value.Size = UDim2.new(0.45, 0, 1, 0)
	value.Font = Enum.Font.GothamBold
	value.TextSize = 14
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextTruncate = Enum.TextTruncate.AtEnd
	value.TextColor3 = Color3.fromRGB(235, 235, 240)
	value.Text = ""
	value.Parent = row

	statRows[key] = value
	return value
end

local function setRow(key: string, order: number, caption: string, valueText: string, color: Color3?)
	local value = ensureRow(key, order, caption)
	local row = value.Parent :: Frame
	row.Visible = true
	row.LayoutOrder = order
	local captionLabel = row:FindFirstChild("Caption") :: TextLabel
	captionLabel.Text = caption
	value.Text = valueText
	value.TextColor3 = color or Color3.fromRGB(235, 235, 240)
end

local function build(parent: ScreenGui)
	topBarButton = Instance.new("TextButton")
	topBarButton.Name = "StatsButton"
	topBarButton.AnchorPoint = Vector2.new(0, 0)
	topBarButton.Position = UDim2.fromOffset(114, 64) -- just right of the Profile button
	topBarButton.Size = UDim2.fromOffset(96, 34)
	topBarButton.BackgroundColor3 = Color3.fromRGB(90, 100, 120)
	topBarButton.Font = Enum.Font.GothamBold
	topBarButton.TextSize = 15
	topBarButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	topBarButton.Text = Text.StatsButton
	topBarButton.ZIndex = 10
	topBarButton.Parent = parent
	styleCorner(topBarButton, 8)
	topBarButton.MouseButton1Click:Connect(function()
		StatsPanelController.Toggle()
	end)

	panel = Instance.new("Frame")
	panel.Name = "StatsPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UICfg.StatsPanelSize
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 42
	panel.Parent = parent
	styleCorner(panel, 14)
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(UICfg.StatsPanelSize.X.Offset, UICfg.StatsPanelSize.Y.Offset)
	sizeConstraint.Parent = panel
	UIFit.Fit(panel, UICfg.StatsPanelSize.X.Offset, UICfg.StatsPanelSize.Y.Offset)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 12)
	title.Size = UDim2.new(1, 0, 0, 26)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = Text.StatsTitle
	title.ZIndex = 43
	title.Parent = panel

	listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "List"
	listFrame.Position = UDim2.fromOffset(20, 46)
	listFrame.Size = UDim2.new(1, -40, 1, -104)
	listFrame.BackgroundTransparency = 1
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 6
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.ZIndex = 43
	listFrame.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listFrame

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
	close.ZIndex = 43
	close.Parent = panel
	styleCorner(close, 10)
	close.MouseButton1Click:Connect(function()
		StatsPanelController.Close()
	end)
end

--------------------------------------------------------------------------------
-- Render (composes live values from snapshot economy + live currency/income/session)
--------------------------------------------------------------------------------

local function render()
	local state = StateController.state
	local economy = state.economy or {}
	local session = state.session or {}
	local collection = state.collection or {}
	local stats = state.stats or {}
	local donation = state.donation or {}

	local liveCurrency = state.currency or 0
	local liveIncome = state.income or 0
	local lifetimeEarned = (economy.lifetimeEarned or 0) + (session.earnings or 0)
	local highestCurrency = math.max(economy.highestCurrency or 0, liveCurrency)
	local highestIncome = math.max(economy.highestIncome or 0, liveIncome)

	local order = 0
	local function n(): number
		order += 1
		return order
	end

	local bucksColor = Color3.fromRGB(255, 235, 150)
	local robuxColor = Color3.fromRGB(120, 255, 140)

	setRow("currency", n(), GameConfig.CurrencyName, NumberFormatter.Format(liveCurrency), bucksColor)
	setRow("lifetimeEarned", n(), "Lifetime Earnings", NumberFormatter.Format(lifetimeEarned), bucksColor)
	setRow("lifetimeSpent", n(), "Lifetime Spent", NumberFormatter.Format(economy.lifetimeSpent or 0), bucksColor)
	setRow("income", n(), "Income / sec", NumberFormatter.Format(liveIncome) .. "/sec", Color3.fromRGB(150, 220, 160))
	setRow("highestIncome", n(), "Highest Income", NumberFormatter.Format(highestIncome) .. "/sec")
	setRow("highestCurrency", n(), "Highest " .. GameConfig.CurrencyName, NumberFormatter.Format(highestCurrency))
	setRow("totalSpins", n(), "Total Spins", tostring(stats.totalSpins or 0))
	setRow("sessionSpins", n(), "Session Spins", tostring(session.spins or 0))
	setRow("sessionEarnings", n(), "Session Earnings", NumberFormatter.Format(session.earnings or 0), bucksColor)
	setRow(
		"collection",
		n(),
		"Collection",
		string.format("%d / %d (%d%%)", collection.collected or 0, collection.total or 0, math.floor(collection.percentage or 0))
	)
	setRow("duplicates", n(), "Duplicates", tostring(collection.duplicates or 0))

	-- Best pull (name resolved client-side from the shared database).
	local best = stats.bestPull
	if best and best.streamerId and best.streamerId ~= 0 then
		local streamer = StreamerDatabase.Get(best.streamerId)
		local color = Color3.fromRGB(235, 235, 240)
		if best.rarity and RarityConfig.IsValidTier(best.rarity) then
			color = RarityConfig.Get(best.rarity).Color
		end
		setRow("bestpull", n(), "Best Pull", streamer and streamer.name or "Unknown", color)
	end

	setRow("donated", n(), "Robux Donated", NumberFormatter.FormatRobux(donation.robuxDonatedLifetime or 0), robuxColor)
	setRow("donations", n(), "Donations", tostring(donation.donationPurchaseCount or 0))
	setRow("biggest", n(), "Biggest Donation", NumberFormatter.FormatRobux(donation.biggestRobuxDonation or 0), robuxColor)
	setRow("playtime", n(), "Play Time", formatDuration(stats.totalPlayTime or 0))
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function StatsPanelController.Open()
	if not featureEnabled or not panel then
		return
	end
	render()
	panel.Visible = true
	-- Developer-only ping (rate-limited + allowlisted server-side).
	AnalyticsUIEvent:FireServer("stats_panel_opened")
end

function StatsPanelController.Close()
	if panel then
		panel.Visible = false
	end
end

function StatsPanelController.Toggle()
	if panel then
		if panel.Visible then
			StatsPanelController.Close()
		else
			StatsPanelController.Open()
		end
	end
end

local function applyFlags(state)
	if type(state.featureFlags) == "table" then
		featureEnabled = state.featureFlags.StatsPanelEnabled ~= false
		if topBarButton then
			topBarButton.Visible = featureEnabled
		end
		if not featureEnabled then
			StatsPanelController.Close()
		end
	end
end

function StatsPanelController.Init(parent: ScreenGui, stateController)
	StateController = stateController
	build(parent)
	if StateController.state then
		applyFlags(StateController.state)
	end
	StateController.Subscribe(function(state, changed)
		if changed.featureFlags then
			applyFlags(state)
		end
		-- Keep the panel live while it is open (currency/income/session tick in).
		if panel and panel.Visible then
			render()
		end
	end)
end

return StatsPanelController
