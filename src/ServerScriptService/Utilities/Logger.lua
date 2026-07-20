--!strict
-- Logger: lightweight developer-only logging. Never shown to players -- these are
-- server-side prints for debugging. Toggle via GameConfig.LoggingEnabled.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Modules.Configuration.GameConfig)

local Logger = {}

local function emit(level: string, category: string, message: string)
	if not GameConfig.LoggingEnabled then
		return
	end
	local line = string.format("[RollAStream][%s][%s] %s", level, category, message)
	if level == "ERROR" then
		warn(line)
	elseif level == "WARN" then
		warn(line)
	else
		print(line)
	end
end

function Logger.Info(category: string, message: string)
	emit("INFO", category, message)
end

function Logger.Warn(category: string, message: string)
	emit("WARN", category, message)
end

function Logger.Error(category: string, message: string)
	emit("ERROR", category, message)
end

return Logger
