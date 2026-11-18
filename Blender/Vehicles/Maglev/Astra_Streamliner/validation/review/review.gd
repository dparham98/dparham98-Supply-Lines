@tool
extends Node3D

const TeamPaint := preload("res://scripts/components/team_paint.gd")
const SHOTS := [
    ["teams", "Team comparison", "pair", 11.0, 42.0, -65.0],
    ["hero", "Industrial Streamliner", "red", 5.65, 23.0, -55.0],
    ["side", "Side elevation", "red", 6.1, 0.0, -90.0],
    ["elevated", "Upper shoulders and spine", "red", 6.9, 55.0, -61.0],
    ["match_new", "Redesigned train", "red", 8.0, 45.0, -69.0],
    ["match_old", "Original train", "old", 8.0, 45.0, -69.0],
    ["match_truck", "Cargo truck", "truck", 8.0, 45.0, -69.0],
    ["game", "Balanced Skirmish gameplay distance", "yard", 72.0, 50.0, -66.0],
    ["mask_new_side", "Streamliner silhouette · side", "red", 8.0, 0.0, -90.0],
    ["mask_truck_side", "Truck silhouette · side", "truck", 8.0, 0.0, -90.0],
    ["mask_new_roof", "Streamliner silhouette · elevated", "red", 8.0, 50.0, -69.0],
    ["mask_truck_roof", "Truck silhouette · elevated", "truck", 8.0, 50.0, -69.0],
]
@onready var cam: Camera3D = $Camera
@onready var original_environment: Environment = $Lighting/AmbientSky.environment
var mask_environment := Environment.new()
var profile_environment: Environment
var mask_material := StandardMaterial3D.new()
var front_blue := false
var back_red := false
var cargo_raised := false
var indicator_rest := {}
var shot := 0

func _ready() -> void:
    mask_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mask_material.albedo_color = Color.BLACK
    mask_environment.background_mode = Environment.BG_COLOR
    mask_environment.background_color = Color.WHITE
    profile_environment = original_environment.duplicate()
    profile_environment.background_color = Color(0.68, 0.72, 0.72)
    for car in [$Red/Model, $Blue/Model]:
        var indicator: Node3D = car.find_child("cargo_car_indicator", true, false)
        if indicator:
            indicator_rest[indicator] = indicator.position
    _assign()
    _show(0)
    if not Engine.is_editor_hint() and "--capture" in OS.get_cmdline_user_args():
        _capture.call_deferred()

func _assign() -> void:
    var red_count := TeamPaint.apply($Red/Model, "player" if front_blue else "enemy")
    var blue_count := TeamPaint.apply($Blue/Model, "enemy" if back_red else "player")
    TeamPaint.apply($Original/Model, "enemy")
    TeamPaint.apply($Truck/Model, "enemy")
    print("REVIEW TEAM SURFACES red=", red_count, " blue=", blue_count)

func _unhandled_key_input(event: InputEvent) -> void:
    if Engine.is_editor_hint(): return
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_RIGHT, KEY_SPACE: _show(posmod(shot + 1, SHOTS.size()))
            KEY_LEFT: _show(posmod(shot - 1, SHOTS.size()))
            KEY_R:
                front_blue = not front_blue
                TeamPaint.apply($Red/Model, "player" if front_blue else "enemy")
            KEY_B:
                back_red = not back_red
                TeamPaint.apply($Blue/Model, "enemy" if back_red else "player")
            KEY_L:
                cargo_raised = not cargo_raised
                for indicator: Node3D in indicator_rest:
                    indicator.position = indicator_rest[indicator] + Vector3.UP * (0.32 if cargo_raised else 0.0)
            KEY_H: $HUD.visible = not $HUD.visible

func _show(index: int) -> void:
    shot = index
    var spec: Array = SHOTS[index]
    var group: String = spec[2]
    var mask: bool = str(spec[0]).begins_with("mask")
    var profile: bool = spec[0] == "side"
    $Red.visible = group in ["red", "pair", "yard"]
    $Blue.visible = group in ["pair", "yard"]
    $Original.visible = group in ["old", "yard"]
    $Truck.visible = group in ["truck", "yard"]
    $Red.position = Vector3.ZERO
    $Blue.position = Vector3.ZERO
    $Original.position = Vector3.ZERO
    $Truck.position = Vector3.ZERO
    if group == "pair":
        $Red.position = Vector3(-0.5,0,2.65)
        $Blue.position = Vector3(0.5,0,-2.65)
    if group == "yard":
        $Red.position = Vector3(-8.2,0,-5.5)
        $Blue.position = Vector3(8.2,0,-5.5)
        $Original.position = Vector3(-8.2,0,7.4)
        $Truck.position = Vector3(8.2,0,7.4)
    for unit in [$Red, $Blue, $Original, $Truck]:
        unit.rotation_degrees.y = float(spec[5]) + (180.0 if unit == $Truck else 0.0)
        if unit.has_node("Rails"):
            unit.get_node("Rails").visible = not mask and not profile
            unit.get_node("YardExtensions").visible = group == "yard"
        for mesh in unit.get_node("Model").find_children("*", "MeshInstance3D", true, false):
            mesh.material_override = mask_material if mask else null
    $Ground.visible = not mask and group != "yard" and not profile
    $GameplayGround.visible = group == "yard"
    $StudioFill.visible = group != "yard" and not mask
    $Lighting/AmbientSky.environment = mask_environment if mask else original_environment
    if profile: $Lighting/AmbientSky.environment = profile_environment
    $Lighting/Sun.directional_shadow_max_distance = 340.0 if group == "yard" else 38.0
    var pitch := deg_to_rad(float(spec[4]))
    var target := Vector3(0,1.18,0)
    if group == "yard": target = Vector3.ZERO
    var distance := 110.0 if group == "yard" else 18.0
    cam.position = target + distance * Vector3(0,sin(pitch),cos(pitch))
    cam.rotation = Vector3(-pitch,0,0)
    cam.size = spec[3]
    $HUD/Controls.text = "%s     ·     ← → views     R front paint     B back paint     L cargo     H controls" % spec[1]

func _capture() -> void:
    var args := OS.get_cmdline_user_args()
    var output := args[args.find("--capture") + 1]
    if DirAccess.make_dir_recursive_absolute(output) != OK:
        push_error("Cannot create capture directory " + output)
        get_tree().quit(1)
        return
    $HUD.visible = false
    for i in SHOTS.size():
        _show(i)
        for k in 6:
            await RenderingServer.frame_post_draw
        var path := output.path_join(str(SHOTS[i][0]) + ".png")
        var image := get_viewport().get_texture().get_image()
        if image == null or image.save_png(path) != OK:
            push_error("Capture failed " + path)
            get_tree().quit(1)
            return
        print("CAPTURED ", path, " ", image.get_size())
        var variant := ""
        var key := KEY_NONE
        match SHOTS[i][0]:
            "teams":
                variant = "front_recolored.png"
                key = KEY_R
            "elevated":
                variant = "loaded_indicator.png"
                key = KEY_L
        if key != KEY_NONE:
            var toggle := InputEventKey.new()
            toggle.keycode = key
            toggle.pressed = true
            _unhandled_key_input(toggle)
            for k in 6:
                await RenderingServer.frame_post_draw
            var changed := get_viewport().get_texture().get_image()
            if changed.save_png(output.path_join(variant)) != OK:
                push_error("Cannot save " + variant)
                get_tree().quit(1)
                return
            _unhandled_key_input(toggle)
    get_tree().quit()
