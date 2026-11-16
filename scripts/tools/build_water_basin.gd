extends SceneTree
# Sinks a map's water below the ground: writes the bed of every lake's shore (a bank, then a slow fall) and a flat
# water surface, both from the map's cells. The terrain shader stops drawing the flat ground where the bed is, and
# Rebuild terrain scenery puts both meshes in the saved scenery (the water_basin_mesh and water_surface_mesh slots).
# It is art only: Water cells are unchanged and the bed is level wherever anything can walk.
# Run after the map cells change, then press Rebuild terrain scenery:
#   godot --headless --path . --script res://scripts/tools/build_water_basin.gd -- --cells=<cells .bin> --basin=<mesh .res> --surface=<mesh .res>
const ToolArgs := preload("res://scripts/tools/tool_args.gd")
const ShoreField := preload("res://scripts/tools/shore_field.gd")
const SIZE := 500
# Squares of bed to a metre. The bank is half a metre wide, so it needs a fine mesh to stay smooth.
const FINE := 3
# The bed is built from just outside the drawn shore to where the water is too deep to see through.
const BED_FROM := -0.5
const BED_TO := 5.4
var CELLS := ToolArgs.value("cells","res://assets/maps/balanced/terrain_cells.bin")
var BASIN := ToolArgs.value("basin","res://assets/maps/balanced/water_basin.res")
var SURFACE := ToolArgs.value("surface","res://assets/maps/balanced/water_surface.res")
var WATER_MATERIAL := ToolArgs.value("material","res://assets/materials/terrain/map_water.tres")

func _initialize() -> void:
	var cells := FileAccess.get_file_as_bytes(CELLS)
	if cells.size() != SIZE*SIZE:
		push_error("Unexpected size for "+CELLS); quit(1); return
	var field := ShoreField.new(cells)
	var basin := build_basin(field)
	var surface := build_surface(field)
	surface.surface_set_material(0,load(WATER_MATERIAL))
	if ResourceSaver.save(basin,BASIN) != OK or ResourceSaver.save(surface,SURFACE) != OK:
		push_error("Could not save the water meshes"); quit(1); return
	print("Bed %d triangles, surface %d triangles" % [basin.get_faces().size()/3,surface.get_faces().size()/3])
	print("WATER_BASIN_BUILT"); quit()

func build_basin(field) -> ArrayMesh:
	var grid := SIZE*FINE+1
	var index_of := {}
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var marks := PackedVector2Array()
	var indices := PackedInt32Array()
	var distance_of := {}
	for cz in range(SIZE):
		for cx in range(SIZE):
			# Only cells near a shore can hold bed: the blurred distance, give or take the wander and the inset.
			var near: float = field.smooth[cz*SIZE+cx]
			if near < -2.0 or near > BED_TO+2.4: continue
			for sz in range(FINE):
				for sx in range(FINE):
					var gx := cx*FINE+sx
					var gz := cz*FINE+sz
					var corners := [gz*grid+gx,gz*grid+gx+1,(gz+1)*grid+gx,(gz+1)*grid+gx+1]
					var least := INF
					var most := -INF
					for corner in corners:
						if not distance_of.has(corner):
							distance_of[corner] = field.shore(float(corner%grid)/FINE,float(corner/grid)/FINE)
						least = minf(least,distance_of[corner])
						most = maxf(most,distance_of[corner])
					if most < BED_FROM or least > BED_TO: continue
					for corner in corners:
						if index_of.has(corner): continue
						index_of[corner] = vertices.size()
						var x := float(corner%grid)/FINE
						var z := float(corner/grid)/FINE
						vertices.append(Vector3(x-SIZE*0.5,ShoreField.bed(distance_of[corner]),z-SIZE*0.5))
						uvs.append(Vector2(x,z)/SIZE)
						# The shader tells bed from flat ground by this second UV.
						marks.append(Vector2(1.0,0.0))
					indices.append_array([index_of[corners[0]],index_of[corners[1]],index_of[corners[2]],index_of[corners[1]],index_of[corners[3]],index_of[corners[2]]])
	return finish(vertices,uvs,marks,indices)

func build_surface(field) -> ArrayMesh:
	var grid := SIZE+1
	var index_of := {}
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for cz in range(SIZE):
		for cx in range(SIZE):
			# Every cell that could hold drawn water, with a margin: where there is none the surface lies hidden
			# under the ground.
			if field.smooth[cz*SIZE+cx] < -0.6: continue
			var corners := [cz*grid+cx,cz*grid+cx+1,(cz+1)*grid+cx,(cz+1)*grid+cx+1]
			for corner in corners:
				if index_of.has(corner): continue
				index_of[corner] = vertices.size()
				var x := float(corner%grid)
				var z := float(corner/grid)
				vertices.append(Vector3(x-SIZE*0.5,ShoreField.WATER_LEVEL,z-SIZE*0.5))
				uvs.append(Vector2(x,z)/SIZE)
			indices.append_array([index_of[corners[0]],index_of[corners[1]],index_of[corners[2]],index_of[corners[1]],index_of[corners[3]],index_of[corners[2]]])
	return finish(vertices,uvs,PackedVector2Array(),indices)

func finish(vertices: PackedVector3Array, uvs: PackedVector2Array, marks: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(vertices.size()):
		tool.set_uv(uvs[i])
		if not marks.is_empty(): tool.set_uv2(marks[i])
		tool.add_vertex(vertices[i])
	for index in indices: tool.add_index(index)
	tool.generate_normals()
	tool.generate_tangents()
	return tool.commit()
