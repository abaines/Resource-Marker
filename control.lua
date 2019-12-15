-- Kizrak


local function sb(object)
	return serpent.block( object )
end

local function tableSize(someTable)
	local count = 0
	for _,_ in pairs(someTable) do
		count = 1 + count
	end
	return count
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


local function updateGlobalResourceMap(surface,name,x,y,amount)
	--log(name..','..x..','..y..','..amount)
	if global["resourceMap"] == nil then
		global["resourceMap"] = {}
	end

	if global["resourceMap"][surface.name] == nil then
		global["resourceMap"][surface.name] = {}
	end

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

	if tableSize(arrayOfLuaEntity) > 0 then
		local resourcesFound = getResourceCounts(arrayOfLuaEntity)

		updateGlobalResourceMapForTile(surface,x,y,resourcesFound)

		local players = game.forces['player']
		local position = getXYCenterPosition(area)
		surface.request_to_generate_chunks(position,1)


		players.chart(surface,{area.left_top,area.left_top})
	end

	if game.tick>120 and not global.printed then
		global.printed = true
		printResourceMap()
	end
end


script.on_event({
	defines.events.on_chunk_generated,
},on_chunk_generated)





local function getXYKey(x,y)
	return math.floor(x)..','..math.floor(y)
end

local function dekeyXY(key)
	local x, y = key:match("([^,]+),([^,]+)")
	return math.floor(x),math.floor(y)
end


local function getGlobalDataForChunkPosition(surface,x,y)
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
				--table.insert(chunkPositions,{x=x,y=y})
				chunkPositions[getXYKey(x,y)] = data[resource]
			end
		end
	end

	return chunkPositions
end


local function floodNearbyChartedChunks(surface,force,chunkPosition,resource)
	local chunkPositions = getNearbyChartedChunks(surface,force,chunkPosition,resource)

	for i=0,1000 do
		local sizeStart = tableSize(chunkPositions)

		for key,value in pairs(chunkPositions) do
			chunkPositions[key] = value
		end

		local sizeEnd = tableSize(chunkPositions)

		if sizeStart == sizeEnd then
			return chunkPositions
		end
	end

	log("EXCESSIVE FLOODING!")
	return chunkPositions
end


local function updateMapTags(surface,force,chunkPosition,resource)
	local flood = floodNearbyChartedChunks(surface,force,chunkPosition,resource)
	local total = 0
	local xCenter = 0
	local yCenter = 0

	log(resource)
	for key,value in pairs(flood) do
		local x,y = dekeyXY(key)
		local amount = value.amount
		log(x .. "   " .. y .. "   " .. amount)
		total = amount + total
		xCenter = x*amount + xCenter
		yCenter = y*amount + yCenter
	end

	local x = xCenter/total
	local y = yCenter/total
	log(total .. "   " .. x .. "   " .. y)


	local tag = force.add_chart_tag(surface,
	{
		position = {x*32+16,y*32+16},
		text = total,
	})

	if tag==nil then
		log("NIL TAG!")
		game.print("NIL TAG!")
		game.print(sb({x*32+16,y*32+16}))
	end

	for key,value in pairs(flood) do
		local oldTag = value.tag
		if oldTag and oldTag.valid then
			oldTag.destroy()
		end
		value.tag = tag
	end
end


local function on_chunk_charted(event)
	local surface_index = event.surface_index -- uint
	local chunkPosition = event.position -- ChunkPosition
	local area = event.area -- BoundingBox: Area of the chunk.
	local force = event.force -- LuaForce

	local surface = game.surfaces[surface_index]
	local resourceData = getGlobalDataForArea(surface,area)

	for resource, value in pairs(resourceData) do
		updateMapTags(surface,force,chunkPosition,resource)
	end

--		local position = getXYCenterPosition(area)
--		log(serpent.block( position ))
--		local tag = force.add_chart_tag(surface,
--		{
--			position = position,
--			text = text,
--		})
--
--		if tag==nil then
--			log("NIL TAG!")
--		end
end


script.on_event({
	defines.events.on_chunk_charted
},on_chunk_charted)

