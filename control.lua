-- Kizrak


local util = require("util")


local english = require('english')


local sb = serpent.block


--- TODO: time for a library soon...
local function sbs(obj) -- luacheck: ignore 211
	local s = sb( obj ):gsub("%s+", " ")
	return s
end


local function format_number(input)
	local number = util.format_number(input,true)

	if string.match(number,"%d%d%d.%d[a-zA-Z]") then
		number = number:sub(1,3) .. number:sub(6)

	elseif string.match(number,"[2-9]%d.%d[a-zA-Z]") then
		number = number:sub(1,2) .. number:sub(5)

	end

	return number
end


-- lua global
local englishMissingSpamGuard = {}

local function getI18N(resource)
	local i18n = english[resource]
	if not i18n and not englishMissingSpamGuard[resource] then
		local msg = "The english.lua table missing `" .. resource.."`"
		log(msg)
		-- game.print(msg)
		englishMissingSpamGuard[resource]=true
	end
	local localResource = i18n or resource
	return localResource
end


local function getResourceCounts(resources)
	local resourcesFound = {}

	for _,resource in pairs(resources) do
		local name = resource.name
		local localName = getI18N(name)
		local amount = resource.initial_amount or resource.amount

		if not resourcesFound[localName] then
			resourcesFound[localName] = 0
		end

		resourcesFound[localName] = amount + resourcesFound[localName]
	end

	return resourcesFound
end


local function getXYCenter(area)
	local x = (area.left_top.x + area.right_bottom.x)/2
	local y = (area.left_top.y + area.right_bottom.y)/2

	return x,y
end

local function getXY(area)
	local x,y = getXYCenter(area)

	return math.floor( x /32 ), math.floor( y /32 )
end

local function getXYCenterPosition(area)
	local x,y = getXYCenter(area)

	return {x=x,y=y}
end


local _RESOURCE_MAP_ = "resourceMap" -- global root key

local function getGlobalMapLocationData(surface,x,y)
	local name = surface.name

	global[_RESOURCE_MAP_]                       = global[_RESOURCE_MAP_] or {}
	global[_RESOURCE_MAP_][name]                 = global[_RESOURCE_MAP_][name] or {}
	global[_RESOURCE_MAP_][name][x]              = global[_RESOURCE_MAP_][name][x] or {}
	global[_RESOURCE_MAP_][name][x][y]           = global[_RESOURCE_MAP_][name][x][y] or {}
	global[_RESOURCE_MAP_][name][x][y].resources = global[_RESOURCE_MAP_][name][x][y].resources or {}
	global[_RESOURCE_MAP_][name][x][y].forces    = global[_RESOURCE_MAP_][name][x][y].forces or {}

	return global[_RESOURCE_MAP_][name][x][y]
end


local function updateGlobalResourceMap(surface,resourceName,x,y,amount)
	--log(resourceName..','..x..','..y..','..amount)
	local locData = getGlobalMapLocationData(surface,x,y)
	local amt = -math.huge

	if locData[resourceName] and locData[resourceName].amount then
		amt = locData.resources[resourceName].amount
	end

	locData.resources[resourceName] = { amount = math.max(amt,amount) }
end


local function updateGlobalResourceMapForTile(surface,x,y,resourcesFound)
	for name,amount in pairs(resourcesFound) do
		updateGlobalResourceMap(surface,name,x,y,amount)
	end
end


local function _on_chunk_generated(surface,area)
	local x,y = getXY(area)
	local arrayOfLuaEntity = surface.find_entities_filtered{area=area,type = "resource"}

	if table_size(arrayOfLuaEntity) > 0 then
		local resourcesFound = getResourceCounts(arrayOfLuaEntity)

		updateGlobalResourceMapForTile(surface,x,y,resourcesFound)

		local generate_adjacent_chunks = settings.global["resourcemarker-generate-adjacent-chunks"].value
		if generate_adjacent_chunks then
			local position = getXYCenterPosition(area)
			surface.request_to_generate_chunks(position,0)
			surface.request_to_generate_chunks(position,1)
		end

		local chart_resource_chunks = settings.global["resourcemarker-chart-resource-chunks"].value
		if chart_resource_chunks then
			local players = game.forces['player']
			players.chart(surface,{area.left_top,area.left_top})
		end
	end

	-- TODO: consider clearning this newly genereated chunk's charting data for each force
	-- AKA reset if each force thinks it has charted this chunk before
	-- see: resourceData.forces[force.name] = game.tick
end

local function on_chunk_generated(event)
	local surface = event.surface
	local area = event.area
	_on_chunk_generated(surface,area)

	--- log("on_chunk_generated  " .. sbs(surface.name) .. "  " .. sbs(area))
