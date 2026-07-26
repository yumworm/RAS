--!strict
-- DonationController: the client donation panel and the top-bar Donate button. It
-- only ever REQUESTS a prompt for an amount; the server validates the amount, maps
-- it to a product, and prompts the purchase. Real crediting happens server-side in
-- ProcessReceipt -- this controller never sets or trusts a total. It renders the
-- player's own Robux-donated stat straight from StateController (server-provided).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local DonationConfig = require(ReplicatedStorage.Modules.Configuration.DonationConfig)
local NumberFormatter = require(ReplicatedStorage.Modules.Shared.NumberFormatter)
local AudioController = require(script.Parent.AudioController)
local UIFit = require(script.Parent.Parent.UI.UIFit)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestDonationPrompt = Remotes:WaitForChild("RequestDonationPrompt")
-- Developer-only funnel signal: fired when this panel opens. It carries no gameplay
-- authority; the server rate-limits and logs it (see AnalyticsMonitorSystem).
local AnalyticsDonationPanelOpened = Remotes:WaitForChild("AnalyticsDonationPanelOpened")

local player = Players.LocalPlayer

local DonationController = {}
local StateController: any
local leaderboardController: any

local panel, personalLabel, statusLabel, topBarButton
local amountButtons = {} -- array of TextButtons
local pending = false
local pendingClearAt = 0

--------------------------------------------------------------------------------
-- Pending state (disables amount buttons while a prompt is open)
--------------------------------------------------------------------------------

local function setPending(value: boolean)
	pending = value
	pendingClearAt = value and (os.clock() + DonationConfig.PromptPendingTimeout + 5) or 0
	for _, button in ipairs(amountButtons) do
		button.Active = not value
		button.AutoButtonColor = not value
		button.BackgroundTransparency = value and 0.4 or 0
	end
end

