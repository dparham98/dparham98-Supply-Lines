extends Node3D
## The Temple of Science placeholder model (docs/TEMPLE_OF_SCIENCE.md): while research is under way the
## armillary over the dome turns and its orb glows brighter.
@export var spin_speed := 0.9
@export var idle_glow := 0.6
@export var research_glow := 3.0
var _active := false
var _glow: StandardMaterial3D
func _ready() -> void:
	# Each Temple brightens its own orb, so the saved material is copied onto this one.
	var orb := get_node_or_null("Armillary/Orb") as MeshInstance3D
	if orb != null and orb.mesh != null and orb.mesh.surface_get_material(0) is StandardMaterial3D:
		_glow = orb.mesh.surface_get_material(0).duplicate()
		orb.set_surface_override_material(0,_glow)
func show_research(active: bool) -> void:
	_active = active
func _process(delta: float) -> void:
	if _active: $Armillary.rotate_y(spin_speed*delta)
	if _glow != null: _glow.emission_energy_multiplier = lerpf(_glow.emission_energy_multiplier,research_glow if _active else idle_glow,minf(1.0,delta*3.0))
