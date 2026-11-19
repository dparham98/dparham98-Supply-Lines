extends Node3D
## The stand supplies the actor properties read by the actual close-defence component.
@export var team := "player"
var health := 150
var game: Node


func _enter_tree() -> void:
	game = get_parent()


func take_damage(amount: int) -> void:
	# Range targets can be used repeatedly without reopening the project.
	health -= amount
	if health <= 0:
		health = 150