-- Safety valve: if no server/marketplace callback ever arrives, re-enable buttons
-- after the timeout so the panel can never wedge.
local function pendingWatchdog()
	task.spawn(function()
		while true do
			task.wait(1)
			if pending and os.clock() >= pendingClearAt then
				setPending(false)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function styleCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function makeAmountButton(amount: number, parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Amount_" .. amount
	button.Size = UDim2.new(0.5, -8, 0, 46)
	button.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 18
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Text = tostring(amount) .. " Robux"
	button.Parent = parent
	styleCorner(button, 10)

	button.MouseButton1Click:Connect(function()
		DonationController.RequestDonation(amount)
	end)
	return button
end

local function build(parent: ScreenGui)
	-- Top-bar Donate button (top-right; leaves the left-aligned HUD untouched).
	topBarButton = Instance.new("TextButton")
	topBarButton.Name = "DonateButton"
	topBarButton.AnchorPoint = Vector2.new(1, 0)
	topBarButton.Position = UDim2.new(1, -16, 0, 11)
	topBarButton.Size = UDim2.fromOffset(120, 34)
	topBarButton.BackgroundColor3 = Color3.fromRGB(240, 90, 130)
	topBarButton.Font = Enum.Font.GothamBold
	topBarButton.TextSize = 16
	topBarButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	topBarButton.Text = DonationConfig.Text.DonateButton
	topBarButton.ZIndex = 10
	topBarButton.Parent = parent
	styleCorner(topBarButton, 8)
	topBarButton.MouseButton1Click:Connect(function()
		DonationController.Toggle()
	end)

	-- Modal panel (hidden until opened).
	panel = Instance.new("Frame")
	panel.Name = "DonationPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(DonationConfig.UI.DonationPanelSize.X, DonationConfig.UI.DonationPanelSize.Y)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 20
	panel.Parent = parent
	styleCorner(panel, 14)

	-- Keep it from overflowing small screens; it stays centered and tappable.
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = DonationConfig.UI.DonationPanelSize
	sizeConstraint.Parent = panel
	-- Uniformly scale the whole panel down to fit small/phone viewports (never up past
	-- 1), so this fixed-layout panel stays fully on-screen without reworking children.
	UIFit.Fit(panel, DonationConfig.UI.DonationPanelSize.X, DonationConfig.UI.DonationPanelSize.Y)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 14)
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = DonationConfig.Text.PanelTitle
	title.ZIndex = 21
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.Position = UDim2.new(0.5, 0, 0, 42)
	subtitle.Size = UDim2.new(1, -40, 0, 20)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 14
	subtitle.TextWrapped = true
	subtitle.TextColor3 = Color3.fromRGB(180, 180, 195)
	subtitle.Text = DonationConfig.Text.PanelSubtitle
	subtitle.ZIndex = 21
	subtitle.Parent = panel

	personalLabel = Instance.new("TextLabel")
	personalLabel.Name = "PersonalStat"
	personalLabel.BackgroundTransparency = 1
	personalLabel.Position = UDim2.fromOffset(0, 70)
	personalLabel.Size = UDim2.new(1, 0, 0, 22)
	personalLabel.Font = Enum.Font.GothamMedium
	personalLabel.TextSize = 16
	personalLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
	personalLabel.Text = DonationConfig.Text.PersonalStatPrefix .. " 0"
	personalLabel.ZIndex = 21
	personalLabel.Parent = panel

	-- Amount grid.
	local grid = Instance.new("Frame")
	grid.Name = "AmountGrid"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(16, 100)
	grid.Size = UDim2.new(1, -32, 0, 200)
	grid.ZIndex = 21
	grid.Parent = panel
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.5, -8, 0, 46)
	gridLayout.CellPadding = UDim2.fromOffset(16, 10)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	for _, amount in ipairs(DonationConfig.DonationAmounts) do
		table.insert(amountButtons, makeAmountButton(amount, grid))
	end

	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.BackgroundTransparency = 1
	statusLabel.AnchorPoint = Vector2.new(0.5, 1)
	statusLabel.Position = UDim2.new(0.5, 0, 1, -52)
	statusLabel.Size = UDim2.new(1, -32, 0, 22)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 14
	statusLabel.TextWrapped = true
	statusLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
	statusLabel.Text = ""
	statusLabel.ZIndex = 21
	statusLabel.Parent = panel

	-- Top Donors button (opens the detailed leaderboard).
	local topDonors = Instance.new("TextButton")
	topDonors.Name = "TopDonorsButton"
	topDonors.AnchorPoint = Vector2.new(0, 1)
	topDonors.Position = UDim2.new(0, 16, 1, -12)
	topDonors.Size = UDim2.new(0.5, -20, 0, 34)
	topDonors.BackgroundColor3 = Color3.fromRGB(60, 60, 74)
	topDonors.Font = Enum.Font.GothamBold
	topDonors.TextSize = 15
	topDonors.TextColor3 = Color3.fromRGB(255, 255, 255)
	topDonors.Text = DonationConfig.Text.TopDonorsButton
	topDonors.ZIndex = 21
	topDonors.Parent = panel
	styleCorner(topDonors, 8)
	topDonors.MouseButton1Click:Connect(function()
		if leaderboardController then
			leaderboardController.Open()
		end
	end)

	-- Close button.
	local close = Instance.new("TextButton")
	close.Name = "CloseButton"
	close.AnchorPoint = Vector2.new(1, 1)
	close.Position = UDim2.new(1, -16, 1, -12)
	close.Size = UDim2.new(0.5, -20, 0, 34)
	close.BackgroundColor3 = Color3.fromRGB(44, 44, 54)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 15
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.Text = "Close"
	close.ZIndex = 21
	close.Parent = panel
	styleCorner(close, 8)
	close.MouseButton1Click:Connect(function()
		DonationController.Close()
	end)
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function renderPersonal(state)
	local total = 0
	if state and type(state.donation) == "table" then
		total = state.donation.robuxDonatedLifetime or 0
	end
	personalLabel.Text = DonationConfig.Text.PersonalStatPrefix .. " " .. NumberFormatter.FormatRobux(total)
end

