extends SceneTree
func _initialize() -> void:
	for id in ["infantry", "scout", "grenadier", "tank", "motorcycle", "drone", "ubermech"]:
		var stats = load("res://assets/units/"+id+".tres")
		assert(stats is UnitStats and stats.validation_errors().is_empty())
		assert(stats.has_resolved_attack() == (id != "drone"))
	var unit = load("res://scenes/gameplay/infantry.tscn").instantiate()
	unit.apply_unit_stats()
	assert(unit.max_health == 55 and unit.move_speed == 2 and unit.attack_range == 5)
	assert(unit.attack_damage == 8 and unit.shot_interval == 1.0)
	assert(unit.vision == 7 and unit.energy_cost == 100 and unit.iron_cost == 20)
	unit.use_prototype_combat_for_unresolved_stats = false
	unit.apply_unit_stats()
	assert(unit._attack_enabled)
	unit.unit_stats = load("res://assets/units/drone.tres")
	unit.apply_unit_stats()
	assert(unit.max_health == 30 and not unit._attack_enabled)
	unit.free()
	print("UNIT_STATS_CHECKS_PASSED")
	quit()
