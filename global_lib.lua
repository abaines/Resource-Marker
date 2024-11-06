-- Kizrak
local i18n = require('english_lib')

local sb = serpent.block

--- TODO: time for a library soon...
local function sbs(obj) -- luacheck: ignore 211
	local s = sb(obj):gsub("%s+", " ")
	return s
end

local M = {}

-- lua storage
local _ICON_TYPES_ = "iconTypes" -- storage root key

local _RESOURCE_MAP_ = "resourceMap" -- storage root key

function M.getGlobalMapLocationData(surface, x, y)
	local name = surface.name

	storage[_RESOURCE_MAP_] = storage[_RESOURCE_MAP_] or {}
	storage[_RESOURCE_MAP_][name] = storage[_RESOURCE_MAP_][name] or {}
	storage[_RESOURCE_MAP_][name][x] = storage[_RESOURCE_MAP_][name][x] or {}
	storage[_RESOURCE_MAP_][name][x][y] = storage[_RESOURCE_MAP_][name][x][y] or {}
	storage[_RESOURCE_MAP_][name][x][y].resources = storage[_RESOURCE_MAP_][name][x][y].resources or {}
	storage[_RESOURCE_MAP_][name][x][y].forces = storage[_RESOURCE_MAP_][name][x][y].forces or {}

	return storage[_RESOURCE_MAP_][name][x][y]
end

-- https://discord.com/channels/1214952937613295676/1281881163702730763/1299143136022368317

function M.calculateIconTypes()
	storage[_ICON_TYPES_] = {} -- storage root key
	for key, _ in pairs(prototypes.virtual_signal) do
		storage[_ICON_TYPES_][key] = "virtual"
	end
	for key, _ in pairs(prototypes.item) do
		storage[_ICON_TYPES_][key] = "item"
	end
	for key, _ in pairs(prototypes.fluid) do
		storage[_ICON_TYPES_][key] = "fluid"
	end

	local resourcePrototypes = prototypes.get_entity_filtered({{filter = "type", type = "resource"}})
	storage.aliases = {} -- storage root key

	for name, value in pairs(resourcePrototypes) do
		local products = value.mineable_properties.products or {}
		local sorter = function(a, b)
			return a.probability < b.probability
		end

		table.sort(products, sorter)
		-- log(sb( products ))

		for _, product in pairs(products) do
			if storage[_ICON_TYPES_][product.name] then
				storage.aliases[name] = product.name
				storage.aliases[i18n.resource(name)] = product.name
			end
		end
	end
	log("storage.aliases:\n" .. sbs(storage.aliases))
end

function M.clearGlobalResourceMapData()
	storage[_RESOURCE_MAP_] = {}
end

function M.logIconTypes()
	-- storage root keys
	-- _RESOURCE_MAP_
	-- _ICON_TYPES_
	-- aliases

	local function _logIconTypes(input_type)
		local list = {}
		for key, value in pairs(storage[_ICON_TYPES_]) do
			if value == input_type then
				table.insert(list, key)
			end
		end
		log(input_type .. "  " .. table_size(list))
	end

	-- log _ICON_TYPES_
	_logIconTypes("virtual")
	_logIconTypes("item")
	_logIconTypes("fluid")

	log("storage.aliases\n" .. sb(storage.aliases))
end

-- lua storage
local loggedMissingResources = {}

function M.calculateSignalID(resource)

	local signalID = {type = "virtual", name = "signal-dot"}

	local resourceIcon = storage.aliases[resource] -- storage root key
	if not resourceIcon then
		log("Warning: Missing resource icon alias: " .. tostring(resource))
		log("storage.aliases:\n" .. sbs(storage.aliases))
		local storage_aliases_size = table_size(storage.aliases)
		if 0 == storage_aliases_size then
			local red = {1, 0, 0}
			game.print({"errors.storage-aliases-missing"}, red)
			game.print({"errors.rebuild-data-structure"}, red)
			M.calculateIconTypes()
			local storage_aliases_size = table_size(storage.aliases) -- luacheck: ignore 421
			if 0 == storage_aliases_size then
				game.print({"errors.unable-to-repair"}, red)
				error("Unable to repair `storage.aliases` data structure.")
			else
				game.print({"errors.repair-complete"}, red)
			end
		end
	elseif storage[_ICON_TYPES_][resourceIcon] then
		signalID.type = storage[_ICON_TYPES_][resourceIcon]
		signalID.name = resourceIcon
	elseif not loggedMissingResources[resourceIcon] then
		log("Warning: Missing icon type: " .. resourceIcon)
		loggedMissingResources[resourceIcon] = true
	end

	return signalID
end

return M
