--!strict
-- FTUEController: the whole first-time experience, and nothing more. Two subtle,
-- non-blocking cues:
--   * A one-time welcome toast (first join only) that auto-fades. It sets the
--     persisted hasSeenWelcomeToast flag so it never shows again.
--   * A gentle pulse on the Spin button while lifetime totalSpins == 0, removed
--     permanently the moment the first server-confirmed spin lands.
--
-- No forced tutorial, no modal, no input block, no currency. The pulse is a single
-- looping tween on a UIStroke, so stopping it is just cancel + destroy -- there is
-- no RunService connection to leak.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameSettingsConfig = require(ReplicatedStorage.Modules.Configuration.GameSettingsConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestUpdateSettings = Remotes:WaitForChild("RequestUpdateSettings")

local FTUEController = {}

local FTUE = GameSettingsConfig.FTUE

local spinButton: TextButton? = nil
local handled = false -- first-join cues run exactly once per session

-- Pulse state (all torn down together in stopPulse).
local pulseStroke: UIStroke? = nil
local pulseTween: Tween? = nil

--------------------------------------------------------------------------------
-- Spin button pulse
--------------------------------------------------------------------------------

local function stopPulse()
	if pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
	end
	if pulseStroke then
		pulseStroke:Destroy()
		pulseStroke = nil
	end
end

local function startPulse()
	if pulseStroke or not spinButton then
		return
	end
	local stroke = Instance.new("UIStroke")
	stroke.Name = "FTUEPulse"
	stroke.Color = Color3.fromRGB(255, 240, 150)
	stroke.Thickness = 3
	stroke.Transparency = FTUE.PulseTransparencyMax
	stroke.Parent = spinButton
	pulseStroke = stroke

	local half = math.max(FTUE.PulsePeriodSec, 0.1) / 2
	local tween = TweenService:Create(
		stroke,
		TweenInfo.new(half, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = FTUE.PulseTransparencyMin }
	)
	pulseTween = tween
	tween:Play()
end

--------------------------------------------------------------------------------
-- Welcome toast
--------------------------------------------------------------------------------

local function showToast(parent: ScreenGui)
	local toast = Instance.new("Frame")
	toast.Name = "WelcomeToast"
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, 64)
	toast.Size = GameSettingsConfig.UI.ToastSize
	toast.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
	toast.BackgroundTransparency = 0.05
	toast.BorderSizePixel = 0
	toast.Active = false -- never steal input; gameplay stays interactive behind it
	toast.ZIndex = 20
	toast.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = toast
	-- Keep it fully on-screen on small phones.
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(GameSettingsConfig.UI.ToastSize.X.Offset, 120)
	sizeConstraint.MinSize = Vector2.new(240, 48)
	sizeConstraint.Parent = toast

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -24, 1, -12)
	label.Position = UDim2.fromOffset(12, 6)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 15
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(240, 240, 245)
	label.Text = FTUE.WelcomeText
	label.ZIndex = 20
	label.Parent = toast

	-- Hold, then fade the frame + text together and destroy.
	task.delay(math.max(FTUE.WelcomeDurationSec, 0.1), function()
		if not toast.Parent then
			return
		end
		local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(toast, info, { BackgroundTransparency = 1 }):Play()
		local fade = TweenService:Create(label, info, { TextTransparency = 1 })
		fade.Completed:Once(function()
			if toast.Parent then
				toast:Destroy()
			end
		end)
		fade:Play()
	end)
end

--------------------------------------------------------------------------------
-- One-time first-join logic
--------------------------------------------------------------------------------

local function runFTUE(parent: ScreenGui, state)
	if handled then
		return
	end
	local settings = state.settings
	local stats = state.stats
	if type(settings) ~= "table" or type(stats) ~= "table" then
		return -- wait until the snapshot with both has arrived
	end
	handled = true

	if not settings.hasSeenWelcomeToast then
		showToast(parent)
		-- Persist the flag so the toast is a true first-join-only event.
		RequestUpdateSettings:FireServer({ hasSeenWelcomeToast = true })
	end

	if FTUE.PulseSpinIfZeroSpins and (stats.totalSpins or 0) == 0 then
		startPulse()
	end
end

-- Called (via the bootstrap's SpinResult wiring) when a server-confirmed spin
-- lands. That is the first spin -> the pulse's job is done, permanently.
function FTUEController.OnSpinResult(_payload)
	stopPulse()
end

function FTUEController.Init(parent: ScreenGui, StateController, buttonRef: TextButton?)
	spinButton = buttonRef

	-- The snapshot may already be here; if so, act now.
	if StateController.ready and StateController.state then
		runFTUE(parent, StateController.state)
	end
	StateController.Subscribe(function(state, changed)
		if changed.settings or changed.stats then
			runFTUE(parent, state)
		end
	end)
end

return FTUEController
