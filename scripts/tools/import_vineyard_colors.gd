@tool
extends EditorScenePostImport
## The vineyard stores soil, foliage, fruit and sprayer finishes in glTF COLOR_0.

func _post_import(scene: Node) -> Object:
	for instance in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := instance.mesh as ArrayMesh
		if mesh == null: continue
		for surface in mesh.get_surface_count():
			if (mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR) == 0: continue
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			if material != null:
				material.vertex_color_use_as_albedo = true
	return scene
