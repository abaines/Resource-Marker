-- Kizrak
local english = require('english')

local sb = serpent.block

--- TODO: time for a library soon...
local function sbs(obj) -- luacheck: ignore 211
	local s = sb(obj):gsub("%s+", " ")
	return s
end

local M = {}

-- lua global
local englishMissingSpamGuard = {}

function M.resource(resource)
	local i18n = english[resource]
	if not i18n and not englishMissingSpamGuard[resource] then
		local msg = "The english.lua table missing `" .. resource .. "`"
		log(msg)
		-- game.print(msg)
		englishMissingSpamGuard[resource] = true
	end
	local localResource = i18n or resource
	return localResource
end

log("english:\n" .. sbs(english))

return M