end


script.on_event({defines.events.on_chunk_generated,},on_chunk_generated)





local function getXYKey(x,y)
	return math.floor(x)..','..math.floor(y)
end

local function dekeyXY(key)
	local x, y = key:match("([^,]+),([^,]+)")
	return math.floor(x),math.floor(y)
end



local function getNearbyChartedChunks(surface,force,chunkPosition,resource)
	--log(resource .. "   " .. chunkPosition.x .. "   " .. chunkPosition.y)
	local chunkPositions = {}

	for x=chunkPosition.x-1,chunkPosition.x+1 do
		for y=chunkPosition.y-1,chunkPosition.y+1 do
			local data = getGlobalMapLocationData(surface, x, y)
			if data.resources[resource] and force.is_chunk_charted(surface,chunkPosition) then
				--log("   " .. x .. "   " .. y .. "   " .. data.resources[resource].amount)
				chunkPositions[getXYKey(x,y)] = data.resources[resource]
			end
		end
	end

	return chunkPositions
end


local function floodNearbyChartedChunks(surface,force,chunkPosition,resource)
	local chunkPositions = getNearbyChartedChunks(surface,force,chunkPosition,resource)

	for i=0,1000 do
		local sizeStart = table_size(chunkPositions)

		for key,value in pairs(chunkPositions) do
			chunkPositions[key] = value

			local x,y = dekeyXY(key)
			local nextChunks = getNearbyChartedChunks(surface,force,{x=x,y=y},resource)

			for key2,value2 in pairs(nextChunks) do
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


local calculateIconTypes


-- lua global
local _ICON_TYPES_ = "iconTypes" -- global root key
local loggedMissingResources = {}
local lastLoggedTagCount = {}

