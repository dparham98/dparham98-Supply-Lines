extends Node3D
## Broken track left where a Derailer destroyed a piece (docs/DERAILER.md). It is not track: trains cannot run on it
## and it marks no ground. Its side rebuilds it from the Rail tile by clicking it (`RailNetwork.rebuild`), which lays
## the same piece in the same place; any track laid over it clears it too.
const MODELS := {"straight": "Straight", "curve": "Curve", "fork_left": "ForkLeft", "fork_right": "ForkRight"}
## The piece that was here.
@export_enum("straight","curve","fork_left","fork_right") var kind := "straight"
## The side whose line it was, the side that can rebuild it.
var team := ""
## The Depot that paid for the piece, the first choice to pay for it again.
var assigned_depot: Node3D
## Ground cells the piece covered.
var cells: Array[Vector2i] = []
@onready var network = get_tree().get_first_node_in_group("rail_network")
func _ready() -> void:
	add_to_group("rail_wrecks")
	for each in MODELS: get_node("Visuals/"+MODELS[each]).visible = each == kind
	cells = network.cells_for(kind,global_transform)
	# The spike that broke it stands in the middle of the piece.
	var probe: Node3D = network.probe(kind)
	$Visuals/Spike.position = probe.local_point(probe.length()*0.5)+Vector3.UP*0.3
## Whether the ground cell is under the wreck.
func covers(cell: Vector2i) -> bool:
	return cells.has(cell)
