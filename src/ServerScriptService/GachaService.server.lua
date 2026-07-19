-- Phase 1 server: owns the spin roll, per-player income accrual, and leaderstats/save data.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage.Modules
local StreamerData = require(Modules.StreamerData)
local RarityConfig = require(Modules.RarityConfig)
local GameConfig = require(Modules.GameConfig)
local WeightedSpin = require(Modules.WeightedSpin)

local Remotes = ReplicatedStorage.Remotes
local SpinRequest = Remotes.SpinRequest
local SpinResult = Remotes.SpinResult

local PlayerDataStore = DataStoreService:GetDataStore("RollAStream_Phase1")

-- player.UserId -> { currency, owned = { [streamerId] = count }, incomePerSecond, lastSpinAt }
local PlayerData = {}

local function computeIncomePerSecond(owned)
	local total = 0
	for streamerId, count in pairs(owned) do
		local streamer = StreamerData.GetById(streamerId)
		if streamer and count > 0 then
			local tier = RarityConfig.Tiers[streamer.rarity_tier]
			total += streamer.base_income * tier.IncomeMultiplier * count
		end
	end
	return total
end

local function loadPlayerData(player)
	local saved
	local ok, err = pcall(function()
		saved = PlayerDataStore:GetAsync("Player_" .. player.UserId)
	end)
	if not ok then
		warn(("[GachaService] Failed to load data for %s: %s"):format(player.Name, tostring(err)))
	end

	local owned = {}
	if saved and saved.owned then
		for streamerId, count in pairs(saved.owned) do
			owned[tonumber(streamerId)] = count
		end
	end

	return {
		currency = (saved and saved.currency) or GameConfig.StartingCurrency,
		owned = owned,
		incomePerSecond = computeIncomePerSecond(owned),
		lastSpinAt = 0,
	}
end

local function savePlayerData(player)
	local data = PlayerData[player.UserId]
	if not data then
		return
	end

	local ok, err = pcall(function()
		PlayerDataStore:SetAsync("Player_" .. player.UserId, {
			currency = data.currency,
			owned = data.owned,
		})
	end)
	if not ok then
		warn(("[GachaService] Failed to save data for %s: %s"):format(player.Name, tostring(err)))
	end
end

local function buildLeaderstats(player, data)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local cash = Instance.new("NumberValue")
	cash.Name = GameConfig.CurrencyName
	cash.Value = data.currency
	cash.Parent = leaderstats

	leaderstats.Parent = player
end

local function buildInventorySnapshot(data)
	local snapshot = {}
	for streamerId, count in pairs(data.owned) do
		snapshot[#snapshot + 1] = { id = streamerId, count = count }
	end
	return snapshot
end

Players.PlayerAdded:Connect(function(player)
	local data = loadPlayerData(player)
	PlayerData[player.UserId] = data
	buildLeaderstats(player, data)
end)

Players.PlayerRemoving:Connect(function(player)
	savePlayerData(player)
	PlayerData[player.UserId] = nil
end)

game:BindToClose(function()
	if RunService:IsStudio() then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		savePlayerData(player)
	end
end)

SpinRequest.OnServerEvent:Connect(function(player)
	local data = PlayerData[player.UserId]
	if not data then
		return
	end

	local now = os.clock()
	if now - data.lastSpinAt < GameConfig.SpinCooldown then
		return
	end
	data.lastSpinAt = now

	local winner = WeightedSpin.Roll(StreamerData.Streamers)
	data.owned[winner.id] = (data.owned[winner.id] or 0) + 1
	data.incomePerSecond = computeIncomePerSecond(data.owned)

	SpinResult:FireClient(player, {
		wonId = winner.id,
		owned = buildInventorySnapshot(data),
		incomePerSecond = data.incomePerSecond,
	})
end)

local incomeAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	incomeAccumulator += dt
	if incomeAccumulator < GameConfig.IncomeTickInterval then
		return
	end
	incomeAccumulator = 0

	for _, player in ipairs(Players:GetPlayers()) do
		local data = PlayerData[player.UserId]
		local leaderstats = player:FindFirstChild("leaderstats")
		if data and leaderstats and data.incomePerSecond > 0 then
			local cash = leaderstats:FindFirstChild(GameConfig.CurrencyName)
			if cash then
				data.currency = math.min(data.currency + data.incomePerSecond, GameConfig.EconomyCap)
				cash.Value = data.currency
			end
		end
	end
end)
