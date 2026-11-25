extends SceneTree
## Renders the HUD's unit and building images from the game's own models (docs/HUD_RENDERS.md). Run it with a
## window, from the project folder:
##   Godot --path . --script res://scripts/tools/render_hud_images.gd
## Each entry's gameplay scene is loaded and its Visuals (the saved model, in the player's team paint) is lit and
## shot in a world of its own. It writes:
##   assets/ui/renders/<id>.png         256 × 256 three-quarter view on a clear background: the selection icon and
##                                     the group portraits
##   assets/ui/portraits/<id>.png       a closer view, up to 340 × 400, cut to what is drawn, on a clear
##                                     background: the portrait frame
##   assets/ui/command_cards/sl_<card>.png  the production and build tiles: the render inside the card's frame
## Pass ids after `--` to render only those.
const TeamPaint = preload("res://scripts/components/team_paint.gd")
const HUD = preload("res://scripts/gameplay/skirmish_hud.gd")
## id: [gameplay scene, production card or "", build card or "", yaw of the view in degrees, portrait framing].
## Portrait framing: the share of the model's height, from the top, the portrait shows (1 is the whole model).
const ENTRIES := {
	"infantry": ["res://scenes/gameplay/infantry.tscn","produce_infantry","",35.0,0.55],
	"scout": ["res://scenes/gameplay/scout.tscn","produce_scout","",35.0,0.55],
	"grenadier": ["res://scenes/gameplay/grenadier.tscn","produce_grenadier","",35.0,0.55],
	"hostile": ["res://scenes/gameplay/hostile.tscn","","",35.0,0.6],
	"ubermech": ["res://scenes/gameplay/ubermech.tscn","produce_ubermech","",35.0,0.6],
	"tank": ["res://scenes/gameplay/tank.tscn","produce_tank","",35.0,1.0],
	"motorcycle": ["res://scenes/gameplay/motorcycle.tscn","produce_motorcycle","",55.0,1.0],
	"drone": ["res://scenes/gameplay/drone.tscn","produce_drone","",35.0,1.0],
	"cargo": ["res://scenes/gameplay/cargo_vehicle.tscn","produce_cargo","",40.0,1.0],
	"truck": ["res://scenes/gameplay/depot_truck.tscn","produce_truck","",40.0,1.0],
	"train": ["res://scenes/gameplay/train.tscn","produce_train","",40.0,1.0],
	"depot": ["res://scenes/gameplay/depot.tscn","","build_depot",35.0,1.0],
	"barracks": ["res://scenes/gameplay/barracks.tscn","","build_barracks",35.0,1.0],
	"tank_factory": ["res://scenes/gameplay/tank_factory.tscn","","build_factory",35.0,1.0],
	"generator": ["res://scenes/gameplay/energy_generator.tscn","","build_generator",35.0,1.0],
	"mine": ["res://scenes/gameplay/site_mine.tscn","","build_mine",20.0,1.0],
	"pithead": ["res://scenes/gameplay/iron_mine.tscn","","build_coal_mine",35.0,1.0],
	"temple": ["res://scenes/gameplay/temple_of_science.tscn","","build_temple",215.0,1.0], # its door faces +Z
}
## More cards made from an entry's render (docs/TEMPLE_OF_SCIENCE.md): the Temple's Mining Trains research shows the
## train, and the train's Mine iron order the portal mine.
## Cards drawn in Blender (Blender/UI/SpellCards/render_spell_cards.py) and only framed here: the Grail Sentinel's
## Mist and Slow and the Forge's Slow research (docs/MIST_AND_SLOW.md). Asked for with the id "spell_cards".
const SPELL_CARDS := ["mist","slow","research_slow"]
const SPELL_CARD_PATH := "res://Blender/UI/SpellCards/renders/%s.png"
const EXTRA_CARDS := {"train": ["research_mining_trains"], "mine": ["mine_iron"]}
## The card whose frame a new card copies before its first render.
const CARD_TEMPLATE := "res://assets/ui/command_cards/sl_build_barracks.png"
const ICON_SIZE := Vector2i(256,256)
const PORTRAIT_SIZE := Vector2i(340,400)
const CARD_SIZE := 128
## Width of the card's frame kept from the existing card image, in pixels.
const CARD_BORDER := 14
var viewport: SubViewport
var camera: Camera3D
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var only := OS.get_cmdline_user_args()
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.62,0.6,0.58)
	environment.environment.ambient_light_energy = 0.55
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	viewport.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50,-35,0)
	key.light_energy = 1.35
	key.shadow_enabled = true
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25,150,0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.85,0.9,1.0)
	viewport.add_child(rim)
	camera = Camera3D.new()
	camera.fov = 26
	viewport.add_child(camera)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui/renders"))
	for id in ENTRIES:
		if not only.is_empty() and not only.has(id): continue
		await render(id,ENTRIES[id])
	if only.is_empty() or only.has("spell_cards"):
		for spell_card in SPELL_CARDS:
			var art := Image.load_from_file(ProjectSettings.globalize_path(SPELL_CARD_PATH % spell_card))
			art.convert(Image.FORMAT_RGBA8)
			card_image("res://assets/ui/command_cards/sl_%s.png" % spell_card,trimmed(art,ICON_SIZE))
			print("framed ",spell_card)
	print("HUD_RENDERS_DONE")
	quit()
## The entry's Visuals, cut from its gameplay scene so the gameplay script never runs.
func model_of(path: String) -> Node3D:
	var actor: Node = load(path).instantiate()
	var visuals: Node3D = actor.get_node("Visuals")
	actor.remove_child(visuals)
	actor.free()
	_strip(visuals,visuals)
	return visuals
