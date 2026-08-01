--!strict
-- TableUtil: small pure helpers for data work (deep copy + schema reconcile).
local TableUtil = {}

-- Operates on arbitrary runtime shapes (DataStore payloads, config tables), so the
-- parameter is deliberately `any`: the value's shape is genuinely unknown until it
-- has been walked. Callers assign the result into their own typed locals.
function TableUtil.DeepCopy(original: any): any
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
-- `data` is untrusted (straight off a DataStore) so it is `any`; the result is
-- shaped like `template`, so the return is generic on the template's type and
-- callers keep full type information instead of an opaque table.
function TableUtil.Reconcile<T>(data: any, template: T): T
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

function TableUtil.Count(t: any): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

return TableUtil
