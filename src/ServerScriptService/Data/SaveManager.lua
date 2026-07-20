--!strict
-- SaveManager: owns *when* profiles are written. Saving is always background (it
-- never blocks gameplay), never runs two writes for the same player at once, and
-- if a save is requested while one is in flight it queues exactly one more so the
-- latest data always lands. Failed writes retry with exponential backoff.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GameConfig = require(ReplicatedStorage.Modules.Configuration.GameConfig)

local Server = script.Parent.Parent
local Runtime = require(Server.Core.Runtime)
local Logger = require(Server.Utilities.Logger)

local SaveManager = {}
local Services: any

-- userId -> { saving: boolean, pending: boolean }
local saveStates = {}

function SaveManager.Init(services)
	Services = services
end

local function stateFor(userId: number)
	local st = saveStates[userId]
	if not st then
		st = { saving = false, pending = false }
		saveStates[userId] = st
	end
	return st
end

-- One save with retry/backoff. Returns true if the data is safely persisted (or
-- was intentionally skipped because the load failed and we must not overwrite).
local function attemptWithRetry(userId: number): boolean
	local runtime = Runtime.Get(userId)
	if runtime and runtime.loadFailed then
		Logger.Warn("Save", string.format("Skipping save for %d (load had failed; not overwriting)", userId))
		return true
	end

	-- In Studio the DataStore API is often disabled; don't burn ~30s of backoff on
	-- a save that can't succeed. Production keeps the full retry policy.
	local maxRetries = if RunService:IsStudio() then 1 else GameConfig.SaveMaxRetries

	for attempt = 1, maxRetries do
		if Services.ProfileService.SaveAsync(userId) then
			if attempt > 1 then
				Logger.Info("Save", string.format("Saved profile for %d (succeeded on retry %d)", userId, attempt))
			else
				Logger.Info("Save", string.format("Saved profile for %d", userId))
			end
			return true
		end
		if attempt < maxRetries then
			local delay = GameConfig.SaveRetryBaseDelay * (2 ^ (attempt - 1))
			Logger.Warn("Save", string.format("Retrying save for %d in %ds (attempt %d)", userId, delay, attempt))
			task.wait(delay)
		end
	end
	Logger.Error("Save", string.format("Save for %d failed after %d attempt(s)", userId, maxRetries))
	return false
end

-- Drains the save queue for a user: keeps saving while more saves were requested
-- mid-flight, then clears the saving flag.
local function drain(userId: number)
	local st = stateFor(userId)
	repeat
		st.pending = false
		attemptWithRetry(userId)
	until not st.pending
	st.saving = false
end

-- Non-blocking. Schedules a background save; coalesces concurrent requests.
function SaveManager.RequestSave(userId: number)
	local st = stateFor(userId)
	if st.saving then
		st.pending = true -- queue exactly one more pass with the latest data
		return
	end
	st.saving = true
	task.spawn(drain, userId)
end

-- Blocking. Requests a save and waits for the queue to fully drain. Used on
-- player leave and server shutdown where data safety beats speed.
function SaveManager.SaveNow(userId: number)
	SaveManager.RequestSave(userId)
	local st = saveStates[userId]
	while st and st.saving do
		task.wait(0.05)
	end
	saveStates[userId] = nil
end

function SaveManager.Forget(userId: number)
	saveStates[userId] = nil
end

-- Background autosave loop; started once by Bootstrap.
function SaveManager.StartAutosaveLoop()
	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveInterval)
			for _, userId in ipairs(Services.ProfileService.GetActiveUserIds()) do
				SaveManager.RequestSave(userId)
			end
		end
	end)
end

return SaveManager
