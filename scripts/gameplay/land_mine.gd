extends Node3D
## A Derailer's land mine (item 9 of the balance handoff, docs/MINES.md). It arms `arm_seconds` after it is laid
## and is then hidden: the other side sees it, and can shoot it, only while one of its detectors covers it
## (Detection). An enemy ground unit within `trigger_radius` sets it off: `damage` to that unit, `splash_share` of
## it to the other side's ground units within `splash_radius`. A train that runs onto it derails instead.
@export var rules: MineRules
var team := "player"
var health := 20
var max_health := 20
var armed := false
var _age := 0.0
var _look := 0.0
var _gone := false
## The side whose view is drawn (the fog of war's viewer, else the player).
var _viewer := "player"
func _ready() -> void:
	add_to_group("land_mines")
	health = rules.health
	max_health = rules.health
	var fog := get_tree().get_first_node_in_group("fog_of_war")
	if fog != null: _viewer = fog.viewer
	preload("res://scripts/components/team_paint.gd").apply(_model(),team)
	_show_model()
func _process(delta: float) -> void:
	if _gone: return
	_age += delta
	if not armed and _age >= rules.arm_seconds: armed = true
	var model := _model()
	if model != null and model.has_method("set_age"): model.set_age(_age,rules.arm_seconds)
	_look -= delta
	if _look > 0.0: return
	_look = 0.1
	_show_model()
	if armed: _check_trigger()
## The model in the Visuals slot (scenes/models/land_mine_model.tscn).
func _model() -> Node3D:
	return get_node_or_null("Visuals/Model")
## Drawn or hidden for the viewer; an armed enemy mine its detectors cover gets the "spotted" ring.
func _show_model() -> void:
	visible = shown_to(_viewer)
	var model := _model()
	if model != null and model.has_method("set_detected"): model.set_detected(_viewer != team and armed and visible and detected_by(_viewer))
## Whether `viewer` may see it: its own side always; the other side before it arms (where its fog allows) and,
## once armed, only while one of its detectors covers it.
func shown_to(viewer: String) -> bool:
	if viewer == team: return true
	if not armed: return true
	return Detection.detects(self,viewer,global_position)
## Whether `side` may target it now (unit_agent.team_sees asks this for a mine).
func detected_by(side: String) -> bool:
	return side == team or not armed or Detection.detects(self,side,global_position)
func _enemy_ground(unit: Node) -> bool:
	if not is_instance_valid(unit) or unit.is_queued_for_deletion() or not unit.is_in_group("units"): return false
	if unit.team == team or unit.team == "neutral" or unit.health <= 0: return false
	return not (unit.has_method("mobility_layer") and unit.mobility_layer() == MobilityRules.Layer.AIR)
func _flat(point: Vector3) -> float:
	return Vector2(point.x-global_position.x,point.z-global_position.z).length()
func _check_trigger() -> void:
	for unit in get_tree().get_nodes_in_group("units"):
		if _enemy_ground(unit) and _flat(unit.global_position) <= rules.trigger_radius:
			explode(unit)
			return
	# A train runs over it along the track: its consist is long, so it is caught by the track it covers.
	for train in get_tree().get_nodes_in_group("rail_trains"):
		if train.get("team") == team or train.get("derailed") == true or train.health <= 0: continue
		if _flat(train.global_position) <= rules.trigger_radius+1.0:
			explode(train)
			return
## Goes off under `victim`.
func explode(victim: Node3D) -> void:
	if _gone: return
	_gone = true
	if victim.is_in_group("rail_trains") and victim.has_method("derail"): victim.derail()
	else: victim.take_damage(rules.damage)
	var share := roundi(rules.damage*rules.splash_share)
	for unit in get_tree().get_nodes_in_group("units"):
		if unit == victim or not _enemy_ground(unit): continue
		if _flat(unit.global_position) <= rules.splash_radius: unit.take_damage(share)
	_blast()
## Shot while detected.
func take_damage(amount: int) -> void:
	if _gone: return
	health = maxi(0,health-maxi(0,amount))
	if health <= 0:
		_gone = true
		_blast()
func _blast() -> void:
	var fx := get_node_or_null("Blast")
	if fx != null and fx.has_method("play"):
		remove_child(fx)
		get_parent().add_child(fx)
		fx.global_position = global_position
		fx.play()
		fx.player.animation_finished.connect(func(_clip: StringName) -> void: fx.queue_free(),CONNECT_ONE_SHOT)
	queue_free()
