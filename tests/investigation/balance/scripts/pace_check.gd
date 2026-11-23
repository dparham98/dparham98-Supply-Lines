extends SceneTree
# Checks whether the Chapterhouse's production speed setting costs anything (it draws extra energy, and Knights units cost none).
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game: Node3D = load("res://scenes/maps/arthurian_skirmish.tscn").instantiate()
	root.add_child(game)
	for i in range(5): await process_frame
	game.get_node("Interface").process_mode = Node.PROCESS_MODE_DISABLED
	var keep: Node3D = game.get_node("Entities/Buildings/Keep")
	var house: Node3D = game.get_node("Entities/Buildings/Chapterhouse")
	for power in [1.0,4.0]:
		house.set_power(power)
		var before := {"food": keep.food, "iron": keep.iron, "energy": keep.energy, "wood": keep.wood}
		var units_before := get_nodes_in_group("units").size()
		var ok: bool = house.request_unit(&"round_table_marine")
		var frames := 0
		while get_nodes_in_group("units").size() == units_before and frames < 30*30:
			await process_frame
			frames += 1
		print("power %.1fx: queued %s · Round Table Marine out after %.2f s · Keep paid %d Food, %d Iron, %d Energy, %d Wood" % [power,ok,frames/30.0,before.food-keep.food,before.iron-keep.iron,before.energy-keep.energy,before.wood-keep.wood])
	quit()
