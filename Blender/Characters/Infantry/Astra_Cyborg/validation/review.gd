extends Node3D

const Paint = preload("res://scripts/components/team_paint.gd")
const CLIPS = ["Rest", "Run", "Hack", "Shoot", "Die"]
@onready var left = $Red/Model
@onready var right = $Blue/Model
var left_team := "enemy"
var right_team := "player"
var clip_index := 0
var failures: Array[String] = []

func _ready() -> void:
    Paint.apply(left,left_team)
    Paint.apply(right,right_team)
    for model in [left,right]:
        model.set_process(false)
    play_clips()
    var args := OS.get_cmdline_user_args()
    if "--capture" in args:
        capture.call_deferred(args[args.find("--capture") + 1], "--baseline" in args)

func play_clips() -> void:
    for model in [left,right]:
        model.player.play(CLIPS[clip_index],0.10)
        model.player.seek(0.0,true)
        model._run_teeth(CLIPS[clip_index] == "Hack")
    $Help.text = "%s    ·    ← → action    A/D turn    R/B team" % CLIPS[clip_index]

func _process(delta: float) -> void:
    # Dedicated orbit keys allow turning the model during any clip.
    var turn := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
    if turn != 0:
        $Red.rotate_y(turn * delta * 1.8)
        $Blue.rotate_y(turn * delta * 1.8)
    for model in [left,right]:
        if model:
            model._update_flash_light()

func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_LEFT, KEY_RIGHT:
                clip_index = posmod(clip_index + (1 if event.keycode == KEY_RIGHT else -1), CLIPS.size())
                play_clips()
            KEY_R:
                left_team = "player" if left_team == "enemy" else "enemy"
                Paint.apply(left,left_team)
            KEY_B:
                right_team = "player" if right_team == "enemy" else "enemy"
                Paint.apply(right,right_team)

func expect(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)

func frame(clip: String, time: float, model) -> void:
    model.player.play(clip,0.0)
    model.player.seek(time,true)
    model.player.pause()
    model.skeleton.force_update_all_bone_transforms()
    model._update_flash_light()

func playback_checks() -> Dictionary:
    var skeleton: Skeleton3D = left.skeleton
    var animation_info := {}
    expect(skeleton != null, "Imported skeleton missing")
    if not skeleton:
        return {}
    for clip in CLIPS:
        expect(left.player.has_animation(clip), "Missing clip " + clip)
        if not left.player.has_animation(clip):
            continue
        var animation: Animation = left.player.get_animation(clip)
        var looped := animation.loop_mode == Animation.LOOP_LINEAR
        expect(looped == (clip in ["Rest","Run","Hack"]), clip + " has incorrect loop mode")
        # Compare actual local joint rotations with a later sample in each action.
        frame(clip,0.0,left)
        var angles: Array[Quaternion] = []
        for j in skeleton.get_bone_count():
            angles.append(skeleton.get_bone_pose_rotation(j))
        var max_swing := 0.0
        for fraction in [0.19,0.47,0.77]:
            frame(clip,animation.length*fraction,left)
            for j in angles.size():
                max_swing = maxf(max_swing,rad_to_deg(angles[j].angle_to(skeleton.get_bone_pose_rotation(j))))
        if clip != "Rest":
            expect(max_swing > 2.0,clip + " did not articulate the skeleton")
        animation_info[clip] = {"length_seconds":animation.length,"loops":looped,"joint_swing_degrees":max_swing}
    expect(skeleton.get_bone_count() == 22, "Expected 22 accepted bones")
    var flash := skeleton.find_bone("flash")
    var names := ["pistol","chainsaw","flash"]
    for bone in names:
        expect(skeleton.find_bone(bone) >= 0,"Missing attachment bone " + bone)
    expect(left.flash_light != null and left.teeth != null, "Flash light or animated teeth missing")
    expect(left.has_node("Rig/infantry_rig2/Skeleton3D/eye_lens_rig"),"Expected emissive lens mesh")
    expect(left.has_node("Rig/infantry_rig2/Skeleton3D/chainsaw_rig"),"Expected saw housing mesh")
    expect(left.has_node("Rig/infantry_rig2/Skeleton3D/flash/Muzzle flash"),"Expected animated flash mesh")
    left.set_motion(&"run",2.0)
    left._process(1.0/60.0)
    expect(left.current_clip() == &"Run","Animator did not select Run")
    left.set_motion(&"work",1.2)
    left._process(1.0/60.0)
    expect(left.current_clip() == &"Hack","Animator did not select Hack")
    if left.teeth:
        expect(is_equal_approx(left.teeth.get_instance_shader_parameter("speed"),left.teeth_speed),"Teeth shader stayed off")
    var flash_on := 0.0
    var flash_rest := 0.0
    if flash >= 0 and left.flash_light:
        frame("Rest",0.0,left)
        flash_rest = left.flash_light.light_energy
        left.play_action(&"shoot",left.shot_lead())
        skeleton.force_update_all_bone_transforms()
        left._update_flash_light()
        flash_on = left.flash_light.light_energy
        expect(flash_on > 0.5 and flash_rest < 0.05,"Flash did not brighten during the shoot event")
    expect(left.has_gun_line(),"Animator could not sample the pistol socket")
    expect(left.has_death_clip(),"Animator could not find its death clip")
    return {"bones":skeleton.get_bone_count(),"clips":animation_info,
        "muzzle_light_rest":flash_rest,"muzzle_light_shoot":flash_on,
        "attachment_bones":names,"animator_path":left.get_script().resource_path}

