--!strict
-- ReturnSummaryController: the welcome-back panel. It renders the server-provided
-- returnSummary payload (facts only) exactly once per session, then the Continue
-- button just closes it. It grants nothing, changes nothing, and never pauses income
-- (the HUD keeps ticking behind the panel). Eligibility -- feature flag, opt-out,
-- first-session suppression, minimum time away -- is decided entirely on the server;
-- the client simply shows the panel when a payload is present.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = ReplicatedStorage.Modules.Configuration
local RarityConfig = require(Configuration.RarityConfig)
local LiveContentConfig = require(Configuration.LiveContentConfig)
local NumberFormatter = require(ReplicatedStorage.Modules.Shared.NumberFormatter)
local UIFit = require(script.Parent.Parent.UI.UIFit)

local ReturnSummaryController = {}
local StateController: any

-- Built once by `build`; typed concretely so class-specific properties resolve.
local panel: Frame?
local rowsFrame: Frame?
local handled = false -- show at most once per session

local Cfg = LiveContentConfig.ReturnSummary
local Text = LiveContentConfig.Text
local UICfg = LiveContentConfig.UI

--------------------------------------------------------------------------------
-- Duration formatting (display only)
--------------------------------------------------------------------------------

local function formatDuration(seconds: number): string
	seconds = math.max(math.floor(seconds), 0)
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if days > 0 then
		return string.format("%dd %dh", days, hours)
	elseif hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm", minutes)
	end
	return string.format("%ds", seconds)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function styleCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function addRow(order: number, caption: string, valueText: string, color: Color3?)
	local row = Instance.new("Frame")
	row.Name = "Row_" .. order
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 26)
	row.LayoutOrder = order
	row.Parent = rowsFrame

	local captionLabel = Instance.new("TextLabel")
	captionLabel.BackgroundTransparency = 1
	captionLabel.Size = UDim2.new(0.55, 0, 1, 0)
	captionLabel.Font = Enum.Font.Gotham
	captionLabel.TextSize = 15
	captionLabel.TextXAlignment = Enum.TextXAlignment.Left
	captionLabel.TextColor3 = Color3.fromRGB(175, 175, 190)
	captionLabel.Text = caption
	captionLabel.Parent = row

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.AnchorPoint = Vector2.new(1, 0)
	valueLabel.Position = UDim2.fromScale(1, 0)
	valueLabel.Size = UDim2.new(0.45, 0, 1, 0)
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextSize = 15
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	valueLabel.TextColor3 = color or Color3.fromRGB(235, 235, 240)
	valueLabel.Text = valueText
	valueLabel.Parent = row
end

-- Built into function-locals and published to the module-level handles at the end;
-- assignment narrows a function-local but never a module-level one.
local function build(parent: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "ReturnSummaryPanel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UICfg.ReturnSummarySize
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 45
	frame.Parent = parent
	styleCorner(frame, 14)
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(UICfg.ReturnSummarySize.X.Offset, UICfg.ReturnSummarySize.Y.Offset)
	sizeConstraint.Parent = frame
	UIFit.Fit(frame, UICfg.ReturnSummarySize.X.Offset, UICfg.ReturnSummarySize.Y.Offset)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 14)
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = Cfg.PanelTitle
	title.ZIndex = 46
	title.Parent = frame

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromOffset(20, 52)
	rows.Size = UDim2.new(1, -40, 1, -122)
	rows.ZIndex = 46
	rows.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rows

	local continueButton = Instance.new("TextButton")
	continueButton.Name = "Continue"
	continueButton.AnchorPoint = Vector2.new(0.5, 1)
	continueButton.Position = UDim2.new(0.5, 0, 1, -14)
	continueButton.Size = UDim2.new(1, -40, 0, UICfg.MinTouchPx)
	continueButton.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
	continueButton.Font = Enum.Font.GothamBold
	continueButton.TextSize = 17
	continueButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	continueButton.Text = Cfg.ContinueText
	continueButton.ZIndex = 46
	continueButton.Parent = frame
	styleCorner(continueButton, 10)
	continueButton.MouseButton1Click:Connect(function()
		-- Continue ONLY closes UI. No currency, no inventory, no grant.
		frame.Visible = false
	end)

	panel, rowsFrame = frame, rows
end

--------------------------------------------------------------------------------
-- Show
--------------------------------------------------------------------------------

local function show(summary)
	local frame = panel
	local rows = rowsFrame
	if not frame or not rows then
		return
	end

	-- Rebuild the rows (cheap; happens once per session). Wrapped in a positive
	-- block rather than relying on the guard above: refinements survive inside an
	-- `if`, but are dropped after an early return.
	if rows then
		for _, child in ipairs(rows:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	addRow(nextOrder(), Text.TimeAwayLabel, formatDuration(summary.TimeAwaySec or 0), Color3.fromRGB(255, 225, 140))
	addRow(
		nextOrder(),
		"Income / sec",
		NumberFormatter.Format(summary.CurrentIncome or 0) .. "/sec",
		Color3.fromRGB(150, 220, 160)
	)
	addRow(nextOrder(), "Lifetime Spins", tostring(summary.LifetimeSpins or 0))
	addRow(
		nextOrder(),
		"Collection",
		string.format(
			"%d / %d (%d%%)",
			summary.CollectionCollected or 0,
			summary.CollectionTotal or 0,
			math.floor(summary.CollectionPercent or 0)
		)
	)
	addRow(
		nextOrder(),
		"Robux Donated",
		NumberFormatter.FormatRobux(summary.RobuxDonatedLifetime or 0),
		Color3.fromRGB(120, 255, 140)
	)
	addRow(nextOrder(), "Donations", tostring(summary.DonationPurchaseCount or 0))
	addRow(
		nextOrder(),
		"Biggest Donation",
		NumberFormatter.FormatRobux(summary.BiggestRobuxDonation or 0),
		Color3.fromRGB(120, 255, 140)
	)
	if summary.BestPullName then
		local color = Color3.fromRGB(235, 235, 240)
		if summary.BestPullRarity and RarityConfig.IsValidTier(summary.BestPullRarity) then
			color = RarityConfig.Get(summary.BestPullRarity).Color
		end
		addRow(nextOrder(), "Best Pull", tostring(summary.BestPullName), color)
	end

	if frame then
		frame.Visible = true
	end
end

local function tryShow(state)
	if handled then
		return
	end
	local summary = state.returnSummary
	if type(summary) ~= "table" then
		return
	end
	handled = true
	show(summary)
end

function ReturnSummaryController.Init(parent: ScreenGui, stateController)
	StateController = stateController
	build(parent)
	if StateController.ready and StateController.state then
		tryShow(StateController.state)
	end
	StateController.Subscribe(function(state, changed)
		if changed.returnSummary then
			tryShow(state)
		end
	end)
end

return ReturnSummaryController
