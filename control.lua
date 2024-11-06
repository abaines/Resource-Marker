-- Kizrak
local util = require("util")

local i18n = require('english_lib')
local glib = require('global_lib')

local sb = serpent.block

--- TODO: time for a library soon...
local function sbs(obj) -- luacheck: ignore 211
	local s = sb(obj):gsub("%s+", " ")
	return s
end

local function table_length(tb)
	-- table array size length count
	assert(type(tb) == 'table')

	local count = 0
	for _ in pairs(tb) do
		count = count + 1
	end
	return count
end

local function format_number(input)
	local number = util.format_number(input, true)

	if string.match(number, "%d%d%d.%d[a-zA-Z]") then
		number = number:sub(1, 3) .. number:sub(6)

	elseif string.match(number, "[2-9]%d.%d[a-zA-Z]") then
		number = number:sub(1, 2) .. number:sub(5)

	end

	return number
end

local function getResourceCounts(resources)
	local resourcesFound = {}

	for _, resource in pairs(resources) do
		local name = resource.name
		local localName = i18n.resource(name)
		local amount = resource.initial_amount or resource.amount

		if not resourcesFound[localName] then
			resourcesFound[localName] = 0
		end

		resourcesFound[localName] = amount + resourcesFound[localName]
	end

	return resourcesFound
end

local function getXYCenter(area)
	local x = (area.left_top.x + area.right_bottom.x) / 2
	local y = (area.left_top.y + area.right_bottom.y) / 2

	return x, y
end

local function getXY(area)
	local x, y = getXYCenter(area)

	return math.floor(x / 32), math.floor(y / 32)
end

local function getXYCenterPosition(area)
	local x, y = getXYCenter(area)

	return {x = x, y = y}
end

local function updateGlobalResourceMap(surface, resourceName, x, y, amount)
	-- log(resourceName..','..x..','..y..','..amount)
	local locData = glib.getGlobalMapLocationData(surface, x, y)
	local amt = -math.huge

	if locData[resourceName] and locData[resourceName].amount then
		amt = locData.resources[resourceName].amount
	end

	locData.resources[resourceName] = {amount = math.max(amt, amount)}
end

local function updateGlobalResourceMapForTile(surface, x, y, resourcesFound)
	for name, amount in pairs(resourcesFound) do
		updateGlobalResourceMap(surface, name, x, y, amount)
	end
end

local function _on_chunk_generated(surface, area)
	local x, y = getXY(area)
	local arrayOfLuaEntity = surface.find_entities_filtered {area = area, type = "resource"}

	if table_size(arrayOfLuaEntity) > 0 then
		local resourcesFound = getResourceCounts(arrayOfLuaEntity)

		updateGlobalResourceMapForTile(surface, x, y, resourcesFound)

		local generate_adjacent_chunks = settings.global["resourcemarker-generate-adjacent-chunks"].value
		if generate_adjacent_chunks then
			local position = getXYCenterPosition(area)
			surface.request_to_generate_chunks(position, 0)
			surface.request_to_generate_chunks(position, 1)
		end

		local chart_resource_chunks = settings.global["resourcemarker-chart-resource-chunks"].value
		if chart_resource_chunks then
			local players = game.forces['player']
			players.chart(surface, {area.left_top, area.left_top})
		end
	end

	-- TODO: consider clearning this newly genereated chunk's charting data for each force
	-- AKA reset if each force thinks it has charted this chunk before
	-- see: resourceData.forces[force.name] = game.tick
end

local function on_chunk_generated(event)
	local surface = event.surface
	local area = event.area
	_on_chunk_generated(surface, area)

	--- log("on_chunk_generated  " .. sbs(surface.name) .. "  " .. sbs(area))
end

script.on_event({defines.events.on_chunk_generated}, on_chunk_generated)

local function getXYKey(x, y)
	return math.floor(x) .. ',' .. math.floor(y)
end

local function dekeyXY(key)
	local x, y = key:match("([^,]+),([^,]+)")
	return math.floor(x), math.floor(y)
end

