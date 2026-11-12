extends Node3D
## The fenced construction site round a planned building (docs/CONSTRUCTION_SITE_MODEL.md). The saved site
## scene stands on the plan's footprint; this only recolours its lamps by the site's state, blinks them while
## Infantry build, sways the bunting (Idle) and clears the clutter away near the end of the build.
@export var player_path := NodePath("Rig/AnimationPlayer")
@export var idle_clip := &"Idle"
## Lamp colours: materials short, everything on site, and Infantry building.
@export var waiting_colour := Color(1.0,0.62,0.12)
@export var ready_colour := Color(0.35,0.95,0.45)
@export var building_colour := Color(0.45,0.78,1.0)
@export_range(0,16,0.1) var lamp_energy := 4.0
## Seconds for one on-off blink while building.
@export_range(0.1,4,0.05) var blink_period := 0.8
## Construction progress from which the sawhorse, planks, sand and tools are cleared away.
@export_range(0,1,0.05) var clear_props_at := 0.75
const WAITING := &"waiting"
const READY := &"ready"
const BUILDING := &"building"
@onready var player: AnimationPlayer = get_node_or_null(player_path)
var lamps: Array[MeshInstance3D] = []
var props: Array[Node3D] = []
## One material for this site's lamps, so recolouring one site leaves the others alone.
var lamp_material: StandardMaterial3D
var state := WAITING
var _clock := 0.0
func _ready() -> void:
	for node in find_children("*lamp_glass*","MeshInstance3D",true,false): lamps.append(node)
	for node in find_children("*prop_*","Node3D",true,false): props.append(node)
	lamp_material = StandardMaterial3D.new()
	lamp_material.emission_enabled = true
	lamp_material.roughness = 0.3
	for lamp in lamps: lamp.material_override = lamp_material
	if player != null and player.has_animation(idle_clip):
		player.play(idle_clip)
	_apply(true)
## waiting, ready or building, as the plan's grid tint.
func show_state(new_state: StringName) -> void:
	if new_state == state: return
	state = new_state
	_clock = 0.0
	_apply(true)
## Construction progress 0..1; the clutter goes once the building is nearly up.
func show_progress(fraction: float) -> void:
	for prop in props: prop.visible = fraction < clear_props_at
func lamp_colour() -> Color:
	if state == BUILDING: return building_colour
	if state == READY: return ready_colour
	return waiting_colour
## Whether the lamps are lit now; they blink only while building.
func lit() -> bool:
	return state != BUILDING or fmod(_clock,blink_period) < blink_period*0.5
func _process(delta: float) -> void:
	if state != BUILDING: return
	var was := lit()
	_clock += delta
	if lit() != was: _apply(false)
func _apply(_recolour: bool) -> void:
	var colour := lamp_colour()
	var on := lit()
	lamp_material.albedo_color = colour.lerp(Color.WHITE,0.35) if on else colour.darkened(0.6)
	lamp_material.emission = colour
	lamp_material.emission_energy_multiplier = lamp_energy if on else 0.0
