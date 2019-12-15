-- Kizrak


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
	x,y = getXYCenter(area)

	return math.floor( x /32 ), math.floor( y /32 )
end


local function printResourceMap()
	for surface,value1 in pairs(global["resourceMap"]) do
		log("   " .. surface)
		for res,value2 in pairs(value1) do
			log("      " .. res)
			for xx,value3 in pairs(value2) do
				for yy,value4 in pairs(value3) do
					log("         " .. xx..','..yy..','..value4)
				end
			end
		end
	end
end


local function updateGlobal(surface,name,x,y,amount)
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

	global["resourceMap"][surface.name][name][x][y] = amount
end


local function updateGlobalForTile(surface,x,y,resourcesFound)
	for name,amount in pairs(resourcesFound) do
		updateGlobal(surface,name,x,y,amount)
	end
end


local function on_chunk_generated(event)
	local surface = event.surface
	local area = event.area

	local x,y = getXY(area)

	local arrayOfLuaEntity = surface.find_entities_filtered{area=area,type = "resource"}

	if tableSize(arrayOfLuaEntity) > 0 then
		local resourcesFound = getResourceCounts(arrayOfLuaEntity)

		updateGlobalForTile(surface,x,y,resourcesFound)

		local players = game.forces['player']
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





local function getGlobalData(surface,area)
	local x,y = getXY(area)
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


local function on_chunk_charted(event)
	local surface_index = event.surface_index -- uint
	local position = event.position -- ChunkPosition
	local area = event.area -- BoundingBox: Area of the chunk.
	local force = event.force -- LuaForce

	local surface = game.surfaces[surface_index]
	local xc,yc = getXYCenter(area)

	local resourceData = getGlobalData(surface,area)
	if tableSize(resourceData) > 0 then
		log(serpent.block( resourceData ))
	end


	force.add_chart_tag(surface,
	{
		position = {xc,yc},
		text = "hiya",
	})
end


script.on_event({
	defines.events.on_chunk_charted
},on_chunk_charted)