local function updateMapTags(surface,force,chunkPosition,resource)
	local flood = floodNearbyChartedChunks(surface,force,chunkPosition,resource)
	local total = 0
	local xCenter = 0
	local yCenter = 0

	for key,value in pairs(flood) do
		local x,y = dekeyXY(key)
		local amount = value.amount

		total = amount + total
		xCenter = x*amount + xCenter
		yCenter = y*amount + yCenter
	end

	local x = xCenter/total
	local y = yCenter/total
	local position = {x=x*32+16,y=y*32+16}

	local minimum_size = settings.global["resourcemarker-minimum-size"].value
	if total<minimum_size then
		local msg = "below minimum size:" .. total .. "   resource:" .. resource .. "   x:" .. position.x .. "   y:" .. position.y
		log(msg)
		return
	end

	local signalID = {
		type="virtual",
		name="signal-dot",
	}

	local resourceIcon = global.aliases[resource] -- global root key
	if not resourceIcon then
		log("Warning: Missing resource icon alias: "..tostring(resource))
		log("global.aliases:\n"..sbs(global.aliases))
		local global_aliases_size = table_size(global.aliases)
		if 0==global_aliases_size then
			local red = {1,0,0}
			game.print({"errors.global-aliases-missing"},red)
			game.print({"errors.rebuild-data-structure"},red)
			calculateIconTypes()
			local global_aliases_size = table_size(global.aliases)
			if 0==global_aliases_size then
				game.print({"errors.unable-to-repair"},red)
				error("Unable to repair `global.aliases` data structure.")
			else
				game.print({"errors.repair-complete"},red)
			end
		end
	elseif global[_ICON_TYPES_][resourceIcon] then
		signalID.type = global[_ICON_TYPES_][resourceIcon]
		signalID.name = resourceIcon
	elseif not loggedMissingResources[resourceIcon] then
		log("Warning: Missing icon type: "..resourceIcon)
		loggedMissingResources[resourceIcon] = true
	end

	local text = format_number(total)

	local append_raw_to_tag = settings.global["resourcemarker-include-raw-resource-name-in-tags"].value

	if append_raw_to_tag then
		text = resource .. " " .. text -- identical to base game build-in tooltips
	end

	local tagData = {
		position = position,
		text = text,
		icon = signalID,
	}

	local tag = force.add_chart_tag(surface,tagData)

	if not tag then
		local warning = "Warning: NIL TAG: resource:" .. resource .. "   total:" .. total .. "   x:" .. position.x .. "   y:" .. position.y
		log(warning)
		--game.print(warning)

	else -- able to place new tag, so remove olds ones
		for key,value in pairs(flood) do
			local oldTag = value.tag
			if oldTag and oldTag.valid then
				oldTag.destroy()
			end
			value.tag = tag
		end

		local tagCount = #force.find_chart_tags(surface)
		local lltcKey = surface.name.."^"..force.name

		if not lastLoggedTagCount[lltcKey] or tagCount>lastLoggedTagCount[lltcKey] then
			log(#force.find_chart_tags(surface).." & "..string.gsub(sb(tagData),"%s+"," "))
		end

		lastLoggedTagCount[lltcKey] = tagCount
	end
end


local function _on_chunk_charted(surface,force,chunkPosition,area)
	local resourceData = getGlobalMapLocationData(surface,getXY(area))
	local charted = resourceData.forces[force.name]

	if charted then
		--log("- "..string.gsub(sb(resourceData),"%s+"," "))
		return
	end

	_on_chunk_generated(surface,area)

	--log("# "..string.gsub(sb(resourceData),"%s+"," "))

	for resource, _ in pairs(resourceData.resources) do
		updateMapTags(surface,force,chunkPosition,resource)
	end

	resourceData.forces[force.name] = game.tick
end

local function on_chunk_charted(event)
	local surface_index = event.surface_index -- uint
	local chunkPosition = event.position -- ChunkPosition
	local area = event.area -- BoundingBox: Area of the chunk.
	local force = event.force -- LuaForce

	local surface = game.surfaces[surface_index]
	_on_chunk_charted(surface,force,chunkPosition,area)

	if false then
		-- luacheck: ignore 511
		if event.name ~= 99 then
			log("on_chunk_charted :: Bad event name :: " .. event.name)
		end

		local logEvent = table.deepcopy( event )
		logEvent.area=nil
		logEvent.force=nil
		logEvent.surface_index=nil
		logEvent.name=nil
		log("on_chunk_charted  " .. sbs(surface.name) .. " " .. sbs(force.name) .. " " .. sbs(logEvent))
	end
end


script.on_event({defines.events.on_chunk_charted},on_chunk_charted)




local function logIconTypes(event)
	-- global root keys
	-- _RESOURCE_MAP_
	-- _ICON_TYPES_
	-- aliases

	local function _logIconTypes(_type)
		local list = {}
		for key,value in pairs(global[_ICON_TYPES_]) do
			if value == _type then
				table.insert(list,key)
			end
		end
		log(_type.."  "..table_size(list))
	end

	--log _ICON_TYPES_
	_logIconTypes("virtual")
	_logIconTypes("item")
	_logIconTypes("fluid")

	log("global.aliases\n"..sb(global.aliases))
end




function calculateIconTypes()
	global[_ICON_TYPES_] = {} -- global root key
	for key,_ in pairs(game.virtual_signal_prototypes) do
		global[_ICON_TYPES_][key] = "virtual"
	end
	for key,_ in pairs(game.item_prototypes) do
		global[_ICON_TYPES_][key] = "item"
	end
	for key,_ in pairs(game.fluid_prototypes) do
		global[_ICON_TYPES_][key] = "fluid"
	end


	local resourcePrototypes = game.get_filtered_entity_prototypes( {{filter="type",type="resource"}} )
	global.aliases = {} -- global root key

	for name,value in pairs(resourcePrototypes) do
		local products = value.mineable_properties.products
		table.sort(products, function(a,b) return a.probability<b.probability end)
		--log(sb( products ))

		for _,product in pairs(products) do
			if global[_ICON_TYPES_][product.name] then
				global.aliases[name] = product.name
				global.aliases[getI18N(name)] = product.name
			end
		end
	end
	log("global.aliases:\n"..sbs(global.aliases))
end



local function generateStaringArea(chunkRadius)
	log("generateStaringArea: " .. chunkRadius)

	local requests = 0

	for radius=0,chunkRadius do
		for _, surface in pairs(game.surfaces) do
			surface.request_to_generate_chunks({0,0},radius)
			requests = 1 + requests
		end
	end

	log("request_to_generate_chunks: " .. requests)
end

local function parseGenerateStaringAreaCommand(event)
	local player = game.players[event.player_index]
	local parameter = event.parameter

	local radius = tonumber(parameter)

	if radius then
		if radius == math.floor(radius) then
			generateStaringArea(radius)
			local msg = "Generating Starting Area Chunks: " .. radius
			log(msg)
			game.print(msg, {r=0.0, g=0.9, b=0.4})
			return
		end
	end

	local msg = "Must provide integer radius to generate: " .. parameter
	log(msg)
	player.print(msg, {r=0.9, g=0.2, b=0.0})
end



local function onInit()
	calculateIconTypes()

	-- for all chunks on all surfaces
	for _, surface in pairs(game.surfaces) do
		for chunk in surface.get_chunks() do
			local x,y = chunk.x,chunk.y
			local event = {}
			event.surface=surface
			event.area=chunk.area

			on_chunk_generated(event)

			for _,force in pairs(game.forces) do
				if force.is_chunk_charted(surface,{x,y}) then
					local chunkPosition = {x=x,y=y}
					_on_chunk_charted(surface,force,chunkPosition,chunk.area)
				end
			end
		end
	end


	local resourcemarker_starting_radius_to_generate = settings.global["resourcemarker-starting-radius-to-generate"].value
	log("resourcemarker-starting-radius-to-generate: " .. resourcemarker_starting_radius_to_generate)
	generateStaringArea(resourcemarker_starting_radius_to_generate)
end

script.on_init(onInit)



local function chart_generated_chunks(event)
	local player = game.players[event.player_index]
	for _, surface in pairs(game.surfaces) do
		for chunk in surface.get_chunks() do
			player.force.chart(surface,chunk.area)
		end
	end
	player.print("Revealing all generated chunks to your force.")
end




local function clear_map_tags_and_data(event)
	global[_RESOURCE_MAP_] = {}
	loggedMissingResources = {}
	lastLoggedTagCount = {}

	for _, surface in pairs(game.surfaces) do
		for _, force in pairs(game.forces) do
			for _,tag in pairs(force.find_chart_tags(surface)) do
				tag.destroy()
			end
		end
	end

	if event then
		local player = game.players[event.player_index]
		player.print("Removed all map labels and cleared mod data.")
	end
end



local function reset_map_tags_and_data(event)
	local player = game.players[event.player_index]
	clear_map_tags_and_data(nil)

	for _, force in pairs(game.forces) do
		for _, surface in pairs(game.surfaces) do
			for chunk in surface.get_chunks() do
				local chunkPosition = {x=chunk.x,y=chunk.y}
				if force.is_chunk_charted(surface,chunkPosition) then
					_on_chunk_charted(surface,force,chunkPosition,chunk.area)
				end
			end
		end
	end

	player.print("Removed and re-tagged all map labels.")
end



local function unifiedCommandHandler(event)
	log("unifiedCommandHandler\n"..sb(event))
	local parameter = event.parameter and event.parameter:lower()
	local player = game.players[event.player_index]

	local blue = {0.7,0.7,1}
	local darkRed = {0.9,0.3,0.3}

	local function printHelp()
		player.print("Parameters for `/resourcemarker` command:",{0.7,1,0.7})

		player.print("   chart -- Reveal all generated chunks to player's force.",blue)
		player.print("   generate <radius in chunks> -- Generate chunks around starting area (in chunk radius).",blue)
		player.print("   help -- Display this message.",blue)

		player.print("For debugging and diagnostics only:",{0.9,0.4,0.4})

		player.print("   retag -- Remove all map labels and clear mod data, then rebuild mod data and retag all resource labels.",darkRed)
		player.print("   delete -- Remove all map labels and clear mod data.",darkRed)
		player.print("   log -- Log aliases and icons data to log file.",darkRed)
		player.print("   rebuild -- clear and rebuild aliases and icon data.",darkRed)
	end

	-- WIP

	if not parameter then
		printHelp()

	elseif string.find(parameter,"help") or string.find(parameter,"?") then
		printHelp()

	elseif string.find(parameter,"chart") then
		player.print("   chart -- Reveal all generated chunks to player's force.",blue)
		chart_generated_chunks(event)

	elseif string.find(parameter,"generat") then
		player.print("   generate <radius in chunks> -- Generate chunks around starting area (in chunk radius).",blue)
		parseGenerateStaringAreaCommand(event)

	elseif string.find(parameter,"retag") then
		player.print("   retag -- Remove all map labels and clear mod data, then rebuild mod data and retag all resource labels.",darkRed)
		reset_map_tags_and_data(event)

	elseif string.find(parameter,"delete") then
		player.print("   delete -- Remove all map labels and clear mod data.",darkRed)
		clear_map_tags_and_data(event)

	elseif string.find(parameter,"log") then
		player.print("   log -- Log aliases and icons data to log file.",darkRed)
		logIconTypes(event)

	elseif string.find(parameter,"rebuild") then
		player.print("   rebuild -- clear and rebuild aliases and icon data.",darkRed)
		calculateIconTypes()

	else
		printHelp()

	end
end

commands.add_command(
	"resourcemarker",
	"Enter `/resourcemarker help` for more details.",
	unifiedCommandHandler
)


log("english:\n"..sbs(english))


-- /c t=game.forces[1].find_chart_tags(game.surfaces[1] ) game.print( #t )
-- /c t=game.forces[1].find_chart_tags(game.surfaces[1] ) for _,i in pairs(t) do i.destroy() end

