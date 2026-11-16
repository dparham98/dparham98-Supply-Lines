extends SceneTree
# Headless: an Infantry builder starts work as soon as it touches the build site, from whichever side it comes
# (docs/BUILDER_TOUCH.md), instead of walking round to a standing spot first.
const Approach := preload("res://scripts/units/interaction_approach.gd")
var game: Node3D
var ground: Node3D
var network: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func step(nodes: Array, seconds: float, done: Callable) -> bool:
	for i in range(ceili(seconds*60)):
		for node in nodes:
			if is_instance_valid(node): node._process(1.0/60)
		if done.call(): return true
	return false
func run() -> void:
	game = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	ground = game.ground
	network = game.get_node("DepotNetwork")
	var depot: Node3D = game.depot
	depot.set_process(false)
	# A Barracks plan in the Depot's range with open ground all round it.
	var spec: Dictionary = network.plan_spec(&"barracks")
	var plan: Node3D
	for r in range(8,24):
		for angle in range(0,360,15):
			var point: Vector3 = depot.global_position+Vector3(cos(deg_to_rad(angle)),0,sin(deg_to_rad(angle)))*r
			var start: Vector2i = network.footprint_start(point,spec.size)
			var ring := Rect2i(start-Vector2i(6,6),spec.size+Vector2i(12,12))
			if not network.plan_terrain_valid(start,spec.size,&"barracks") or network.plan_overlaps(start,spec.size): continue
			var open := true
			for z in range(ring.position.y,ring.end.y):
				for x in range(ring.position.x,ring.end.x):
					if not ground.can_traverse(Vector2i(x,z),MobilityRules.Layer.GROUND,""): open = false
			if not open: continue
			plan = network.queue_plan(point,&"barracks")
			if plan != null: break
		if plan != null: break
	if not check(plan != null,"No open Barracks site near the Depot"): return
	plan.set_process(false)
	var rect: Rect2i = plan.footprint()
	# From a corner, coming diagonally, and from the middle of a side.
	var approaches := {
		"corner": ground.tile_to_world(rect.end+Vector2i(4,4)),
		"side": ground.tile_to_world(Vector2i(rect.position.x+rect.size.x/2,rect.position.y-5)),
	}
	for side in approaches:
		var worker: Node3D = load("res://scenes/gameplay/infantry.tscn").instantiate()
		worker.team = "player"
		game.get_node("Entities/Units").add_child(worker)
		worker.global_position = approaches[side]
		worker.set_process(false)
		await process_frame
		var from: Vector3 = worker.global_position
		worker.command_construct(plan)
		var started := func(): return worker.state != "To build site" and worker.state != "Idle" and not worker.state.begins_with("Stepping")
		if not check(step([worker],30.0,started),"The %s builder never started: '%s'" % [side,worker.state]): return
		var edge := Approach.distance_to_rect(ground,worker.global_position,rect)
		if not check(edge > 0.0 and edge <= Approach.TOUCH+0.05,"The %s builder should start touching the site, %.2f m from its edge" % [side,edge]): return
		# It started on the side it came from: no farther from where it set out than the nearest touching point.
		var nearest := Approach.distance_to_rect(ground,from,rect)
		if not check(worker.global_position.distance_to(from) <= nearest+1.5,"The %s builder walked round the site: %.1f m for a %.1f m approach" % [side,worker.global_position.distance_to(from),nearest]): return
		if not check(worker._route.is_empty(),"The %s builder should stop walking once it touches the site" % side): return
		# It stays put while it works.
		var at: Vector3 = worker.global_position
		step([worker],2.0,func(): return false)
		if not check(worker.global_position.distance_to(at) < 0.3 and worker.order == "construct","The %s builder should keep working where it stands: '%s'" % [side,worker.state]): return
		worker.queue_free()
		await process_frame
	print("BUILDER_TOUCH_TEST_PASSED")
	quit(0)