func check_paint(model, expected: Material) -> int:
    var targets := 0
    for slot in model.find_children("*","MeshInstance3D",true,false):
        if slot.mesh == null: continue
        for surface in slot.mesh.get_surface_count():
            var base: Material = slot.mesh.surface_get_material(surface)
            if base and base.resource_name == "team_color":
                targets += 1
                expect(slot.get_surface_override_material(surface) == expected,"Paint did not resolve on " + str(slot.name))
            else:
                expect(slot.get_surface_override_material(surface) == null,"Unrelated material was recoloured")
    return targets

func snapshot() -> Image:
    for i in range(5):
        await RenderingServer.frame_post_draw
    return get_viewport().get_texture().get_image()

func paint_pixels(before: Image, left_changed: Image, right_changed: Image) -> Dictionary:
    var changed_left := 0
    var tested_right := 0
    var changed_right := 0
    var max_difference := 0.0
    var max_left_difference := 0.0
    for y in before.get_height():
        for x in before.get_width():
            var c := before.get_pixel(x,y)
            var next := left_changed.get_pixel(x,y)
            var other := right_changed.get_pixel(x,y)
            if x < before.get_width()/2 and c.r > c.b*1.25 and c.r > c.g*1.2 and next.b > next.r*1.25:
                changed_left += 1
                max_left_difference = maxf(max_left_difference, maxf(absf(c.r-other.r),maxf(absf(c.g-other.g),absf(c.b-other.b))) * 255)
            # A second controlled reassignment identifies pixels belonging to the
            # blue paint itself, including the shaded portions of that material.
            if x > before.get_width()/2 and c.b > c.r*1.25 and c.b > c.g*1.07 and other.r > other.b*1.25:
                tested_right += 1
                var difference := maxf(absf(c.r-next.r),maxf(absf(c.g-next.g),absf(c.b-next.b))) * 255
                max_difference = maxf(difference,max_difference)
                if difference > 4.01:
                    changed_right += 1
    return {"red_pixels_reassigned_blue":changed_left,"blue_pixels_reassigned_red":tested_right,
        "right_max_delta_when_left_changed_255":roundi(max_difference),
        "left_max_delta_when_right_changed_255":roundi(max_left_difference),
        "blue_pixels_changed_over_four_levels":changed_right}

func capture(folder: String, baseline: bool) -> void:
    $Help.hide()
    var result := playback_checks()
    if not failures.is_empty():
        print("CHECK_FAILURES ",failures)
        get_tree().quit(1)
        return
    frame("Rest",0.0,left)
    frame("Rest",0.0,right)
    var surfaces := check_paint(left,Paint.paint_for("enemy"))
    expect(check_paint(right,Paint.paint_for("player")) == surfaces,"Instances have different team surface counts")
    if not baseline:
        expect(surfaces > 0,"No team_color material")
    var pair := await snapshot()
    expect(pair.save_png(folder.path_join("teams.png")) == OK, "Could not save team image")
    Paint.apply(left,"player")
    check_paint(right,Paint.paint_for("player"))
    var after := await snapshot()
    Paint.apply(left,"enemy")
    Paint.apply(right,"enemy")
    check_paint(left,Paint.paint_for("enemy"))
    var right_changed := await snapshot()
    Paint.apply(right,"player")
    var pixels := paint_pixels(pair,after,right_changed)
    if not baseline:
        expect(pixels.red_pixels_reassigned_blue > 30 and pixels.blue_pixels_reassigned_red > 30, "Paint independence was not visible")
        expect(pixels.blue_pixels_changed_over_four_levels == 0,"Changing the left actor changed the right actor")
        expect(pixels.left_max_delta_when_right_changed_255 <= 4,"Changing the right actor changed the left actor")
    # Capture the adopted joints at useful instants, independent of rendering speed.
    frame("Hack",0.49,left)
    frame("Run",0.21,right)
    var moving := await snapshot()
    expect(moving.save_png(folder.path_join("poses.png")) == OK,"Could not save animated contact")
    frame("Rest",0.0,left)
    frame("Rest",0.0,right)
    $Red.rotate_y(PI)
    $Blue.rotate_y(PI)
    var rear := await snapshot()
    expect(rear.save_png(folder.path_join("rear.png")) == OK,"Could not save rear inspection")
    result["team_surfaces_per_actor"] = surfaces
    result["paint_framebuffer"] = pixels
    result["failures"] = failures
    var output := FileAccess.open(folder.path_join("checks.json"),FileAccess.WRITE)
    output.store_string(JSON.stringify(result,"  "))
    output.close()
    print("CYBORG_REVIEW ",result)
    get_tree().quit(0 if failures.is_empty() else 1)
