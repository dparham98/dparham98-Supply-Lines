extends "res://scripts/gameplay/air_balloon.gd"
## The chartered Sky-Pavilion (docs/ROUND3_SKY_PAVILION.md): a Keep's Found Keep (P) sends one to land it has explored.
## It lifts off the Keep's rooftop dock, cruises at `pavilion_cruise_height` straight to the site and lands. If the
## site is still good Keep land (DepotNetwork.found_keep) it unfolds into an empty Keep with a Forester Maiden at its
## gate; if the site is blocked by then, it sets down 50 Wood and 50 Iron as crates and the Maiden beside them. Its
## housing passes to the Maiden. Shot down, it drops nothing. Like the balloon it takes no orders.
const WOOD_CRATES := 2
const IRON_CRATES := 2
func _ready() -> void:
	super._ready()
	add_to_group("sky_pavilions")
func cruise_height() -> float:
	return RULES.pavilion_cruise_height
func _fly() -> void:
	super._fly()
	state = "Flying to found a Keep"
func cargo_text() -> String:
	return "a Keep"
func _land() -> void:
	landed = true
	var keep: Node3D = game.get_node("DepotNetwork").found_keep(destination,team)
	var ground = game.ground
	var spot: Vector2i
	if keep != null:
		spot = ProductionExit.find_cell(ground,keep.global_position,keep.footprint,MobilityRules.Layer.GROUND)
		game.notify("Sky-Pavilion founded %s." % keep.name,team)
	else:
		var cell = ground.get_tile_at_position(global_position)
		for i in range(WOOD_CRATES+IRON_CRATES):
			var free = CrateYard.free_cell(get_tree(),global_position,0,8)
			if free != null: CrateYard.spawn(get_tree(),free,&"wood" if i < WOOD_CRATES else &"iron",ResourceStockpile.CRATE,team)
		spot = ground.nearest_actor_cell(cell if cell != null else Vector2i.ZERO,MobilityRules.Layer.GROUND,"")
		game.notify("The Sky-Pavilion's site was blocked: it set down %d Wood and %d Iron and a Forester Maiden." % [WOOD_CRATES*ResourceStockpile.CRATE,IRON_CRATES*ResourceStockpile.CRATE],team)
	remove_from_group("units")
	remove_from_group("enemies")
	if spot.x >= 0:
		var maiden: Node3D = load("res://scenes/gameplay/forester_maiden.tscn").instantiate()
		maiden.team = team
		maiden.position = ground.tile_to_world(spot)
		game.get_node("Entities/Units").add_child(maiden,true)
	queue_free()
