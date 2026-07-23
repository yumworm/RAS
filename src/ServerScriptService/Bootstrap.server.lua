-- Bootstrap: the single server entry point. It validates content on startup,
-- wires every service into the shared registry, initializes them in dependency
-- order, and starts networking + the player lifecycle. This is the only Script in
-- the server tree; everything else is a ModuleScript it drives.
local Server = script.Parent
local Core = Server.Core
local Utilities = Server.Utilities
local Data = Server.Data
local Economy = Server.Economy
local Inventory = Server.Inventory
local PlayerFolder = Server.Player
local Networking = Server.Networking
local Donation = Server.Donation

local Services = require(Core.Services)
local Logger = require(Utilities.Logger)
local Validation = require(Utilities.Validation)

-- 1) Validate config + streamer database before anything can touch it.
-- `errors` are fatal (they gate the gacha below); `warnings` are logged only.
local errors, warnings = Validation.ValidateAll()
local gachaSafe = #errors == 0

if #warnings > 0 then
	Logger.Warn("Config", string.format("Startup validation raised %d warning(s):", #warnings))
	for _, message in ipairs(warnings) do
		Logger.Warn("Config", "  - " .. message)
	end
end

if not gachaSafe then
	Logger.Error("Config", string.format("Startup validation found %d issue(s):", #errors))
	for _, message in ipairs(errors) do
		Logger.Error("Config", "  - " .. message)
	end
	-- Fail safe: the game still boots (services fall back to safe defaults) but the
	-- gacha refuses to roll on unsafe content until the issues are fixed.
	Logger.Error("Config", "Gacha spins are DISABLED until validation passes")
else
	Logger.Info("Config", "Startup validation passed")
end

-- 2) Register every service singleton.
Services.ProfileService = require(Data.ProfileService)
Services.SaveManager = require(Data.SaveManager)
Services.EconomyService = require(Economy.EconomyService)
Services.IncomeService = require(Economy.IncomeService)
Services.InventoryService = require(Inventory.InventoryService)
Services.CollectionService = require(Inventory.CollectionService)
Services.SessionTracker = require(PlayerFolder.SessionTracker)
Services.PlayerManager = require(PlayerFolder.PlayerManager)
Services.NetworkService = require(Networking.NetworkService)
Services.DonationLeaderboard = require(Donation.DonationLeaderboard)
Services.RobuxDonationSystem = require(Donation.RobuxDonationSystem)
Services.GlobalDonationStandSystem = require(Donation.GlobalDonationStandSystem)

-- 3) Initialize (they wire dependencies via the registry, at call time).
for _, name in ipairs({
	"SaveManager",
	"EconomyService",
	"IncomeService",
	"InventoryService",
	"CollectionService",
	"SessionTracker",
	"NetworkService",
	"PlayerManager",
	"DonationLeaderboard",
	"RobuxDonationSystem",
	"GlobalDonationStandSystem",
}) do
	local service = Services[name]
	if service.Init then
		service.Init(Services)
	end
end

-- 4) Go live: hook remotes, then start the player lifecycle + loops. Gate the
-- gacha on validation so unsafe content never rolls.
Services.NetworkService.SetSpinEnabled(gachaSafe)
Services.NetworkService.Start()
Services.PlayerManager.Start()

-- 5) Donation subsystem. The stand is built first so the leaderboard's refresh loop
-- always has a board to render into; the receipt/prompt handler and board loop start
-- after it.
Services.GlobalDonationStandSystem.Start()
Services.DonationLeaderboard.Start()
Services.RobuxDonationSystem.Start()

Logger.Info("Boot", "RollAStream server started")
