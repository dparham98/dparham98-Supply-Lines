class_name RailAnchor
extends RefCounted
## A pick on laid track while connecting (docs/RAIL_PLANNING.md, joining track): new track joins that line at
## one of its free ends, or at a fork laid in place of three straights, near where the player clicked.
## The piece clicked on; its line is where new track joins.
var piece: Node3D
## The click on the track, which the rail tool treats like a picked building's centre.
var global_position: Vector3
## Where new track can join, worked out once per network revision: see RailNetwork.join_candidates.
var candidates: Array[Dictionary] = []
var revision := -1
func _init(on: Node3D, at: Vector3) -> void:
	piece = on
	global_position = Vector3(at.x,0,at.z)
