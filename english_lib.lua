-- Kizrak
local english = require('locale-server.english')
local russian = require('locale-server.russian')

local sb = serpent.block

--- TODO: time for a library soon...
local function sbs(obj) -- luacheck: ignore 211
	local s = sb(obj):gsub("%s+", " ")
	return s
end

local M = {}

-- lua global
local englishMissingSpamGuard = {}

local function get_global_map_tag_language()
	return settings.startup["global-map-tag-language"].value
end


local function get_language_server_file()
	local global_map_tag_language = get_global_map_tag_language()

	if global_map_tag_language=="en" then
		return english
	elseif global_map_tag_language=="ru" then
		return russian
	else
		local msg = "Unknown language!" .. str(global_map_tag_language)
		log(msg)
		error(msg)
	end
end


function M.resource(resource)
	local i18n_file_data = get_language_server_file()

	local i18n = i18n_file_data[resource]

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
