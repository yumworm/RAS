--!strict
-- StandardRevealHandler: the reveal path for Common through Legendary. It is the
-- deliberate opposite of a cinematic: the winning card snaps to its final state
-- instantly, with zero scale/bounce/flip/fade, no task.wait for drama, no custom
-- banner, and no per-streamer voice line. Only a shared rarity color and a shared
-- rarity chime. Speed and clarity are the feature here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = ReplicatedStorage.Modules.Configuration
local RarityConfig = require(Configuration.RarityConfig)
local PresentationConfig = require(Configuration.PresentationConfig)
local StreamerDatabase = require(Configuration.StreamerDatabase)

local AudioController = require(script.Parent.AudioController)

local StandardRevealHandler = {}

-- The shared rarity chime, routed through the SFX bus so the Master/SFX toggles
-- apply. AudioController skips placeholder/empty ids and owns instance cleanup.
local function playChime(rarityName: string)
	AudioController.PlaySFX(PresentationConfig.RarityChimes[rarityName], { Volume = 0.5 })
end

-- view: the shared reveal surface owned by SpinController (see its Init).
-- result: the authoritative server payload (streamerId, rarity, ...).
function StandardRevealHandler.Reveal(view, result)
	local streamer = StreamerDatabase.Get(result.streamerId)
	local rarity = RarityConfig.Get(result.rarity)

	-- Kill any anticipation leftovers so the winner card is static, not mid-motion.
	view.stopRainbow()
	view.cancelWinnerTweens()

	-- Snap the card to its final state. No TweenService anywhere on this path.
	view.card.Size = view.defaultCardSize
	view.card.BackgroundColor3 = rarity.Color
	view.name.Text = streamer and streamer.name or "Unknown"
	view.rarity.Text = rarity.DisplayName

	-- No glow flourish on Standard; make sure any previous glow is hidden.
	view.glow.BackgroundTransparency = 1

	playChime(result.rarity)
end

return StandardRevealHandler
