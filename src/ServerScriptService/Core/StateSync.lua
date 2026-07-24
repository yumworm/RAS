--!strict
-- StateSync: a per-player buffer of *what changed* since the last flush. Services
-- Mark() the specific fields they touched; NetworkService flushes and sends only
-- those to the client. This is how we avoid shipping the whole profile on every
-- tick -- currency changes every second and sends just {currency=...}; inventory
-- changes rarely and sends its (small) payload only then.
local StateSync = {}

local pending = {}

function StateSync.Mark(userId: number, key: string, value)
	local bucket = pending[userId]
	if not bucket then
		bucket = {}
		pending[userId] = bucket
	end
	bucket[key] = value
end

-- Returns the pending change table (or nil if nothing changed) and clears it.
function StateSync.Flush(userId: number)
	local bucket = pending[userId]
	if not bucket then
		return nil
	end
	pending[userId] = nil
	return bucket
end

function StateSync.Clear(userId: number)
	pending[userId] = nil
end

return StateSync