local function getNearbyChartedChunks(surface, force, chunkPosition, resource)
	-- log(resource .. "   " .. chunkPosition.x .. "   " .. chunkPosition.y)
	local chunkPositions = {}

	for x = chunkPosition.x - 1, chunkPosition.x + 1 do
		for y = chunkPosition.y - 1, chunkPosition.y + 1 do
			local data = glib.getGlobalMapLocationData(surface, x, y)
			if data.resources[resource] and force.is_chunk_charted(surface, chunkPosition) then
				-- log("   " .. x .. "   " .. y .. "   " .. data.resources[resource].amount)
				chunkPositions[getXYKey(x, y)] = data.resources[resource]
			end
		end
	end

	return chunkPositions
end

local function floodNearbyChartedChunks(surface, force, chunkPosition, resource)
	local chunkPositions = getNearbyChartedChunks(surface, force, chunkPosition, resource)

	for _ = 0, 1000 do
		local sizeStart = table_size(chunkPositions)

		for key, value in pairs(chunkPositions) do
			chunkPositions[key] = value

			local x, y = dekeyXY(key)
			local nextChunks = getNearbyChartedChunks(surface, force, {x = x, y = y}, resource)

			for key2, value2 in pairs(nextChunks) do
				chunkPositions[key2] = value2
			end
		end

		local sizeEnd = table_size(chunkPositions)

		if sizeStart == sizeEnd then
			return chunkPositions
		end
	end

	log("EXCESSIVE FLOODING!")
	return chunkPositions
end

-- lua global
local lastLoggedTagCount = {}

