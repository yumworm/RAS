--!strict
-- TableUtil: small pure helpers for data work (deep copy + schema reconcile).
local TableUtil = {}

function TableUtil.DeepCopy(original)
	if type(original) ~= "table" then
		return original
	end
	local copy = {}
	for key, value in pairs(original) do
		copy[key] = TableUtil.DeepCopy(value)
	end
	return copy
end

-- Reconcile `data` against `template`, returning a fresh table shaped like the
-- template: every fixed key from the template is guaranteed present with the
-- right type; valid existing values are carried over; unknown/wrong-typed values
-- fall back to the template default.
--
-- Dynamic-keyed maps (e.g. the inventory, whose keys are streamer ids) are NOT a
-- good fit for this -- they are handled explicitly by ProfileService instead.
function TableUtil.Reconcile(data, template)
	local result = TableUtil.DeepCopy(template)
	if type(data) ~= "table" then
		return result
	end
	for key, templateValue in pairs(template) do
		local dataValue = data[key]
		if type(templateValue) == "table" then
			if type(dataValue) == "table" then
				result[key] = TableUtil.Reconcile(dataValue, templateValue)
			end
		else
			if type(dataValue) == type(templateValue) then
				result[key] = dataValue
			end
		end
	end
	return result
end

function TableUtil.Count(t): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

return TableUtil
