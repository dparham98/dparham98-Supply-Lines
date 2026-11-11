extends RefCounted
# Stands the sculpted landscape's scenery on its ground (docs/LANDSCAPE_LOOKDEV.md). Called by terrain_baker.gd when
# terrain.tscn has landscape settings. Every placement is decided from the map cells and a hash of the cell, so a
# change to the layout only changes the scenery around the cells that changed.
const MAP := 500
const WATER := 1
const DESERT := 2
const FOREST := 3
const MOUNTAIN := 4
## Scenery is batched in squares of this many metres so off-screen batches are not drawn.
const CHUNK := 64
## Height the cliff pieces are modelled at, in metres.
const CLIFF_HEIGHT := 4.5

var settings: LandscapeSettings
var builder
var cells: PackedByteArray
var baker
var root: Node3D
var patches := FastNoiseLite.new()
# scene -> {chunk -> [transforms, colours]}
var placed := {}

func add_to(root_: Node3D, cells_: PackedByteArray, settings_: LandscapeSettings, baker_) -> void:
	root = root_
	cells = cells_
	settings = settings_
	baker = baker_
	builder = load("res://scripts/tools/landscape_builder.gd").new()
	builder.setup(cells,settings)
	patches.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	patches.frequency = 0.06
	patches.seed = settings.scatter_seed
	var landscape := _group(root,"Landscape")
	_mesh(landscape,"Ground",settings.ground_mesh,true)
	_mesh(landscape,"Water",settings.water_mesh,false)
	_rocks()
	_ore()
	_plants()
	_emit(_group(landscape,"Scatter"))
	_forest()
	_emit(_group(landscape,"Forest"))

func covers(x: int, z: int) -> bool:
	return settings.region.has_point(Vector2i(x,z))

func replaces_ore() -> bool:
	return not settings.ore_scenes.is_empty()

func replaces_forest() -> bool:
	return not settings.conifer_scenes.is_empty() or not settings.broadleaf_scenes.is_empty()

func _group(parent: Node3D, name_: String) -> Node3D:
	var group := Node3D.new()
	group.name = name_
	parent.add_child(group)
	group.owner = root
	return group

func _mesh(parent: Node3D, name_: String, mesh: Mesh, shadows: bool) -> void:
	if mesh == null:
		push_warning("Landscape %s mesh missing: run scripts/tools/build_landscape.gd first." % name_)
		return
	var node := MeshInstance3D.new()
	node.name = name_
	node.mesh = mesh
	if not shadows: node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.owner = root

# A number from 0 to 1 that depends only on the cell and the question asked of it.
func chance(x: int, z: int, salt: int) -> float:
	var h := (x*73856093) ^ (z*19349663) ^ (salt*83492791) ^ (settings.scatter_seed*2654435761)
	h = (h ^ (h >> 13))*1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffffff)/float(0x1000000)

# The value noise of assets/shaders/landscape_ground.gdshader, so scenery can stand on what that shader draws.
func _shader_hash(x: int, y: int) -> float:
	var h := (x*1597334677+y*3812015801) & 0xffffffff
	h = ((h ^ (h >> 15))*2246822519) & 0xffffffff
	h = ((h ^ (h >> 13))*3266489917) & 0xffffffff
	h = h ^ (h >> 16)
	return float(h)/4294967295.0

func shader_noise(p: Vector2, layers: int) -> float:
	var total := 0.0
	var weight := 0.5
	var sum := 0.0
	for i in range(layers):
		var cell := Vector2i(floori(p.x),floori(p.y))
		var f := p-Vector2(cell)
		f = f*f*(Vector2(3.0,3.0)-2.0*f)
		total += lerpf(lerpf(_shader_hash(cell.x,cell.y),_shader_hash(cell.x+1,cell.y),f.x),lerpf(_shader_hash(cell.x,cell.y+1),_shader_hash(cell.x+1,cell.y+1),f.x),f.y)*weight
		sum += weight
		weight *= 0.5
		p = Vector2(1.6*p.x-1.2*p.y,1.2*p.x+1.6*p.y)+Vector2(17.3,9.1)
	return total/sum

func kind(x: int, z: int) -> int:
	return int(cells[z*MAP+x]) if x >= 0 and z >= 0 and x < MAP and z < MAP else -1

func _pick(scenes: Array, x: int, z: int, salt: int) -> PackedScene:
	return scenes[mini(int(chance(x,z,salt)*scenes.size()),scenes.size()-1)]

