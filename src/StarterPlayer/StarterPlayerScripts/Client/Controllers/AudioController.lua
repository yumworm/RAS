--!strict
-- AudioController: the single client audio bus. Everything that makes sound goes
-- through here so the Master / Music / SFX settings actually mean something:
--   * One looping BGM Sound (skipped cleanly if no SoundId is configured).
--   * PlaySFX(): fire-and-forget one-shots that are suppressed when SFX (or Master)
--     is off, and always destroyed after playback so instances never accumulate.
--
-- Bus rules (match the settings semantics):
--   * Master off  -> nothing is audible (BGM stopped, SFX suppressed).
--   * Music off    -> BGM stopped; SFX still play if SFX + Master are on.
--   * SFX off      -> one-shots suppressed; BGM keeps playing if Music + Master on.
--
-- Before settings arrive from the server the bus defaults to "all on" so early
-- reveal sounds are never wrongly swallowed; ApplySettings then reconciles it.
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameSettingsConfig = require(ReplicatedStorage.Modules.Configuration.GameSettingsConfig)

local AudioController = {}

local current = {
	masterEnabled = true,
	musicEnabled = true,
	sfxEnabled = true,
}

local bgmSound: Sound? = nil
local initialized = false

-- An id counts as "set" only if it is a real asset string. Placeholder 0 / empty
-- ids simply mean "no sound" so a dev build with no audio stays silent, never errors.
local function isAssetSet(id: any): boolean
	return type(id) == "string" and id ~= "" and id ~= "rbxassetid://0"
end

local function clamp01(v: any, default: number): number
	if type(v) ~= "number" or v ~= v then
		return default
	end
	return math.clamp(v, 0, 1)
end

-- Should the BGM be audible right now? Requires Master AND Music both on.
local function bgmShouldPlay(): boolean
	return current.masterEnabled and current.musicEnabled
end

-- Should one-shot SFX be audible right now? Requires Master AND SFX both on.
local function sfxShouldPlay(): boolean
	return current.masterEnabled and current.sfxEnabled
end

local function refreshBgm()
	if not bgmSound then
		return
	end
	if bgmShouldPlay() then
		if not bgmSound.IsPlaying then
			bgmSound:Play()
		end
	else
		if bgmSound.IsPlaying then
			bgmSound:Stop()
		end
	end
end

-- Build the single looping BGM Sound. No-op (and no error) when no id is set.
function AudioController.Init()
	if initialized then
		return
	end
	initialized = true

	local audio = GameSettingsConfig.Audio
	if isAssetSet(audio.BgmSoundId) then
		local sound = Instance.new("Sound")
		sound.Name = "BGM"
		sound.SoundId = audio.BgmSoundId
		sound.Looped = audio.BgmLoop ~= false
		sound.Volume = clamp01(audio.BgmVolume, 0.3)
		sound.Parent = SoundService
		bgmSound = sound
	end
	refreshBgm()
end

-- Reconcile the bus with the player's persisted settings. Cheap + idempotent, so
-- it is safe to call on every settings delta and on every local toggle.
function AudioController.ApplySettings(settings: any)
	if type(settings) ~= "table" then
		return
	end
	if type(settings.masterEnabled) == "boolean" then
		current.masterEnabled = settings.masterEnabled
	end
	if type(settings.musicEnabled) == "boolean" then
		current.musicEnabled = settings.musicEnabled
	end
	if type(settings.sfxEnabled) == "boolean" then
		current.sfxEnabled = settings.sfxEnabled
	end
	refreshBgm()
end

-- Fire-and-forget a 2D one-shot through the SFX bus. Suppressed entirely when SFX
-- or Master is off. Placeholder/empty ids are skipped. The Sound is destroyed on
-- Ended, with a timeout safety net in case Ended never fires (bad/instant id).
function AudioController.PlaySFX(soundId: any, props: { Volume: number? }?)
	if not sfxShouldPlay() then
		return
	end
	if not isAssetSet(soundId) then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = clamp01(props and props.Volume, GameSettingsConfig.Audio.SfxDefaultVolume)
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

-- Full teardown (e.g. controller reload). Stops and destroys the BGM instance.
function AudioController.Destroy()
	if bgmSound then
		bgmSound:Destroy()
		bgmSound = nil
	end
	initialized = false
end

return AudioController
