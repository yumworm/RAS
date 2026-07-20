--!strict
-- StateController: the client's read-only mirror of server state. It never invents
-- values -- it only holds what the server sent (a full snapshot on init, then
-- deltas). UI controllers subscribe and re-render from here; they don't talk to
-- the network directly.
local StateController = {}

StateController.ready = false
StateController.state = {
	currency = 0,
	income = 0,
	inventory = {}, -- server-sorted array of display rows
	collection = { collected = 0, total = 0, percentage = 0 },
	bestPull = nil,
	stats = nil,
	session = nil,
	settings = nil,
	economyCap = 0,
}

local listeners = {}

-- Subscribe(fn): fn(state, changedKeys) is called on every change. changedKeys is
-- a set (e.g. { currency = true }). Returns the fn for later use.
function StateController.Subscribe(fn)
	table.insert(listeners, fn)
	return fn
end

local function notify(changedKeys)
	for _, fn in ipairs(listeners) do
		task.spawn(fn, StateController.state, changedKeys)
	end
end

-- Apply the one-time full snapshot.
function StateController.ApplyInitial(payload)
	if type(payload) ~= "table" then
		return
	end
	local state = StateController.state
	local changed = {}
	for key, value in pairs(payload) do
		state[key] = value
		changed[key] = true
	end
	StateController.ready = true
	notify(changed)
end

-- Apply a partial delta (only the keys the server says changed).
function StateController.ApplyUpdate(payload)
	if type(payload) ~= "table" then
		return
	end
	local state = StateController.state
	local changed = {}
	for key, value in pairs(payload) do
		state[key] = value
		changed[key] = true
	end
	notify(changed)
end

return StateController
