data:extend({
	-- runtime-global
	{
		type = "bool-setting",
		name = "resourcemarker-include-raw-resource-name-in-tags",
		default_value = true,
		setting_type = "runtime-global",
	},
	{
		type = "bool-setting",
		name = "resourcemarker-generate-adjacent-chunks",
		default_value = false,
		setting_type = "runtime-global",
	},
	{
		type = "bool-setting",
		name = "resourcemarker-chart-resource-chunks",
		default_value = false,
		setting_type = "runtime-global",
	},
	{
		type = "int-setting",
		name = "resourcemarker-minimum-size",
		default_value = 1000,
		minimum_value = 0,
		setting_type = "runtime-global",
	},
	{
		type = "int-setting",
		name = "resourcemarker-starting-radius-to-generate",
		default_value = 8,
		minimum_value = 0,
		setting_type = "runtime-global",
	},
})

