extends "res://scripts/units/infantry.gd"
func _ready() -> void:
	team = "enemy"
	add_to_group("enemies")
	super._ready()