local function flashStatus(text: string, color: Color3)
	statusLabel.Text = text
	statusLabel.TextColor3 = color
	statusLabel.TextTransparency = 0
	TweenService:Create(statusLabel, TweenInfo.new(3, Enum.EasingStyle.Linear), { TextTransparency = 1 }):Play()
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function DonationController.Open()
	if not panel then
		return
	end
	renderPersonal(StateController and StateController.state)
	panel.Visible = true
	-- Top of the donation funnel (developer analytics only). Server rate-limits it.
	AnalyticsDonationPanelOpened:FireServer()
end

function DonationController.Close()
	if panel then
		panel.Visible = false
	end
end

function DonationController.Toggle()
	if panel then
		if panel.Visible then
			DonationController.Close()
		else
			DonationController.Open()
		end
	end
end

-- Request a prompt for an amount. The server re-validates everything; we just lock
-- the UI optimistically and let the server's reply / notifications drive the rest.
function DonationController.RequestDonation(amount: number)
	if pending or not (StateController and StateController.ready) then
		return
	end
	setPending(true)
	statusLabel.Text = ""
	RequestDonationPrompt:FireServer(amount)
end

-- Server reply to a prompt request (DonationPromptResult).
function DonationController.OnPromptResult(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.ok then
		return -- the Roblox purchase prompt is now open; wait for its finished event
	end
	-- Rejected: re-enable and explain briefly.
	setPending(false)
	local reasons = {
		Cooldown = "Please wait a moment before donating again",
		Pending = "A donation prompt is already open",
		InvalidAmount = "That amount is not available",
		ProductNotConfigured = DonationConfig.Text.NotConfiguredText,
		ProfileNotLoaded = "Your data is still loading",
		PromptFailed = DonationConfig.Text.FailText,
	}
	flashStatus(reasons[payload.reason] or DonationConfig.Text.FailText, Color3.fromRGB(255, 150, 150))
end

-- Server-confirmed outcome (DonationNotification). Success is the ONLY place the
-- thank-you shows; the stat itself updates via the replicated `donation` state.
function DonationController.OnNotification(payload)
	if type(payload) ~= "table" then
		return
	end
	setPending(false)
	if payload.Kind == "Success" then
		flashStatus(payload.Message or "Thank you!", Color3.fromRGB(120, 255, 140))
		-- Success chime through the audio bus so it obeys the SFX / Master toggles.
		-- SuccessSoundId is empty by default, so this is a clean no-op until a human
		-- pastes a real asset id into DonationConfig.Effects.SuccessSoundId.
		AudioController.PlaySFX(DonationConfig.Effects.SuccessSoundId, { Volume = 0.6 })
		if panel and panel.Visible then
			TweenService:Create(panel, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(
					DonationConfig.UI.DonationPanelSize.X + 14,
					DonationConfig.UI.DonationPanelSize.Y + 14
				),
			}):Play()
			task.delay(0.18, function()
				if panel then
					TweenService:Create(panel, TweenInfo.new(0.12), {
						Size = UDim2.fromOffset(
							DonationConfig.UI.DonationPanelSize.X,
							DonationConfig.UI.DonationPanelSize.Y
						),
					}):Play()
				end
			end)
		end
	elseif payload.Kind == "Cancelled" then
		flashStatus(payload.Message or DonationConfig.Text.CancelText, Color3.fromRGB(230, 210, 140))
	else
		flashStatus(payload.Message or DonationConfig.Text.FailText, Color3.fromRGB(255, 150, 150))
	end
end

local function onState(state, changed)
	if changed.donation or changed.currency then
		renderPersonal(state)
	end
end

function DonationController.Init(parent: ScreenGui, stateController, leaderboard)
	StateController = stateController
	leaderboardController = leaderboard
	build(parent)
	renderPersonal(StateController.state)
	StateController.Subscribe(onState)
	pendingWatchdog()

	-- Client-side prompt completion is UI-only: it re-enables the panel and shows a
	-- cancel/fail message. It NEVER credits -- the server does that via ProcessReceipt.
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _productId, isPurchased)
		if userId ~= player.UserId then
			return
		end
		if not isPurchased then
			setPending(false)
			flashStatus(DonationConfig.Text.CancelText, Color3.fromRGB(230, 210, 140))
		end
		-- On success we wait for the server's DonationNotification (authoritative).
	end)
end

return DonationController
