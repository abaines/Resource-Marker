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


local function on_chunk_generated(event)
	local area = event.area
	local surface = event.surface

	local x = (area.left_top.x + area.right_bottom.x)/2
	local y = (area.left_top.y + area.right_bottom.y)/2

	local arrayOfLuaEntity = surface.find_entities_filtered{area=area,type = "resource"}

	if tableSize(arrayOfLuaEntity) > 0 then
		local resourcesFound = getResourceCounts(arrayOfLuaEntity)

		log(serpent.block( resourcesFound ))
	end
end


script.on_event({
	defines.events.on_chunk_generated,
},on_chunk_generated)