# Stands a scene at a point in cell coordinates, on the ground or at a given height.
func _place(scene: PackedScene, cx: float, cz: float, turn: float, scale: Vector3, tint: Color, sink := 0.0, lean := Vector2.ZERO, at_height := NAN) -> void:
	var y: float = builder.height_at(cx,cz) if is_nan(at_height) else at_height
	var basis := Basis(Vector3.UP,turn)
	if lean != Vector2.ZERO: basis = Basis(Vector3.RIGHT,lean.x)*Basis(Vector3.BACK,lean.y)*basis
	var transform := Transform3D(basis*Basis.from_scale(scale),Vector3(cx-MAP*0.5,y-sink,cz-MAP*0.5))
	var chunk := Vector2i(floori(cx/CHUNK),floori(cz/CHUNK))
	if not placed.has(scene): placed[scene] = {}
	if not placed[scene].has(chunk): placed[scene][chunk] = [[] as Array[Transform3D],[] as Array[Color]]
	placed[scene][chunk][0].append(transform)
	placed[scene][chunk][1].append(tint)

func _emit(group: Node3D) -> void:
	for scene in placed:
		for chunk in placed[scene]:
			var suffix := "_%d_%d" % [chunk.x,chunk.y]
			baker._batches(root,group,scene,placed[scene][chunk][0],placed[scene][chunk][1],"_"+scene.resource_path.get_file().get_basename()+suffix)
	placed.clear()

func _rocks() -> void:
	var region := settings.region
	for z in range(region.position.y+2,region.end.y-2):
		for x in range(region.position.x+2,region.end.x-2):
			var cx := x+chance(x,z,1)
			var cz := z+chance(x,z,2)
			var m: float = builder.sample(builder.mount,cx,cz)
			var s: float = builder.sample(builder.shore,cx,cz)
			var turn := chance(x,z,3)*TAU
			var grey := Color.WHITE*lerpf(0.86,1.1,chance(x,z,4))
			# Rock faces: a wall of them along the mountain edge, and a second along the ledge above where the rock
			# is wide enough. Each is turned to face out of the rock and stretched to the height of the wall behind.
			if not settings.cliff_scenes.is_empty() and x % 2 == 0 and z % 2 == 0:
				var out: Vector2 = builder.mountain_outward(cx,cz)
				var face := atan2(out.x,out.y)+(chance(x,z,8)-0.5)*0.4
				var wide := lerpf(0.85,1.2,chance(x,z,6))
				if m > -0.1 and m < 1.1 and chance(x,z,5) < 0.85:
					var tall: float = (builder.rock_first_height(cx,cz)+0.3)/CLIFF_HEIGHT*lerpf(0.8,1.08,chance(x,z,9))*builder.edge_fade(cx,cz)
					_place(_pick(settings.cliff_scenes,x,z,7),cx,cz,face,Vector3(wide,tall,wide),grey,0.0,Vector2.ZERO,0.0)
				var second: float = builder.rock_second_edge(m,cx,cz)
				if second > -0.2 and second < 1.0 and chance(x,z,5) < 0.7:
					var ledge: float = builder.height_at(cx+out.x*1.6,cz+out.y*1.6)
					var tall: float = (builder.rock_second_height(cx,cz)+0.2)/CLIFF_HEIGHT*lerpf(0.7,0.98,chance(x,z,9))
					_place(_pick(settings.cliff_scenes,x,z,7),cx,cz,face,Vector3(wide,tall,wide),grey,0.0,Vector2.ZERO,ledge-0.2)
			# Boulders: fallen at the foot, inside the Mountain cells, and broken out of the top.
			if not settings.boulder_scenes.is_empty() and kind(x,z) == MOUNTAIN:
				var foot := m > -0.2 and m < 0.9 and chance(x,z,10) < 0.16
				var top := m > 2.2 and chance(x,z,10) < 0.035
				if foot or top:
					var size := lerpf(0.55,1.25,pow(chance(x,z,11),1.6))
					_place(_pick(settings.boulder_scenes,x,z,12),cx,cz,turn,Vector3(size,size*lerpf(0.8,1.15,chance(x,z,13)),size),grey,size*0.25,Vector2(chance(x,z,14)-0.5,chance(x,z,15)-0.5)*0.5)
			# Stones: thick on the scree, scattered thinly over desert, a few on the beach.
			if not settings.stone_scenes.is_empty() and s < -0.3 and m < 0.3:
				var share := 0.3*smoothstep(-3.5,-0.3,m)
				if kind(x,z) == DESERT: share = maxf(share,0.035)
				if s > -2.0: share = maxf(share,0.07)
				if chance(x,z,16) < share:
					var size := lerpf(0.6,1.5,pow(chance(x,z,17),2.0))
					_place(_pick(settings.stone_scenes,x,z,18),cx,cz,turn,Vector3.ONE*size,grey,0.03)
			# Rocks in the shallows, in loose groups.
			if not settings.shore_rock_scenes.is_empty() and s > 0.1 and s < 2.6 and kind(x,z) == WATER:
				var grouped := smoothstep(0.1,0.5,patches.get_noise_2d(cx*2.3,cz*2.3))
				if chance(x,z,19) < 0.03+0.2*grouped:
					var size := lerpf(0.5,1.3,pow(chance(x,z,20),1.5))
					_place(_pick(settings.shore_rock_scenes,x,z,21),cx,cz,turn,Vector3(size,size*lerpf(0.7,1.1,chance(x,z,22)),size),grey,0.0,Vector2.ZERO,settings.water_level-0.25*size)

