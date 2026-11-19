extends SceneTree
# Headless: the placement guide (docs/PLACEMENT_GUIDE.md). No text follows the cursor; while laying rail the HUD's
# guide shows the three steps with the current one lit and the line about the track, and while placing a building
# it shows the placement colours with the one under the cursor lit. It hides otherwise, and never takes clicks.
const MAPS := ["res://scenes/maps/lakes_skirmish.tscn","res://scenes/maps/balanced_skirmish.tscn","res://scenes/maps/resource_skirmish.tscn","res://scenes/maps/mine_site_exercise.tscn"]
var game: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message); quit(1); return false
func lit(guide: Control) -> int:
	for i in range(3):
		if guide.get_node("Body/Steps/Step%d" % (i+1)).modulate == Color.WHITE: return i
	return -1
func run() -> void:
	for path in MAPS:
		var map: Node = load(path).instantiate()
		if not check(map.get_node_or_null("RailPreview/Status") == null,"%s: no rail label should follow the cursor" % path): return
		map.free()
	var preview: Node = load("res://scenes/gameplay/construction_preview.tscn").instantiate()
	if not check(preview.get_node_or_null("Status") == null,"No placement label should follow the cursor"): return
	preview.free()
	root.size = Vector2i(1280,900)
	game = load("res://scenes/maps/balanced_skirmish.tscn").instantiate()
	root.add_child(game)
	for frame in range(3): await process_frame
	game.set_process(false)
	var hud = game.get_node("Interface")
	hud.set_process(false)
	var rails = game.get_node("RailNetwork")
	var network = game.get_node("DepotNetwork")
	var guide: Control = hud.get_node("Bottom/Body/Row/Guide")
	var mouse_free := func(): return guide.mouse_filter == Control.MOUSE_FILTER_IGNORE and guide.find_children("*","Control",true,false).all(func(c): return c.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	if not check(mouse_free.call(),"The guide must let clicks through to the map"): return
	hud._process(0)
	var overlay = hud.get_node("MapOverlay")
	if not check(not guide.visible and hud.info.visible and overlay.status_for(game.depot).readout.is_empty(),"The guide and the Depot readout hide when nothing is being placed"): return
	# Rail: three steps.
	game.placing_rail = true
	hud._process(0)
	if not check(guide.visible and guide.get_node("Body/Title").text == "LAY RAIL" and lit(guide) == 0,"Laying rail shows the guide at step 1"): return
	if not check(not hud.info.visible and not hud.context.visible and guide.get_parent() == hud.get_node("Bottom/Body/Row"),"The guide sits in the bottom panel in place of the info columns"): return
	if not check(not overlay.status_for(game.depot).readout.is_empty(),"While building, the Depot shows its stock above it"): return
	if not check(guide.get_node("Body/Status").text == rails.route_status() and guide.get_node("Body/Steps/Arrow1").visible,"The guide shows the track line and the arrows"): return
	rails.pick_target(game.depot)
	hud._process(0)
	if not check(lit(guide) == 1,"After the first pick, step 2 is lit"): return
	var site: Node3D
	for r in range(30,90,6):
		site = network.queue_plan(game.depot.global_position+Vector3(r,0,0),&"generator")
		if site != null: break
	if not check(site != null,"No site for the second pick"): return
	rails.pick_target(site)
	hud._process(0)
	if not check(lit(guide) == 2 and guide.get_node("Body/Status").text == rails.route_status(),"After the second pick, step 3 is lit: %s" % guide.get_node("Body/Status").text): return
	game.placing_rail = false
	hud._process(0)
	if not check(not guide.visible,"Leaving rail hides the guide"): return
	# Placement: the colour key, with the state under the cursor lit.
	game.global_plan_kind = &"barracks"
	var point: Vector3 = game.depot.global_position+Vector3(0,0,24)
	network.update_global_preview(point)
	hud._process(0)
	if not check(guide.visible and guide.get_node("Body/Title").text == "PLAN BARRACKS","Placing shows the guide: %s" % guide.get_node("Body/Title").text): return
	if not check(guide.get_node("Body/Steps/Step1/Row/Swatch").visible and not guide.get_node("Body/Steps/Arrow1").visible,"Placement shows the colour key, not steps"): return
	if not check(lit(guide) == ["ok","short","blocked"].find(network.placement_state) and guide.get_node("Body/Status").text == network.placement_text,"The key lights the colour under the cursor (%s)" % network.placement_state): return
	# Off the map's buildable land it is red.
	network.update_global_preview(game.depot.global_position)
	hud._process(0)
	if not check(network.placement_state == "blocked" and lit(guide) == 2,"On the Depot itself it is red: %s" % network.placement_state): return
	game.global_plan_kind = &""
	hud._process(0)
	if not check(not guide.visible and hud.info.visible and hud.context.visible,"Leaving placement hides the guide and brings the info back"): return
	# The Build page alone also shows the Depot's stock.
	hud.global_build_open = true
	if not check(not overlay.status_for(game.depot).readout.is_empty(),"With the Build page open the Depot shows its stock"): return
	hud.global_build_open = false
	print("PLACEMENT_GUIDE_TEST_PASSED")
	quit(0)
