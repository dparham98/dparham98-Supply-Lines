extends SceneTree
# Saves command card hotkeys to the Input Map. HUD buttons carry matching Shortcut resources,
# so a key works only while its button is visible and enabled. Actions sharing a key belong
# to different cards, which are never shown together.
func _initialize() -> void:
	var keys := {"command_move": KEY_M, "command_attack": KEY_A, "command_gather": KEY_G, "command_fell": KEY_F, "command_stop": KEY_S, "command_return": KEY_V, "command_repair": KEY_R, "command_capture": KEY_C, "command_derail": KEY_R, "command_drop": KEY_X, "command_refuel": KEY_T, "command_deploy": KEY_D, "command_cancel": KEY_X, "command_pause": KEY_R, "command_focus_assigned": KEY_F,
		"produce_infantry": KEY_F, "produce_depot_truck": KEY_D, "produce_cargo": KEY_V, "produce_train": KEY_T,
		"produce_scout": KEY_S, "produce_grenadier": KEY_G, "produce_tank": KEY_T, "produce_motorcycle": KEY_C, "produce_drone": KEY_D, "produce_ubermech": KEY_Q,
		"control_group_1": KEY_1, "control_group_2": KEY_2, "control_group_3": KEY_3, "control_group_4": KEY_4, "control_group_5": KEY_5, "control_group_6": KEY_6, "control_group_7": KEY_7, "control_group_8": KEY_8, "control_group_9": KEY_9,
		"playtest_tools": KEY_F10, "map_show_all": KEY_ALT,
		"command_load": KEY_E, "command_unload": KEY_V, "command_trips": KEY_C,
		# The Load and Make crates pages, and the Generator card's fuel tiles.
		"resource_iron": KEY_A, "resource_energy": KEY_E, "resource_wood": KEY_W, "resource_coal": KEY_C,
		# The Temple of Science's research and the train's Mine iron order (docs/TEMPLE_OF_SCIENCE.md).
		"research_mining_trains": KEY_R, "research_minelaying": KEY_N, "command_lay_mine": KEY_E, "command_buy_mine": KEY_Q, "command_mine_iron": KEY_I,
		# The Foundry's and Forge's upgrade lines (docs/UPGRADES.md), one tile per line.
		# The Grail Sentinel's Mist and Slow (docs/MIST_AND_SLOW.md).
		"command_mist": KEY_Q, "command_slow": KEY_W,
		"upgrade_1": KEY_Q, "upgrade_2": KEY_W, "upgrade_3": KEY_E, "upgrade_4": KEY_R,
		"command_make_crates": KEY_C, "command_worksite": KEY_W, "command_burn_either": KEY_E,
		# Build page tiles (the card is hidden there, so letters can repeat) and header actions.
		"build_depot": KEY_D, "build_generator": KEY_G, "build_barracks": KEY_B, "build_tank_factory": KEY_T, "build_mine": KEY_A, "build_coal_mine": KEY_C, "build_rail": KEY_R, "build_temple": KEY_S, "build_wainwright": KEY_W, "produce_keep_train": KEY_T, "build_foundry": KEY_O, "build_forge": KEY_O, "build_pin": KEY_P, "build_back": KEY_ESCAPE,
		# B opens the build page; the header button is disabled there, so B then picks Barracks.
		"command_global_build": KEY_B}
	for action in keys:
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": [event]})
	assert(ProjectSettings.save() == OK)
	print("Command Input Map saved")
	quit(0)