# Ore outcrops on the same spots the old ore rocks used: every second Ore cell each way.
func _ore() -> void:
	if not replaces_ore(): return
	var region := settings.region
	for z in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			if kind(x,z) != 5 or x % 2 != 1 or z % 2 != 1: continue
			var size := lerpf(0.8,1.15,chance(x,z,90))
			var tint := Color.WHITE*lerpf(0.9,1.1,chance(x,z,91))
			_place(_pick(settings.ore_scenes,x,z,92),x+lerpf(0.3,0.7,chance(x,z,93)),z+lerpf(0.3,0.7,chance(x,z,94)),chance(x,z,95)*TAU,Vector3(size,size*lerpf(0.8,1.2,chance(x,z,96)),size),tint,0.05)

func _plants() -> void:
	var region := settings.region
	for z in range(region.position.y+1,region.end.y-1):
		for x in range(region.position.x+1,region.end.x-1):
			var here := kind(x,z)
			if here == 5: continue
			if here == MOUNTAIN:
				# Dry growth on the level rock on top.
				var top: float = builder.sample(builder.mount,x+0.5,z+0.5)
				if top > 2.4 and not settings.dry_tuft_scenes.is_empty() and chance(x,z,45) < 0.16:
					_plant(settings.dry_tuft_scenes if chance(x,z,46) < 0.75 or settings.dry_bush_scenes.is_empty() else settings.dry_bush_scenes,x,z,47,0.8,1.5,0.8,1.1)
				continue
			var s: float = builder.sample(builder.shore,x+0.5,z+0.5)
			var m: float = builder.sample(builder.mount,x+0.5,z+0.5)
			var wood: float = builder.sample(builder.forest,x+0.5,z+0.5)
			var lush := patches.get_noise_2d(x,z)*0.5+0.5
			var thicket := patches.get_noise_2d(x*2.7+50.0,z*2.7)*0.5+0.5
			# Reeds stand in the first of the water along green shores.
			if here == WATER:
				if not settings.reed_scenes.is_empty() and s > -0.1 and s < 1.1 and kind(x-2,z) != DESERT and kind(x+2,z) != DESERT:
					if chance(x,z,30) < 0.55*smoothstep(0.45,0.7,thicket):
						for i in range(2):
							var size := lerpf(0.8,1.3,chance(x,z,31+i))
							_place(_pick(settings.reed_scenes,x,z,33+i),x+chance(x,z,35+i),z+chance(x,z,37+i),chance(x,z,39+i)*TAU,Vector3.ONE*size,Color.WHITE*lerpf(0.85,1.1,chance(x,z,41+i)),0.0,Vector2.ZERO,settings.water_level-0.2)
				continue
			if s > -0.9: continue
			if here == DESERT:
				if not settings.dry_bush_scenes.is_empty() and chance(x,z,50) < 0.015+0.07*smoothstep(0.55,0.8,thicket):
					_plant(settings.dry_bush_scenes,x,z,51,0.7,1.3,0.85,1.1)
				elif not settings.dry_tuft_scenes.is_empty() and chance(x,z,52) < 0.05+0.12*smoothstep(0.5,0.8,lush):
					_plant(settings.dry_tuft_scenes,x,z,53,0.7,1.3,0.85,1.15)
				continue
			if here == FOREST or m > -1.2: continue
			# Grass: bushes gather in thickets and along the forest edge, tufts and flowers in the lusher parts.
			var edge := smoothstep(0.05,0.3,wood)*(1.0-smoothstep(0.3,0.6,wood))
			var centre := Vector2(x+0.5,z+0.5)
			var inside: float = builder.edge_fade(centre.x,centre.y)
			var clump := smoothstep(0.58,0.7,shader_noise(centre/9.0+Vector2(41.0,7.0),3))*inside
			var bare := smoothstep(0.72,0.82,shader_noise(centre/6.0+Vector2(3.0,77.0),3))*inside
			if bare > 0.5:
				if not settings.stone_scenes.is_empty() and chance(x,z,66) < 0.2:
					_place(_pick(settings.stone_scenes,x,z,67),x+chance(x,z,68),z+chance(x,z,69),chance(x,z,59)*TAU,Vector3.ONE*lerpf(0.6,1.2,chance(x,z,58)),Color.WHITE,0.03)
				continue
			if not settings.tall_grass_scenes.is_empty() and chance(x,z,56) < 0.8*clump:
				_plant(settings.tall_grass_scenes,x,z,57,0.75,1.3,0.8,1.1)
				continue
			if not settings.bush_scenes.is_empty() and chance(x,z,60) < 0.002+0.3*smoothstep(0.7,0.84,thicket)*smoothstep(0.4,0.6,lush)+0.2*edge:
				_plant(settings.bush_scenes,x,z,61,0.7,1.35,0.82,1.12)
			elif not settings.flower_scenes.is_empty() and chance(x,z,62) < 0.2*smoothstep(0.66,0.86,lush):
				_plant(settings.flower_scenes,x,z,63,0.8,1.25,0.9,1.1)
			elif not settings.tuft_scenes.is_empty() and chance(x,z,64) < 0.1+0.3*smoothstep(0.3,0.75,lush):
				_plant(settings.tuft_scenes,x,z,65,0.7,1.4,0.8,1.15)

