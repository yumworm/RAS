--!strict
-- GameSettingsConfig: the single home for every Phase 5 launch-polish tuning value
-- (FTUE copy, audio bus defaults, analytics thresholds, UI sizing, lighting). Like
-- GameConfig, if a Phase 5 number or string affects behaviour or presentation it
-- lives here, not inline in a controller.
--
-- Scope guardrails baked in:
--   * Audio defaults are booleans only (Master / Music / SFX on-off). No gameplay.
--   * EconomyCapSoft mirrors the project-wide ~10T ceiling; the analytics monitor
--     only DETECTS and logs crossing it (Phase 5 never clamps or wipes).
--   * The audio settings persisted per player are booleans, not 0-1 floats.
local GameSettingsConfig = {}

-- First-Time User Experience. Subtle cues only: one non-blocking welcome toast and
-- a gentle pulse on the Spin button until the first spin. No forced tutorials.
GameSettingsConfig.FTUE = {
	WelcomeText = "Spin to collect creators. Build your income. Flex on the global donor board.",
	WelcomeDurationSec = 5, -- toast auto-fades after this many seconds
	PulseSpinIfZeroSpins = true, -- pulse only while lifetime totalSpins == 0
	PulsePeriodSec = 1.2, -- one full pulse cycle
	PulseTransparencyMin = 0.2, -- brightest point of the pulse (glow ring)
	PulseTransparencyMax = 0.7, -- dimmest point of the pulse
}

-- Central client audio bus. BgmSoundId is intentionally empty by default so CI /
-- dev boots stay silent without erroring; a human pastes a real asset id to ship.
GameSettingsConfig.Audio = {
	DefaultMasterOn = true,
	DefaultMusicOn = true,
	DefaultSFXOn = true,
	BgmSoundId = "", -- human pastes asset id; "" means "no BGM" (not an error)
	BgmVolume = 0.3, -- clamped 0-1 when applied
	BgmLoop = true,
	SfxDefaultVolume = 0.8, -- clamped 0-1 when applied
}

-- Developer-only analytics. All values are for server-side logging; nothing here is
-- shown to players. Debounces exist so logs never flood per-frame or per-open.
GameSettingsConfig.Analytics = {
	EconomyCapSoft = 1e13, -- ~10T; matches GameConfig.EconomyCap. Detect + log only.
	CapWarnDebounceSec = 60, -- min seconds between soft-cap warnings per player
	SnapshotIntervalSec = 300, -- periodic health snapshot cadence (in-memory only)
	LogDonationFunnel = true, -- gate for the Phase 3 donation funnel log hooks
	LogEconomyCap = true, -- gate for the soft-cap monitor
	LogPanelOpenRateLimitSec = 2, -- min seconds between donation-panel-open logs per player
}

-- UI sizing knobs shared by the settings panel, welcome toast, and touch targets.
GameSettingsConfig.UI = {
	SettingsPanelSize = UDim2.fromOffset(320, 260),
	ToastSize = UDim2.fromOffset(420, 60),
	MinTouchPx = 48, -- primary buttons should be at least this tall/wide on mobile
}

-- Environment lighting accents for the Global Donation Stand (Phase 3). Consumed by
-- an idempotent setup that is a no-op until the stand exists in the world.
GameSettingsConfig.Lighting = {
	StandPointLightBrightness = 1,
	StandPointLightRange = 16,
	BoardSurfaceLightBrightness = 0.6,
}

-- Player-facing copy for the settings panel. Kept here so wording changes never
-- require touching controller code. No emojis, no em dashes.
GameSettingsConfig.Text = {
	SettingsTitle = "Settings",
	MasterLabel = "Master Volume",
	MusicLabel = "Music",
	SFXLabel = "SFX",
	Close = "Close",
	On = "On",
	Off = "Off",
}

-- The canonical default for the persisted Settings subtree. ProfileTemplate reads
-- this so the audio/FTUE defaults live in exactly one place. Booleans only.
function GameSettingsConfig.DefaultSettings()
	return {
		masterEnabled = GameSettingsConfig.Audio.DefaultMasterOn,
		musicEnabled = GameSettingsConfig.Audio.DefaultMusicOn,
		sfxEnabled = GameSettingsConfig.Audio.DefaultSFXOn,
		hasSeenWelcomeToast = false,
	}
end

-- The exact set of settings keys a client may request to change, mapped to their
-- required value type. NetworkService validates inbound updates against this so an
-- exploiter can never smuggle currency/inventory through the settings remote.
GameSettingsConfig.MutableSettingKeys = {
	masterEnabled = "boolean",
	musicEnabled = "boolean",
	sfxEnabled = "boolean",
	hasSeenWelcomeToast = "boolean",
	reducedMotion = "boolean",
}

-- Minimum seconds between accepted settings updates from one player (anti-spam).
GameSettingsConfig.SettingsUpdateRateLimitSec = 0.5

return GameSettingsConfig
