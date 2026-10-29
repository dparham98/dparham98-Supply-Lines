extends Node3D
# Numbered markers for the current and queued order destinations of selected player units.
# Markers are pooled instances of the authored marker scene.
@export var marker_scene: PackedScene
var markers: Array[Node3D] = []
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
func _process(_delta: float) -> void:
	var points: Array = []
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team != "player" or not unit.is_selected: continue
		var index := 0
		for point in unit.waypoint_points():
			index += 1
			points.append([point,index])
	while markers.size() < points.size():
		var marker := marker_scene.instantiate()
		add_child(marker)
		markers.append(marker)
	for i in markers.size():
		markers[i].visible = i < points.size()
		if i < points.size():
			markers[i].global_position = Vector3(points[i][0].x,0,points[i][0].z)
			markers[i].get_node("Order").text = str(points[i][1])
func visible_count() -> int:
	return markers.filter(func(marker): return marker.visible).size()