func _plant(scenes: Array, x: int, z: int, salt: int, small: float, large: float, dark: float, light: float) -> void:
	var size := lerpf(small,large,chance(x,z,salt+100))
	var shade := lerpf(dark,light,chance(x,z,salt+101))
	# A little warmer or cooler as well as lighter or darker, so a field of one plant is not one colour.
	var warmth := (chance(x,z,salt+102)-0.5)*0.16
	_place(_pick(scenes,x,z,salt+103),x+chance(x,z,salt+104),z+chance(x,z,salt+105),chance(x,z,salt+106)*TAU,Vector3.ONE*size,Color(shade*(1.0+warmth),shade,shade*(1.0-warmth)))

# One tree on most Forest cells, and low growth beneath. Each stands inside its own cell, because a cleared cell
# hides exactly the instances that stand on it (scripts/terrain/forest_state_visuals.gd).
func _forest() -> void:
	if not replaces_forest(): return
	var region := settings.region
	for z in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			if kind(x,z) != FOREST: continue
			var wood: float = builder.sample(builder.forest,x+0.5,z+0.5)
			# Stands of conifers and of broadleaves, mixed where they meet.
			var stand := patches.get_noise_2d(x*1.6-200.0,z*1.6+90.0)*0.5+0.5
			var conifer := chance(x,z,70) < lerpf(0.25,0.8,smoothstep(0.35,0.65,stand))
			var scenes: Array = settings.conifer_scenes if (conifer and not settings.conifer_scenes.is_empty()) or settings.broadleaf_scenes.is_empty() else settings.broadleaf_scenes
			if chance(x,z,71) < settings.tree_share:
				# Smaller trees at the edge of the wood, the tallest in its middle.
				var size := lerpf(0.72,1.0,smoothstep(0.35,0.9,wood))*lerpf(0.82,1.1,chance(x,z,72))
				var shade := lerpf(0.78,1.12,chance(x,z,73))
				var warmth := (chance(x,z,74)-0.5)*0.2
				_place(_pick(scenes,x,z,75),x+lerpf(0.2,0.8,chance(x,z,76)),z+lerpf(0.2,0.8,chance(x,z,77)),chance(x,z,78)*TAU,Vector3(size,size*lerpf(0.95,1.08,chance(x,z,79)),size),Color(shade*(1.0+warmth),shade,shade*(1.0-warmth)),0.05,Vector2(chance(x,z,80)-0.5,chance(x,z,81)-0.5)*0.12)
			if not settings.undergrowth_scenes.is_empty() and chance(x,z,82) < 0.7:
				var size := lerpf(0.7,1.3,chance(x,z,83))
				_place(_pick(settings.undergrowth_scenes,x,z,84),x+lerpf(0.15,0.85,chance(x,z,85)),z+lerpf(0.15,0.85,chance(x,z,86)),chance(x,z,87)*TAU,Vector3.ONE*size,Color.WHITE*lerpf(0.75,1.05,chance(x,z,88)))
