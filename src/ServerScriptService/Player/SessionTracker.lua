--!strict
-- SessionTracker: per-join session metrics. Session values reset every join;
-- lifetime values (in the saved profile) only ever increase. Session state lives
-- in Runtime so it's never saved.
local Server = script.Parent.Parent
local Runtime = require(Server.Core.Runtime)
local StateSync = require(Server.Core.StateSync)

local SessionTracker = {}
local Services: any

function SessionTracker.Init(services)
	Services = services
end

function SessionTracker.Start(userId: number)
	local runtime = Runtime.Get(userId)
	if not runtime then
		return
	end
	runtime.session = {
		startedAt = os.clock(),
		earnings = 0,
		spins = 0,
		playtime = 0,
		streamersPulled = 0,
		highestIncome = runtime.incomePerSecond or 0,
		highestCurrency = Services.EconomyService.GetCurrency(userId),
	}
end

-- Called by EconomyService whenever money is earned.
function SessionTracker.OnEarned(userId: number, gained: number, currentCurrency: number)
	local runtime = Runtime.Get(userId)
	local session = runtime and runtime.session
	if not session then
		return
	end
	session.earnings += gained
	if currentCurrency > session.highestCurrency then
		session.highestCurrency = currentCurrency
	end
end

-- Called when a spin awards a streamer.
function SessionTracker.OnSpin(userId: number)
	local runtime = Runtime.Get(userId)
	local session = runtime and runtime.session
	if not session then
		return
	end
	session.spins += 1
	session.streamersPulled += 1
end

-- Called once per income tick to advance both session and lifetime playtime and
-- refresh the session income high-water mark.
function SessionTracker.Tick(userId: number, dt: number)
	local runtime = Runtime.Get(userId)
	local session = runtime and runtime.session
	if not session then
		return
	end
	session.playtime += dt

	local profile = Services.ProfileService.Get(userId)
	if profile then
		profile.stats.totalPlayTime += dt
	end
	if runtime.incomePerSecond > session.highestIncome then
		session.highestIncome = runtime.incomePerSecond
	end

	-- Phase 6: replicate the live session summary so the Stats panel shows current
	-- session spins / earnings / playtime. Piggybacks on the once-per-tick FlushState
	-- the income loop already performs, so it adds no extra network round trip.
	StateSync.Mark(userId, "session", SessionTracker.GetSummary(userId))
end

function SessionTracker.GetSummary(userId: number)
	local runtime = Runtime.Get(userId)
	local session = runtime and runtime.session
	if not session then
		return { earnings = 0, spins = 0, playtime = 0, streamersPulled = 0, highestIncome = 0, highestCurrency = 0 }
	end
	return {
		earnings = session.earnings,
		spins = session.spins,
		playtime = session.playtime,
		streamersPulled = session.streamersPulled,
		highestIncome = session.highestIncome,
		highestCurrency = session.highestCurrency,
	}
end

function SessionTracker.End(userId: number)
	-- Lifetime playtime is accumulated per-tick already; nothing to roll up here.
	-- Hook kept for symmetry / future session-summary rewards.
end

return SessionTracker
