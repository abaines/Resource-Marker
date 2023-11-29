-- Kizrak

local i18n = require('english_lib')

local sb = serpent.block

--- TODO: time for a library soon...
local function sbs(obj) -- luacheck: ignore 211
	local s = sb(obj):gsub("%s+", " ")
	return s
end

local M = {}

-- lua global
local _ICON_TYPES_ = "iconTypes" -- global root key

local _RESOURCE_MAP_ = "resourceMap" -- global root key


function M.getGlobalMapLocationData(surface, x, y)
	local name = surface.name

	global[_RESOURCE_MAP_] = global[_RESOURCE_MAP_] or {}
	global[_RESOURCE_MAP_][name] = global[_RESOURCE_MAP_][name] or {}
	global[_RESOURCE_MAP_][name][x] = global[_RESOURCE_MAP_][name][x] or {}
	global[_RESOURCE_MAP_][name][x][y] = global[_RESOURCE_MAP_][name][x][y] or {}
	global[_RESOURCE_MAP_][name][x][y].resources = global[_RESOURCE_MAP_][name][x][y].resources or {}
	global[_RESOURCE_MAP_][name][x][y].forces = global[_RESOURCE_MAP_][name][x][y].forces or {}

	return global[_RESOURCE_MAP_][name][x][y]
end


function M.calculateIconTypes()
	global[_ICON_TYPES_] = {} -- global root key
	for key, _ in pairs(game.virtual_signal_prototypes) do
		global[_ICON_TYPES_][key] = "virtual"
	end
	for key, _ in pairs(game.item_prototypes) do
		global[_ICON_TYPES_][key] = "item"
	end
	for key, _ in pairs(game.fluid_prototypes) do
		global[_ICON_TYPES_][key] = "fluid"
	end

	local resourcePrototypes = game.get_filtered_entity_prototypes({{filter = "type", type = "resource"}})
	global.aliases = {} -- global root key

	for name, value in pairs(resourcePrototypes) do
		local products = value.mineable_properties.products or {}
		local sorter = function(a, b)
			return a.probability < b.probability
		end


		table.sort(products, sorter)
		-- log(sb( products ))

		for _, product in pairs(products) do
			if global[_ICON_TYPES_][product.name] then
				global.aliases[name] = product.name
				global.aliases[i18n.resource(name)] = product.name
			end
		end
	end
	log("global.aliases:\n" .. sbs(global.aliases))
end


function M.clearGlobalResourceMapData()
    global[_RESOURCE_MAP_] = {}
end


function M.logIconTypes()
	-- global root keys
	-- _RESOURCE_MAP_
	-- _ICON_TYPES_
	-- aliases

	local function _logIconTypes(_type)
		local list = {}
		for key, value in pairs(global[_ICON_TYPES_]) do
			if value == _type then
				table.insert(list, key)
			end
		end
		log(_type .. "  " .. table_size(list))
	end


	-- log _ICON_TYPES_
	_logIconTypes("virtual")
	_logIconTypes("item")
	_logIconTypes("fluid")

	log("global.aliases\n" .. sb(global.aliases))
end


function M.calculateSignalID()

	local signalID = {type = "virtual", name = "signal-dot"}

	local resourceIcon = global.aliases[resource] -- global root key
	if not resourceIcon then
		log("Warning: Missing resource icon alias: " .. tostring(resource))
		log("global.aliases:\n" .. sbs(global.aliases))
		local global_aliases_size = table_size(global.aliases)
		if 0 == global_aliases_size then
			local red = {1, 0, 0}
			game.print({"errors.global-aliases-missing"}, red)
			game.print({"errors.rebuild-data-structure"}, red)
			calculateIconTypes()
			local global_aliases_size = table_size(global.aliases) -- luacheck: ignore 421
			if 0 == global_aliases_size then
				game.print({"errors.unable-to-repair"}, red)
				error("Unable to repair `global.aliases` data structure.")
			else
				game.print({"errors.repair-complete"}, red)
			end
		end
	elseif global[_ICON_TYPES_][resourceIcon] then
		signalID.type = global[_ICON_TYPES_][resourceIcon]
		signalID.name = resourceIcon
	elseif not loggedMissingResources[resourceIcon] then
		log("Warning: Missing icon type: " .. resourceIcon)
		loggedMissingResources[resourceIcon] = true
	end

    return signalID
end


return M
