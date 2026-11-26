extends Node3D
## The look of a Grail Sentinel spell (docs/MIST_AND_SLOW.md), on the Visuals node of mist_cloud.tscn and
## slow_field.tscn. It only reads its gameplay parent: `seconds` (counting down to the end) and, when the parent has
## one, `radius`. From those it grows the authored meshes in over `in_seconds`, scales them to the radius, and sets
## the `draw_in` and `fade` instance uniforms their shaders use (assets/shaders/holy_mist.gdshader,
## assets/shaders/slow_sigil.gdshader), so the look always ends exactly when the spell does.
@export_range(0.05,3.0,0.05) var in_seconds := 0.5
@export_range(0.05,3.0,0.05) var out_seconds := 1.0
## Radius the meshes are authored at; the parent's `radius` scales them from it.
@export var authored_radius := 1.0
## Size the spread starts from, as a fraction, and how much of that growth applies to the height.
@export_range(0.0,1.0,0.05) var grow_from := 0.6
@export_range(0.0,1.0,0.05) var grow_height := 1.0
var _total := -1.0
var _meshes: Array[GeometryInstance3D] = []
func _ready() -> void:
	for node in find_children("*","GeometryInstance3D",true,false):
		_meshes.append(node)
	_show()
func _process(_delta: float) -> void:
	_show()
## How far in (0..1) and how much is left of the fade-out (1 until the last `out_seconds`).
func progress() -> Vector2:
	var spell := get_parent()
	var left: float = spell.get("seconds") if spell != null and spell.get("seconds") != null else 0.0
	if _total < 0.0: _total = maxf(left,0.01)
	return Vector2(clampf((_total-left)/in_seconds,0.0,1.0),clampf(left/out_seconds,0.0,1.0))
func _show() -> void:
	var p := progress()
	var radius = get_parent().get("radius") if get_parent() != null else null
	var spread: float = (radius if radius != null else authored_radius)/authored_radius
	var grow := lerpf(grow_from,1.0,1.0-pow(1.0-p.x,3.0))
	scale = Vector3(spread*grow,lerpf(1.0,grow,grow_height),spread*grow)
	var fade := minf(smoothstep(0.0,1.0,p.x),p.y)
	for mesh in _meshes:
		mesh.set_instance_shader_parameter(&"draw_in",p.x)
		mesh.set_instance_shader_parameter(&"fade",fade)
