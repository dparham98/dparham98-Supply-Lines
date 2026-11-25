extends Node3D
## Orbit the authored model for close inspection.

@onready var pivot: Node3D = $Pivot
@onready var camera: Camera3D = $Pivot/Camera
@onready var animation: AnimationPlayer = $Hound/AnimationPlayer

func _ready() -> void:
	if animation.has_animation("Rest"):
		animation.get_animation("Rest").loop_mode = Animation.LOOP_LINEAR
		animation.play("Rest")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		pivot.rotation.y -= event.relative.x * 0.008
		pivot.rotation.x = clampf(pivot.rotation.x - event.relative.y * 0.006, -1.15, 0.35)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.size = maxf(0.38, camera.size / 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = minf(4.5, camera.size * 1.12)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			var next := "Rest" if animation.current_animation == "Run" else "Run"
			if animation.has_animation(next):
				animation.get_animation(next).loop_mode = Animation.LOOP_LINEAR
				animation.play(next, 0.12)
		elif event.keycode == KEY_1:
			pivot.position = Vector3(0, 0.78, 0)
			camera.size = 2.0
		elif event.keycode == KEY_2:
			pivot.position = Vector3(0, 1.20, 0.55)
			camera.size = 0.8
