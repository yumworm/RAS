--!strict
-- Runtime: per-player runtime-only state that must NEVER be saved (sessions,
-- cached income, spin locks, event connections). Kept separate from the saved
-- profile so persistence stays clean and cleanup on leave is trivial.
local Runtime = {}

local states = {}

function Runtime.Create(userId: number)
	local state = {
		initialized = false, -- gameplay enabled only once true
		loadFailed = false, -- if true, do NOT save (avoid overwriting good data)

		incomePerSecond = 0, -- cached; recomputed by IncomeService on inventory change

		spinActive = false, -- a roll is mid-flight
		lastSpinAt = 0, -- os.clock() of last accepted spin
		lastSettingsAt = 0, -- os.clock() of last accepted settings update (rate limit)

		donationPending = 0, -- os.clock() when a donation prompt was opened (0 = none)
		lastDonationPromptAt = 0, -- os.clock() of last accepted donation prompt (cooldown)
		lastLeaderboardRequestAt = 0, -- os.clock() of last accepted board request (rate limit)

		session = nil, -- populated by SessionTracker

		connections = {}, -- RBXScriptConnections to disconnect on leave
	}
	states[userId] = state
	return state
end

function Runtime.Get(userId: number)
	return states[userId]
end

function Runtime.TrackConnection(userId: number, connection)
	local state = states[userId]
	if state then
		table.insert(state.connections, connection)
	end
	return connection
end

-- Full teardown: disconnect everything and drop the state so no references leak.
function Runtime.Destroy(userId: number)
	local state = states[userId]
	if not state then
		return
	end
	for _, connection in ipairs(state.connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(state.connections)
	states[userId] = nil
end

function Runtime.GetAll()
	return states
end

return Runtime
