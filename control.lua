-- Kizrak


local util = require("util")


local function sb(object)
	return serpent.block( object )
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


local function printResourceMap()
	for surface,value1 in pairs(global["resourceMap"]) do
		log("   " .. surface)
		for res,value2 in pairs(value1) do
			log("      " .. res)
			for xx,value3 in pairs(value2) do
				for yy,value4 in pairs(value3) do
					log("         " .. xx..','..yy..','..value4.amount)
				end
			end
		end
	end
end


local function updateGlobalResourceSurface(surface)
	if global["resourceMap"] == nil then
		global["resourceMap"] = {}
	end

	if global["resourceMap"][surface.name] == nil then
		global["resourceMap"][surface.name] = {}
	end
end


local function updateGlobalResourceMap(surface,name,x,y,amount)
	--log(name..','..x..','..y..','..amount)
	updateGlobalResourceSurface(surface)

	if global["resourceMap"][surface.name][name] == nil then
		global["resourceMap"][surface.name][name] = {}
	end

	if global["resourceMap"][surface.name][name][x] == nil then
		global["resourceMap"][surface.name][name][x] = {}
	end

	global["resourceMap"][surface.name][name][x][y] = { amount = amount }
end


local function updateGlobalResourceMapForTile(surface,x,y,resourcesFound)
	for name,amount in pairs(resourcesFound) do
		updateGlobalResourceMap(surface,name,x,y,amount)
	end
end


local function on_chunk_generated(event)
	local surface = event.surface
	local area = event.area

	local x,y = getXY(area)
	local arrayOfLuaEntity = surface.find_entities_filtered{area=area,type = "resource"}

	if table_size(arrayOfLuaEntity) > 0 then
		local resourcesFound = getResourceCounts(arrayOfLuaEntity)

		updateGlobalResourceMapForTile(surface,x,y,resourcesFound)

		local generate_adjacent_chunks = settings.global["resourcemarker-generate-adjacent-chunks"].value
		if generate_adjacent_chunks then
			local position = getXYCenterPosition(area)
			surface.request_to_generate_chunks(position,1)
		end

		local chart_resource_chunks = settings.global["resourcemarker-chart-resource-chunks"].value
		if chart_resource_chunks then
			local players = game.forces['player']
			players.chart(surface,{area.left_top,area.left_top})
		end
	end

	if false and game.tick>120 and not global.printed then
		global.printed = true
		printResourceMap()
	end
end


script.on_event({defines.events.on_chunk_generated,},on_chunk_generated)





local function getXYKey(x,y)
	return math.floor(x)..','..math.floor(y)
end

local function dekeyXY(key)
	local x, y = key:match("([^,]+),([^,]+)")
	return math.floor(x),math.floor(y)
end


local function getGlobalDataForChunkPosition(surface,x,y)
	updateGlobalResourceSurface(surface)
	local surfaceData = global["resourceMap"][surface.name]
	local data = {}

	for resource,value in pairs(surfaceData) do
		if value and value[x] and value[x][y] then
			local amount = value[x][y]
			--log(resource .. "   " .. amount )
			data[resource] = amount
		end
	end

	return data
end


local function getGlobalDataForArea(surface,area)
	local x,y = getXY(area)

	return getGlobalDataForChunkPosition(surface,x,y)
end


local function getNearbyChartedChunks(surface,force,chunkPosition,resource)
	--log(resource .. "   " .. chunkPosition.x .. "   " .. chunkPosition.y)
	local chunkPositions = {}

	for x=chunkPosition.x-1,chunkPosition.x+1 do
		for y=chunkPosition.y-1,chunkPosition.y+1 do
			local data = getGlobalDataForChunkPosition(surface, x, y)
			if data and data[resource] and force.is_chunk_charted(surface,chunkPosition) then
				--log("   " .. x .. "   " .. y .. "   " .. data[resource].amount)
				chunkPositions[getXYKey(x,y)] = data[resource]
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
loggedMissingResources = {}

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

	local tag = force.add_chart_tag(surface,
	{
		position = position,
		text = number,
		icon = signalID,
	})

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
	end
end


local function _on_chunk_charted(surface,force,chunkPosition,area)
	local resourceData = getGlobalDataForArea(surface,area)

	for resource, value in pairs(resourceData) do
		updateMapTags(surface,force,chunkPosition,resource)
	end
end

local function on_chunk_charted(event)
	local surface_index = event.surface_index -- uint
	local chunkPosition = event.position -- ChunkPosition
	local area = event.area -- BoundingBox: Area of the chunk.
	local force = event.force -- LuaForce

	local surface = game.surfaces[surface_index]
	_on_chunk_charted(surface,force,chunkPosition,area)
end


script.on_event({defines.events.on_chunk_charted},on_chunk_charted)




local function calculateIconTypes()
	-- global.iconTypes
	global["iconTypes"] = {}
	for key,v in pairs(game.virtual_signal_prototypes) do
		global["iconTypes"][key] = "virtual"
	end
	for key,v in pairs(game.item_prototypes) do
		global["iconTypes"][key] = "item"
	end
	for key,v in pairs(game.fluid_prototypes) do
		global["iconTypes"][key] = "fluid"
	end
	--log(sb( global["iconTypes"] ))

	-- global.aliases
	local resourcePrototypes = game.get_filtered_entity_prototypes( {{filter="type",type="resource"}} )
	global.aliases = {}

	for name,value in pairs(resourcePrototypes) do
		local products = value.mineable_properties.products
		if table_size(products)==1 and products[1].name == name then
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

	--log(sb( global.aliases ))
end


local function onInit()
	calculateIconTypes()

	local chart_resource_chunks = settings.global["resourcemarker-starting-radius-to-generate"].value

	for _, surface in pairs(game.surfaces) do
		for r=0,chart_resource_chunks do
			surface.request_to_generate_chunks({0,0},r)
		end

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

	log("resourcemarker-starting-radius-to-generate: " .. chart_resource_chunks)
end

script.on_init(onInit)

