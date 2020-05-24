-- Kizrak


local util = require("util")


local sb = serpent.block


--- TODO: time for a library soon...
local function sbs(obj)
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


local function getResourceCounts(resources)
	local resourcesFound = {}

	for _,resource in pairs(resources) do
		local name = resource.name
		local amount = resource.amount

		if resourcesFound[name]==nil then
			resourcesFound[name] = 0
		end

		resourcesFound[name] = amount + resourcesFound[name]
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


local function getGlobalMapLocationData(surface,x,y)
	if global["resourceMap"] == nil then
		global["resourceMap"] = {}
	end

	if global["resourceMap"][surface.name] == nil then
		global["resourceMap"][surface.name] = {}
	end

	if global["resourceMap"][surface.name][x] == nil then
		global["resourceMap"][surface.name][x] = {}
	end

	if global["resourceMap"][surface.name][x][y] == nil then
		global["resourceMap"][surface.name][x][y] = {}
	end

	if global["resourceMap"][surface.name][x][y].resources == nil then
		global["resourceMap"][surface.name][x][y].resources = {}
	end

	if global["resourceMap"][surface.name][x][y].forces == nil then
		global["resourceMap"][surface.name][x][y].forces = {}
	end

	return global["resourceMap"][surface.name][x][y]
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


-- lua global
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

	local resourceIcon = global.aliases[resource] or resource

	if global["iconTypes"][resourceIcon] then
		signalID.type = global["iconTypes"][resourceIcon]
		signalID.name = resourceIcon
	elseif not loggedMissingResources[resourceIcon] then
		log("missing icon: "..resourceIcon)
		loggedMissingResources[resourceIcon] = true
	end

	local number = format_number(total)

	local tagData = {
		position = position,
		text = number,
		icon = signalID,
	}

	local tag = force.add_chart_tag(surface,tagData)

	if tag==nil then
		local warning = "NIL TAG: resource:" .. resource .. "   total:" .. total .. "   x:" .. position.x .. "   y:" .. position.y
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

		if lastLoggedTagCount[lltcKey]==nil or tagCount>lastLoggedTagCount[lltcKey] then
			log(#force.find_chart_tags(surface).." & "..string.gsub(sb(tagData),"%s+"," "))
		end

		lastLoggedTagCount[lltcKey] = tagCount
	end
end


local function _on_chunk_charted(surface,force,chunkPosition,area)
	_on_chunk_generated(surface,area)

	local resourceData = getGlobalMapLocationData(surface,getXY(area))
	local charted = resourceData.forces[force.name]

	if charted then
		--log("- "..string.gsub(sb(resourceData),"%s+"," "))
		return
	end

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
	--- log("on_chunk_charted  " .. sbs(surface.name) .. "  " .. sbs(force.name) .. "  " .. sbs(chunkPosition) .. "  " .. sbs(area))
end


script.on_event({defines.events.on_chunk_charted},on_chunk_charted)




local function calculateIconTypes()
	-- global.iconTypes
	global["iconTypes"] = {}
	for key,_ in pairs(game.virtual_signal_prototypes) do
		global["iconTypes"][key] = "virtual"
	end
	for key,_ in pairs(game.item_prototypes) do
		global["iconTypes"][key] = "item"
	end
	for key,_ in pairs(game.fluid_prototypes) do
		global["iconTypes"][key] = "fluid"
	end


	local resourcePrototypes = game.get_filtered_entity_prototypes( {{filter="type",type="resource"}} )
	global.aliases = {}

	for name,value in pairs(resourcePrototypes) do
		local products = value.mineable_properties.products
		if table_size(products)==1 and products[1].name == name then -- luacheck: ignore 542
			--skip
		else
			table.sort(products, function(a,b) return a.probability<b.probability end)
			--log(sb( products ))

			for _,product in pairs(products) do
				if global["iconTypes"][product.name] then
					global.aliases[name] = product.name
				end
			end
		end
	end
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

local function parseGenerateStaringAreaCommand(commandData)
	local player = game.players[commandData.player_index]
	local parameter = commandData.parameter
	local tick = commandData.tick

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

commands.add_command(
	"generate-chunks",
	"Generate chunks around starting area (in chunk radius).",
	parseGenerateStaringAreaCommand
)


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
end

commands.add_command(
	"chart-generated-chunks",
	"Reveal all generated chunks to player's force.",
	chart_generated_chunks
)



local function reset_map_tags_and_data(event)
	local player = game.players[event.player_index]
	local force = player.force

	global["resourceMap"] = {}
	loggedMissingResources = {}
	lastLoggedTagCount = {}

	for _, surface in pairs(game.surfaces) do
		for _,tag in pairs(force.find_chart_tags(surface)) do
			tag.destroy()
		end
		for chunk in surface.get_chunks() do
			local chunkPosition = {x=chunk.x,y=chunk.y}
			if force.is_chunk_charted(surface,chunkPosition) then
				_on_chunk_charted(surface,force,chunkPosition,chunk.area)
			end
		end
	end
end

commands.add_command(
	"reset-map-tags-and-data",
	"Remove all labels for the given user's force and then re-tag all resources with new labels.",
	reset_map_tags_and_data
)


-- /c t=game.forces[1].find_chart_tags(game.surfaces[1] ) game.print( #t )
-- /c t=game.forces[1].find_chart_tags(game.surfaces[1] ) for _,i in pairs(t) do i.destroy() end