local function updateMapTags(surface, force, chunkPosition, resource)
	local flood = floodNearbyChartedChunks(surface, force, chunkPosition, resource)
	local total = 0
	local xCenter = 0
	local yCenter = 0

	for key, value in pairs(flood) do
		local x, y = dekeyXY(key)
		local amount = value.amount

		total = amount + total
		xCenter = x * amount + xCenter
		yCenter = y * amount + yCenter
	end

	local x = xCenter / total
	local y = yCenter / total
	local position = {x = x * 32 + 16, y = y * 32 + 16}

	local minimum_size = settings.global["resourcemarker-minimum-size"].value
	if total < minimum_size then
		local msg = "below minimum size:" .. total .. "   resource:" .. resource
		msg = msg .. "   x:" .. position.x .. "   y:" .. position.y
		log(msg)
		return
	end

	local signalID = glib.calculateSignalID(resource)

	local text = format_number(total)

	local append_raw_to_tag = settings.global["resourcemarker-include-raw-resource-name-in-tags"].value

	if append_raw_to_tag then
		text = resource .. " " .. text -- identical to base game build-in tooltips
	end

	local tagData = {position = position, text = text, icon = signalID}

	local tag = force.add_chart_tag(surface, tagData)

	if not tag then
		local warning =
			"Warning: NIL TAG: resource:" .. resource .. "   total:" .. total .. "   x:" .. position.x .. "   y:" .. position.y
		log(warning)
		-- game.print(warning)

	else -- able to place new tag, so remove olds ones
		for _, value in pairs(flood) do
			local oldTag = value.tag
			if oldTag and oldTag.valid then
				oldTag.destroy()
			end
			value.tag = tag
		end

		local tagCount = #force.find_chart_tags(surface)
		local lltcKey = surface.name .. "^" .. force.name

		if not lastLoggedTagCount[lltcKey] or tagCount > lastLoggedTagCount[lltcKey] then
			log(#force.find_chart_tags(surface) .. " & " .. string.gsub(sb(tagData), "%s+", " "))
		end

		lastLoggedTagCount[lltcKey] = tagCount
	end
end

local function _on_chunk_charted(surface, force, chunkPosition, area)
	local resourceData = glib.getGlobalMapLocationData(surface, getXY(area))
	local charted = resourceData.forces[force.name]

	if charted then
		-- log("- "..string.gsub(sb(resourceData),"%s+"," "))
		return
	end

	_on_chunk_generated(surface, area)

	-- log("# "..string.gsub(sb(resourceData),"%s+"," "))

	for resource, _ in pairs(resourceData.resources) do
		updateMapTags(surface, force, chunkPosition, resource)
	end

	resourceData.forces[force.name] = game.tick
end

local function on_chunk_charted(event)
	local surface_index = event.surface_index -- uint
	local chunkPosition = event.position -- ChunkPosition
	local area = event.area -- BoundingBox: Area of the chunk.
	local force = event.force -- LuaForce

	local surface = game.surfaces[surface_index]
	_on_chunk_charted(surface, force, chunkPosition, area)

	if false then
		-- luacheck: ignore 511
		if event.name ~= 99 then
			log("on_chunk_charted :: Bad event name :: " .. event.name)
		end

		local logEvent = table.deepcopy(event)
		logEvent.area = nil
		logEvent.force = nil
		logEvent.surface_index = nil
		logEvent.name = nil
		log("on_chunk_charted  " .. sbs(surface.name) .. " " .. sbs(force.name) .. " " .. sbs(logEvent))
	end
end

script.on_event({defines.events.on_chunk_charted}, on_chunk_charted)

local function generateStaringArea(chunkRadius)
	log("generateStaringArea: " .. chunkRadius)

	local requests = 0

	for radius = 0, chunkRadius do
		for _, surface in pairs(game.surfaces) do
			surface.request_to_generate_chunks({0, 0}, radius)
			requests = 1 + requests
		end
	end

	log("request_to_generate_chunks: " .. requests)
end

local function parseGenerateStaringAreaCommand(event)
	local player = game.players[event.player_index]
	local parameters = event.parameter

	local radius = nil

	for parameter in string.gmatch(parameters, "%S+") do
		local num = tonumber(parameter)

		if num and not radius then
			radius = num
		elseif num then
			local msg = "Must provide exactly one integer radius to generate chunks: " .. parameters
			log(msg)
			player.print(msg, {r = 0.9, g = 0.2, b = 0.0})
			return
		end
	end

	if radius then
		if radius == math.floor(radius) then
			generateStaringArea(radius)
			local msg = "Generating Starting Area Chunks: " .. radius
			log(msg)
			game.print(msg, {r = 0.0, g = 0.9, b = 0.4})
			return
		end
	end

	local msg = "Must provide integer radius to generate: " .. parameters
	log(msg)
	player.print(msg, {r = 0.9, g = 0.2, b = 0.0})
end

local function onInit()
	glib.calculateIconTypes()

	-- for all chunks on all surfaces
	for _, surface in pairs(game.surfaces) do
		for chunk in surface.get_chunks() do
			local x, y = chunk.x, chunk.y
			local event = {}
			event.surface = surface
			event.area = chunk.area

			on_chunk_generated(event)

			for _, force in pairs(game.forces) do
				if force.is_chunk_charted(surface, {x, y}) then
					local chunkPosition = {x = x, y = y}
					_on_chunk_charted(surface, force, chunkPosition, chunk.area)
				end
			end
		end
	end

	local resourcemarker_starting_radius_to_generate = settings.global["resourcemarker-starting-radius-to-generate"].value
	log("resourcemarker-starting-radius-to-generate: " .. resourcemarker_starting_radius_to_generate)
	generateStaringArea(resourcemarker_starting_radius_to_generate)
end

script.on_init(onInit)

local function on_configuration_changed()
	log("on_configuration_changed")
	glib.calculateIconTypes()
end

script.on_configuration_changed(on_configuration_changed)

local function chart_generated_chunks(event)
	local player = game.players[event.player_index]

	for _, surface in pairs(game.surfaces) do
		for chunk in surface.get_chunks() do
			player.force.chart(surface, chunk.area)
		end
	end

	player.print("Revealing all generated chunks to your force.")
end

local function _get_ore_name(tag)
	local text = tag.text
	local tag_length = string.len(text) -- find length of tag name
	local cutoff, _ = string.find(string.reverse(text), " ", 1, true) -- find index of the last space
	if not cutoff then
		cutoff = 0
	end
	local tag_ore_name = string.sub(text, 1, tag_length - cutoff)

	return tag_ore_name
end

local function _get_tag_exceptions(event)
	local parameters = event.parameter

	local tag_exceptions = {}
	local i = 0 -- used to ignore first parameter entry

	for parameter in string.gmatch(parameters, "([^,]+)") do
		if i ~= 0 then -- if not first parameter entry then insert key into lookup table
			local cleaned_param = parameter:match('^%s*(.-)%s*$'):lower()
			tag_exceptions[cleaned_param] = true
		end
		i = i + 1
	end

	return tag_exceptions
end

local function clear_map_tags_and_data(event, tag_exceptions)
	glib.clearGlobalResourceMapData()

	tag_exceptions = tag_exceptions or {}

	for _, surface in pairs(game.surfaces) do
		for _, force in pairs(game.forces) do
			for _, tag in pairs(force.find_chart_tags(surface)) do
				local tag_ore_name = _get_ore_name(tag):lower()
				if tag_exceptions[tag_ore_name] == nil then
					tag.destroy()
				end
			end
		end
	end

	if event then
		local player = game.players[event.player_index]
		if table_length(tag_exceptions) > 0 then
			player.print("Removed all map labels and cleared mod data, except:")
			for tag_exp in pairs(tag_exceptions) do
				player.print("   " .. tag_exp)
			end
		else
			player.print("Removed all map labels and cleared mod data.")
		end
	end
end

local function reset_map_tags_and_data(event)
	local player = game.players[event.player_index]
	clear_map_tags_and_data(nil)

	for _, force in pairs(game.forces) do
		for _, surface in pairs(game.surfaces) do
			for chunk in surface.get_chunks() do
				local chunkPosition = {x = chunk.x, y = chunk.y}
				if force.is_chunk_charted(surface, chunkPosition) then
					_on_chunk_charted(surface, force, chunkPosition, chunk.area)
				end
			end
		end
	end

	player.print("Removed and re-tagged all map labels.")
end

local blue = {0.7, 0.7, 1}
local darkRed = {0.9, 0.3, 0.3}

local function printHelp(player)
	player.print("Parameters for `/resourcemarker` command:", {0.7, 1, 0.7})

	player.print("   chart -- Reveal all generated chunks to player's force.", blue)
	player.print("   generate <radius in chunks> -- Generate chunks around starting area (in chunk radius).", blue)
	player.print("   help -- Display this message.", blue)

	player.print("For debugging and diagnostics only:", {0.9, 0.4, 0.4})

	player.print(
	"   retag -- Remove all map labels and clear mod data, then rebuild mod data and retag all resource labels."
	, darkRed)
	player.print("   delete -- Remove all map labels and clear mod data.", darkRed)
	player.print("      a list of ores can be provided to be ignored during tag deletion, such as:", darkRed)
	player.print("      /resourcemarker delete,Copper ore,Iron ore", darkRed)
	player.print("   log -- Log aliases and icons data to log file.", darkRed)
	player.print("   rebuild -- clear and rebuild aliases and icon data.", darkRed)
end

local function unifiedCommandHandler(event)
	log("unifiedCommandHandler\n" .. sb(event))
	local parameter = event.parameter and event.parameter:lower()
	local player = game.players[event.player_index]

	if not parameter then
		printHelp(player)

	elseif string.find(parameter, "help") or string.find(parameter, "?") then
		printHelp(player)

	elseif string.find(parameter, "chart") then
		player.print("   chart -- Reveal all generated chunks to player's force.", blue)
		chart_generated_chunks(event)

	elseif string.find(parameter, "generat") then
		player.print("   generate <radius in chunks> -- Generate chunks around starting area (in chunk radius).", blue)
		parseGenerateStaringAreaCommand(event)

	elseif string.find(parameter, "retag") then
		player.print(
		"   retag -- Remove all map labels and clear mod data, then rebuild mod data and retag all resource labels."
		, darkRed)
		reset_map_tags_and_data(event)

	elseif string.find(parameter, "delete") then
		player.print("   delete -- Remove all map labels and clear mod data.", darkRed)
		local tag_exceptions = _get_tag_exceptions(event)
		clear_map_tags_and_data(event, tag_exceptions)

	elseif string.find(parameter, "log") then
		player.print("   log -- Log aliases and icons data to log file.", darkRed)
		glib.logIconTypes()

	elseif string.find(parameter, "rebuild") then
		player.print("   rebuild -- clear and rebuild aliases and icon data.", darkRed)
		glib.calculateIconTypes()

	else
		printHelp(player)

	end
end

commands.add_command("resourcemarker", "Enter `/resourcemarker help` for more details.", unifiedCommandHandler)

-- /c t=game.forces[1].find_chart_tags(game.surfaces[1] ) game.print( #t )
-- /c t=game.forces[1].find_chart_tags(game.surfaces[1] ) for _,i in pairs(t) do i.destroy() end

