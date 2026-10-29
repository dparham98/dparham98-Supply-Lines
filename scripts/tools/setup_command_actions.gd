extends SceneTree
# Saves command card hotkeys to the Input Map. HUD buttons carry matching Shortcut resources,
# so a key works only while its button is visible and enabled. Actions sharing a key belong
# to different cards, which are never shown together.
func _initialize() -> void:
	var keys := {"command_move": KEY_M, "command_attack": KEY_A, "command_gather": KEY_G, "command_stop": KEY_S, "command_return": KEY_V, "command_build": KEY_B, "command_repair": KEY_R, "command_capture": KEY_C, "command_drop": KEY_X, "command_refuel": KEY_T, "command_deploy": KEY_D, "command_cancel": KEY_X, "command_pause": KEY_P, "command_focus_assigned": KEY_F,
		"produce_infantry": KEY_I, "produce_depot_truck": KEY_U, "produce_cargo": KEY_C, "produce_train": KEY_T,
		"produce_scout": KEY_S, "produce_grenadier": KEY_G, "produce_tank": KEY_T, "produce_motorcycle": KEY_M, "produce_drone": KEY_D, "produce_ubermech": KEY_U,
		"control_group_1": KEY_1, "control_group_2": KEY_2, "control_group_3": KEY_3, "control_group_4": KEY_4, "control_group_5": KEY_5, "control_group_6": KEY_6, "control_group_7": KEY_7, "control_group_8": KEY_8, "control_group_9": KEY_9,
		# Moved from M and F, which now belong to Move and Focus assigned Depot.
		"camera_overview": KEY_O, "camera_focus_hq": KEY_BACKSPACE,
		"playtest_tools": KEY_F10, "map_show_all": KEY_ALT}
	for action in keys:
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": [event]})
	assert(ProjectSettings.save() == OK)
	print("Command Input Map saved")
	quit(0)