## Markers, labels and effects are not part of the picture.
func _strip(node: Node, top: Node) -> void:
	for child in node.get_children():
		var hidden: bool = child.name in [&"TeamMarker",&"Label",&"SelectionRing"] or child is Label3D or child is GPUParticles3D or child is CPUParticles3D
		if child is GeometryInstance3D:
			var mesh = child.get("mesh")
			if mesh != null:
				for i in mesh.get_surface_count():
					var material = mesh.surface_get_material(i)
					if material != null and str(material.resource_name).begins_with("fx_"): hidden = true
		if hidden: child.visible = false
		_strip(child,top)
func bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in node.find_children("*","VisualInstance3D",true,false):
		if not mesh.is_visible_in_tree() or not (mesh is GeometryInstance3D): continue
		var part: AABB = mesh.global_transform*mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box
func shoot(size: Vector2i) -> Image:
	viewport.size = size
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
## Frames `box` (in view of `yaw`, from 28° above) to fill `fill` of the picture's height and width.
func frame_box(box: AABB, yaw: float, aspect: float, fill: float) -> void:
	# Models face -Z, so the view is from that side.
	var direction := Vector3(sin(deg_to_rad(yaw)),0,-cos(deg_to_rad(yaw)))*cos(deg_to_rad(28))+Vector3.UP*sin(deg_to_rad(28))
	var center := box.get_center()
	var radius := box.size.length()*0.5
	var vertical := deg_to_rad(camera.fov)*0.5
	var horizontal := atan(tan(vertical)*aspect)
	var distance := radius/sin(minf(vertical,horizontal))/fill
	camera.global_position = center+direction*distance
	camera.look_at(center,Vector3.UP)
func render(id: String, entry: Array) -> void:
	var model := model_of(entry[0])
	viewport.add_child(model)
	TeamPaint.apply(model.get_node_or_null("Model"),"player")
	for player in model.find_children("*","AnimationPlayer",true,false):
		for clip in ["idle","Idle","idle_loop"]:
			if player.has_animation(clip): player.play(clip); player.seek(0.4,true); break
	await process_frame
	var box := bounds(model)
	# Icon: the whole model, three-quarter view, clear background.
	frame_box(box,entry[3],1.0,0.98)
	var icon := await shoot(ICON_SIZE)
	icon = trimmed(icon,ICON_SIZE)
	icon.save_png("res://assets/ui/renders/%s.png" % id)
	# Portrait: the top share of the model, closer, on a clear ground. The frame shows it whole and centred, on
	# its own background, at any width (the frame is 204 px tall and 172–812 px wide).
	var top := box
	var share: float = entry[4]
	top.position.y += box.size.y*(1.0-share)
	top.size.y = box.size.y*share
	frame_box(top,entry[3]-10.0,float(PORTRAIT_SIZE.x)/PORTRAIT_SIZE.y,1.7 if share < 1.0 else 1.2)
	var portrait := await shoot(PORTRAIT_SIZE)
	# Cut to what is drawn, so a long vehicle fills the frame's height as a figure does.
	var used := portrait.get_used_rect().grow(6).intersection(Rect2i(Vector2i.ZERO,portrait.get_size()))
	if used.size.x > 0 and used.size.y > 0: portrait = portrait.get_region(used)
	# A portrait composed for the frame by hand (the Deforester's, from Blender) is kept.
	if not HUD.COMPOSED_PORTRAITS.has(id): portrait.save_png("res://assets/ui/portraits/%s.png" % id)
	# Cards: the render inside the card's own frame.
	for card in [entry[1],entry[2]]+EXTRA_CARDS.get(id,[]):
		if not card.is_empty(): card_image("res://assets/ui/command_cards/sl_%s.png" % card,icon)
	model.queue_free()
	await process_frame
	print("rendered ",id)
## Crops to the drawn pixels and centres them on a square of `size`, so every icon fills its tile alike.
func trimmed(image: Image, size: Vector2i) -> Image:
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0: return image
	var cropped := image.get_region(used)
	var scale := minf(size.x*0.94/used.size.x,size.y*0.94/used.size.y)
	cropped.resize(maxi(1,roundi(used.size.x*scale)),maxi(1,roundi(used.size.y*scale)),Image.INTERPOLATE_LANCZOS)
	var out := Image.create_empty(size.x,size.y,false,Image.FORMAT_RGBA8)
	out.blit_rect(cropped,Rect2i(Vector2i.ZERO,cropped.get_size()),(size-cropped.get_size())/2)
	return out
## Keeps the card's frame and ground and puts the render where its glyph was.
func card_image(path: String, icon: Image) -> void:
	var card := Image.load_from_file(ProjectSettings.globalize_path(path if FileAccess.file_exists(path) else CARD_TEMPLATE))
	card.convert(Image.FORMAT_RGBA8)
	if card.get_width() != CARD_SIZE: card.resize(CARD_SIZE,CARD_SIZE,Image.INTERPOLATE_LANCZOS)
	var ground := card.get_pixel(CARD_BORDER+2,CARD_BORDER+2)
	card.fill_rect(Rect2i(CARD_BORDER,CARD_BORDER,CARD_SIZE-CARD_BORDER*2,CARD_SIZE-CARD_BORDER*2),ground)
	var inner := CARD_SIZE-CARD_BORDER*2-4
	var art := icon.duplicate()
	art.resize(inner,inner,Image.INTERPOLATE_LANCZOS)
	card.blend_rect(art,Rect2i(0,0,inner,inner),Vector2i(CARD_BORDER+2,CARD_BORDER+2))
	card.save_png(path)
