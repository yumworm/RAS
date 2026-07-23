--!strict
-- FlagshipRevealHandler: the premium reveal path for Mythic and Secret only. It
-- takes over the screen for a bounded, cinematic moment: input locked, custom
-- banner frame, an animated sequence, a signature sound, and a particle burst,
-- then it returns control cleanly.
--
-- Hard guarantees:
--   * Input is always unlocked again, even if the sequence errors or overruns
--     (pcall + a MaxSequenceSeconds deadline).
--   * Every temporary instance / connection is tracked and destroyed, so a second
--     Flagship pull never inherits leftovers from the first.
--   * Missing required asset FIELDS fall back to the Standard path (never a
--     soft-lock). Individual placeholder ids degrade gracefully (skip the image,
--     fall back to the rarity chime) while the sequence still runs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Configuration = ReplicatedStorage.Modules.Configuration
local RarityConfig = require(Configuration.RarityConfig)
local PresentationConfig = require(Configuration.PresentationConfig)
local StreamerDatabase = require(Configuration.StreamerDatabase)

local StandardRevealHandler = require(script.Parent.StandardRevealHandler)

local FlagshipRevealHandler = {}

-- Everything spawned by the current reveal, so it can be torn down on completion,
-- timeout, error, or the start of the next reveal.
local activeTweens: { Tween } = {}
local activeParticles: { Instance } = {}
local rainbowConnection: RBXScriptConnection? = nil

local function trackTween(tween: Tween): Tween
	table.insert(activeTweens, tween)
	return tween
end

local function cleanup(view)
	if rainbowConnection then
		rainbowConnection:Disconnect()
		rainbowConnection = nil
	end
	for _, tween in ipairs(activeTweens) do
		pcall(function()
			tween:Cancel()
		end)
	end
	table.clear(activeTweens)
	for _, inst in ipairs(activeParticles) do
		if inst and inst.Parent then
			inst:Destroy()
		end
	end
	table.clear(activeParticles)
	if view then
		view.card.Size = view.defaultCardSize
		view.glow.BackgroundTransparency = 1
	end
end

-- All required asset FIELDS present (non-nil)? Placeholder ids still count as
-- present; only a truly absent field routes to the Standard fallback.
local function hasRequiredFields(assets): boolean
	if type(assets) ~= "table" then
		return false
	end
	return assets.RevealAnimId ~= nil
		and assets.RevealSoundId ~= nil
		and assets.ParticlePreset ~= nil
		and assets.CustomBannerId ~= nil
end

local function playFlagshipSound(assets, rarityName: string)
	-- Prefer the streamer's signature sound; fall back to the rarity chime; else
	-- stay silent. Never hard-depend on a real asset existing.
	local id = assets and assets.RevealSoundId
	if not PresentationConfig.IsAssetSet(id) then
		id = PresentationConfig.RarityChimes[rarityName]
	end
	if not PresentationConfig.IsAssetSet(id) then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = 0.6
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(8, function()
		if sound and sound.Parent then
			sound:Destroy()
		end
	end)
	sound:Play()
end

local function particleBurst(view, color: Color3, rainbow: boolean, preset: string)
	-- Preset only nudges density/spread; all styles are procedural so a missing
	-- asset pack can never break the burst.
	local count = if preset == "SecretStorm" then 22 else 16
	for i = 1, count do
		local p = Instance.new("Frame")
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = UDim2.fromScale(0.5, 0.5)
		p.Size = UDim2.fromOffset(8, 8)
		p.BackgroundColor3 = rainbow and Color3.fromHSV(i / count, 1, 1) or color
		p.BorderSizePixel = 0
		p.ZIndex = 6
		p.Parent = view.card
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = p
		table.insert(activeParticles, p)

		local angle = (i / count) * math.pi * 2
		local distance = 110 + math.random(0, 60)
		trackTween(
			TweenService:Create(
				p,
				TweenInfo.new(0.6 + math.random() * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					Position = UDim2.new(0.5, math.cos(angle) * distance, 0.5, math.sin(angle) * distance),
					BackgroundTransparency = 1,
				}
			)
		):Play()
		Debris:AddItem(p, 1.2)
	end
end

-- The cinematic timeline. Uses tweens freely (Flagship is allowed motion). Kept
-- comfortably under MaxSequenceSeconds; the caller enforces a hard deadline too.
local function runSequence(view, result)
	local streamer = StreamerDatabase.Get(result.streamerId)
	local rarity = RarityConfig.Get(result.rarity)
	local assets = result.assets or {}
	local preset = PresentationConfig.ResolveParticlePreset(assets.ParticlePreset)

	-- Card content (the "custom banner" frame is procedural in dev; a real
	-- CustomBannerId would drive an ImageLabel here in a later content pass).
	view.card.BackgroundColor3 = rarity.Color
	view.name.Text = streamer and streamer.name or "Unknown"
	view.rarity.Text = rarity.DisplayName

	-- Secret gets the animated rainbow chrome.
	if rarity.IsRainbow then
		rainbowConnection = RunService.Heartbeat:Connect(function()
			view.card.BackgroundColor3 = Color3.fromHSV((os.clock() * 0.5) % 1, 0.85, 1)
		end)
	end

	-- Sound + glow + particles kick off together for impact.
	playFlagshipSound(assets, result.rarity)

	view.glow.BackgroundColor3 = rarity.Color
	view.glow.BackgroundTransparency = 0.25
	trackTween(
		TweenService:Create(
			view.glow,
			TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		)
	):Play()

	particleBurst(view, rarity.Color, rarity.IsRainbow == true, preset)

	-- A confident scale-in, then settle. Bounded, intentional motion.
	local pop = trackTween(
		TweenService:Create(
			view.card,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(view.defaultCardSize.X.Offset + 44, view.defaultCardSize.Y.Offset + 30) }
		)
	)
	pop:Play()
	pop.Completed:Wait()
	trackTween(
		TweenService:Create(
			view.card,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = view.defaultCardSize }
		)
	):Play()

	-- Hold the milestone beat, then let the glow finish fading.
	task.wait(1.4)
end

-- Entry point. Routes to Standard if required fields are absent; otherwise runs
-- the cinematic under an input lock and a hard timeout.
function FlagshipRevealHandler.Reveal(view, result)
	-- Tear down any leftovers from a previous reveal before starting a new one.
	cleanup(view)

	if PresentationConfig.Flagship.FallbackToStandardOnMissingAssets and not hasRequiredFields(result.assets) then
		warn("[RollAStream] Flagship assets missing required fields; falling back to Standard reveal")
		StandardRevealHandler.Reveal(view, result)
		return
	end

	if PresentationConfig.Flagship.InputLock then
		view.setInputLocked(true)
	end

	local finished = false
	task.spawn(function()
		local ok, err = pcall(runSequence, view, result)
		if not ok then
			warn("[RollAStream] Flagship reveal sequence error: " .. tostring(err))
		end
		finished = true
	end)

	-- Hard deadline so a hung/overrunning sequence can never freeze the UI.
	local deadline = os.clock() + PresentationConfig.Flagship.MaxSequenceSeconds
	while not finished and os.clock() < deadline do
		task.wait()
	end

	cleanup(view)
	view.setInputLocked(false)
end

return FlagshipRevealHandler
