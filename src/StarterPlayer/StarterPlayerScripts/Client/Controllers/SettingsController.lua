--!strict
-- SettingsController: the gear button + lightweight settings panel (Master / Music
-- / SFX on-off). It is preferences-only: it applies changes to the AudioController
-- immediately for responsiveness, then asks the server to persist them. It never
-- touches currency, inventory or any gameplay state.
--
-- Connections are wired exactly once at build time (never per open/close), so
-- opening and closing the panel any number of times grows nothing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameSettingsConfig = require(ReplicatedStorage.Modules.Configuration.GameSettingsConfig)
local AudioController = require(script.Parent.AudioController)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestUpdateSettings = Remotes:WaitForChild("RequestUpdateSettings")

local SettingsController = {}

local Text = GameSettingsConfig.Text

-- Local mirror of the persisted booleans. Seeded from server state, updated on
-- every local toggle, and reconciled whenever the server echoes a settings delta.
local localSettings = {
	masterEnabled = GameSettingsConfig.Audio.DefaultMasterOn,
	musicEnabled = GameSettingsConfig.Audio.DefaultMusicOn,
	sfxEnabled = GameSettingsConfig.Audio.DefaultSFXOn,
	-- Phase 6 visibility preferences (hide UI only; the server still records the feed).
	showDonationFeed = true,
	showReturnSummary = true,
}

-- The persisted keys this panel owns (audio + Phase 6 visibility). Both commit() and
-- the server-echo reconcile iterate this list so a new toggle is added in one place.
local MANAGED_KEYS = {
	"masterEnabled",
	"musicEnabled",
	"sfxEnabled",
	"showDonationFeed",
	"showReturnSummary",
}

local panel: Frame? = nil
local toggleButtons: { [string]: TextButton } = {}

local ON_COLOR = Color3.fromRGB(70, 170, 90)
local OFF_COLOR = Color3.fromRGB(90, 60, 60)

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function refreshToggleVisual(key: string)
	local button = toggleButtons[key]
	if not button then
		return
	end
	local on = localSettings[key] == true
	button.Text = on and Text.On or Text.Off
	button.BackgroundColor3 = on and ON_COLOR or OFF_COLOR
end

local function refreshAll()
	for key in pairs(toggleButtons) do
		refreshToggleVisual(key)
	end
end

-- Apply the current mirror to audio and push it to the server to persist. The full
-- toggle set is sent each time so a rate-limited intermediate update never leaves
-- the saved state stale.
local function commit()
	AudioController.ApplySettings(localSettings)
	local payload = {}
	for _, key in ipairs(MANAGED_KEYS) do
		payload[key] = localSettings[key]
	end
	RequestUpdateSettings:FireServer(payload)
end

local function onToggle(key: string)
	localSettings[key] = not localSettings[key]
	refreshToggleVisual(key)
	commit()
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function makeToggleRow(parent: Instance, key: string, labelText: string, order: number)
	local row = Instance.new("Frame")
	row.Name = "Row_" .. key
	row.Size = UDim2.new(1, -24, 0, 44)
	row.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(12, 0)
	label.Size = UDim2.new(1, -110, 1, 0)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(235, 235, 240)
	label.Text = labelText
	label.Parent = row

	local button = Instance.new("TextButton")
	button.Name = "Toggle"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.fromOffset(84, 32)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.AutoButtonColor = true
	button.Parent = row
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = button

	toggleButtons[key] = button
	button.MouseButton1Click:Connect(function()
		onToggle(key)
	end)
	refreshToggleVisual(key)
end

local function build(parent: ScreenGui)
	-- Gear button, top-right, sized for a comfortable touch target. It sits in its own
	-- slot to the LEFT of the Phase 3 Leaderboard (1,-144) and Donate (1,-16) buttons
	-- so the three never overlap: [Settings][Leaderboard][Donate], right-aligned, ~8px
	-- gaps. Vertically centered on the same line as those 34px-tall buttons.
	local gear = Instance.new("TextButton")
	gear.Name = "SettingsGear"
	gear.AnchorPoint = Vector2.new(1, 0)
	gear.Position = UDim2.new(1, -284, 0, 4)
	gear.Size = UDim2.fromOffset(GameSettingsConfig.UI.MinTouchPx, GameSettingsConfig.UI.MinTouchPx)
	gear.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
	gear.Font = Enum.Font.GothamBold
	gear.TextSize = 20
	gear.TextColor3 = Color3.fromRGB(235, 235, 240)
	gear.Text = "[=]" -- plain glyph placeholder for a gear icon (no emoji)
	gear.ZIndex = 10
	gear.Parent = parent
	local gearCorner = Instance.new("UICorner")
	gearCorner.CornerRadius = UDim.new(0, 8)
	gearCorner.Parent = gear

	-- The panel itself, centered and non-blocking (it does not cover the whole
	-- screen, so gameplay behind it stays reachable once closed).
	local frame = Instance.new("Frame")
	frame.Name = "SettingsPanel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = GameSettingsConfig.UI.SettingsPanelSize
	frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 11
	frame.Parent = parent
	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 14)
	frameCorner.Parent = frame
	-- Never exceed a small viewport; keeps the panel fully on-screen on phones.
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(GameSettingsConfig.UI.SettingsPanelSize.X.Offset, GameSettingsConfig.UI.SettingsPanelSize.Y.Offset)
	sizeConstraint.MinSize = Vector2.new(260, 220)
	sizeConstraint.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 12)
	title.Size = UDim2.new(1, -32, 0, 26)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = Text.SettingsTitle
	title.ZIndex = 11
	title.Parent = frame

	local rows = Instance.new("ScrollingFrame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.Position = UDim2.fromOffset(12, 46)
	rows.Size = UDim2.new(1, -24, 1, -110)
	rows.ScrollBarThickness = 6
	rows.CanvasSize = UDim2.new(0, 0, 0, 0)
	rows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rows.ZIndex = 11
	rows.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rows

	makeToggleRow(rows, "masterEnabled", Text.MasterLabel, 1)
	makeToggleRow(rows, "musicEnabled", Text.MusicLabel, 2)
	makeToggleRow(rows, "sfxEnabled", Text.SFXLabel, 3)
	makeToggleRow(rows, "showDonationFeed", Text.DonationFeedLabel, 4)
	makeToggleRow(rows, "showReturnSummary", Text.ReturnSummaryLabel, 5)

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -12)
	close.Size = UDim2.new(1, -24, 0, GameSettingsConfig.UI.MinTouchPx)
	close.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.Text = Text.Close
	close.ZIndex = 11
	close.Parent = frame
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 10)
	closeCorner.Parent = close

	panel = frame

	gear.MouseButton1Click:Connect(function()
		frame.Visible = not frame.Visible
	end)
	close.MouseButton1Click:Connect(function()
		frame.Visible = false
	end)
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Reconcile from an authoritative settings table (initial snapshot or server echo).
local function applyServerSettings(settings)
	if type(settings) ~= "table" then
		return
	end
	for _, key in ipairs(MANAGED_KEYS) do
		if type(settings[key]) == "boolean" then
			localSettings[key] = settings[key]
		end
	end
	refreshAll()
	AudioController.ApplySettings(localSettings)
end

local function onState(state, changed)
	if changed.settings then
		applyServerSettings(state.settings)
	end
end

function SettingsController.Init(parent: ScreenGui, StateController)
	build(parent)
	-- If the snapshot already arrived before we built, apply it now.
	if StateController.state and StateController.state.settings then
		applyServerSettings(StateController.state.settings)
	end
	StateController.Subscribe(onState)
end

return SettingsController
