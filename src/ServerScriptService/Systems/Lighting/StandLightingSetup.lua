--!strict
-- StandLightingSetup: a one-shot, idempotent lighting accent for the Phase 3 Global
-- Donation Stand. It makes the stand and its Top 100 board read clearly and stand out
-- from spawn, using the brightness/range values in GameSettingsConfig.Lighting.
--
-- It adds a warm PointLight at the stand base and a SurfaceLight on the board face.
-- Both are name-guarded, so running it more than once -- or over a map-placed stand
-- that already carries them -- never stacks lights (Section 12.5 / Task 9 DoD). It
-- runs once at server start (never per player join), changes no gameplay, and rebuilds
-- no geometry: if the stand or a part is missing it is a clean no-op.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameSettingsConfig = require(ReplicatedStorage.Modules.Configuration.GameSettingsConfig)

local Server = script.Parent.Parent.Parent
local Logger = require(Server.Utilities.Logger)

local StandLightingSetup = {}

local POINT_LIGHT_NAME = "StandAccentLight"
local BOARD_LIGHT_NAME = "BoardAccentLight"

local Lighting = GameSettingsConfig.Lighting

local function ensurePointLight(base: BasePart)
	if base:FindFirstChild(POINT_LIGHT_NAME) then
		return -- already lit; do not stack
	end
	local light = Instance.new("PointLight")
	light.Name = POINT_LIGHT_NAME
	light.Brightness = Lighting.StandPointLightBrightness
	light.Range = Lighting.StandPointLightRange
	light.Color = Color3.fromRGB(255, 244, 214) -- warm white, not neon
	light.Shadows = true
	light.Parent = base
end

local function ensureBoardLight(board: BasePart)
	if board:FindFirstChild(BOARD_LIGHT_NAME) then
		return -- already lit; do not stack
	end
	local light = Instance.new("SurfaceLight")
	light.Name = BOARD_LIGHT_NAME
	light.Face = Enum.NormalId.Front -- the board renders its SurfaceGui on Front
	light.Brightness = Lighting.BoardSurfaceLightBrightness
	light.Range = 14
	light.Angle = 90
	light.Color = Color3.fromRGB(235, 235, 255) -- cool, keeps the board readable
	light.Parent = board
end

-- Apply the accents to whatever stand is in the world (runtime-built or map-placed).
-- Safe no-op when the stand or its parts are absent.
function StandLightingSetup.Apply()
	local area = Workspace:FindFirstChild("DonationArea")
	local stand = area and area:FindFirstChild("GlobalDonationStand")
	if not stand then
		return
	end

	local base = stand:FindFirstChild("InteractPart", true)
	if not (base and base:IsA("BasePart")) then
		base = stand:FindFirstChildWhichIsA("BasePart")
	end
	if base and base:IsA("BasePart") then
		ensurePointLight(base)
	end

	local board = stand:FindFirstChild("Board", true) or stand:FindFirstChild("BoardPart", true)
	if board and board:IsA("BasePart") then
		ensureBoardLight(board)
	end

	Logger.Info("Lighting", "Global Donation Stand lighting accents ensured")
end

return StandLightingSetup
