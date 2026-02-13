extends RefCounted
class_name ModelAssetUtils

static func list_model_paths(models_dir: String) -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(models_dir)
	if dir == null:
		return paths
	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		var lower_name: String = file_name.to_lower()
		if lower_name.ends_with(".glb") or lower_name.ends_with(".gltf") or lower_name.ends_with(".fbx") or lower_name.ends_with(".obj") or lower_name.ends_with(".dae"):
			paths.append(models_dir.path_join(file_name))
	dir.list_dir_end()
	paths.sort()
	return paths

static func resolve_model_path(models_dir: String, explicit_path: String, auto_index: int) -> String:
	if not explicit_path.is_empty():
		return explicit_path
	var paths: PackedStringArray = list_model_paths(models_dir)
	if paths.is_empty():
		return ""
	var idx: int = clampi(auto_index, 0, paths.size() - 1)
	return paths[idx]

static func load_first_mesh(model_path: String) -> Mesh:
	if model_path.is_empty():
		return null
	var scene: PackedScene = load(model_path) as PackedScene
	if scene == null:
		return null
	var instance: Node = scene.instantiate()
	var mesh: Mesh = _find_first_mesh(instance)
	instance.free()
	return mesh

static func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			return mi.mesh
	for child: Node in node.get_children():
		var found: Mesh = _find_first_mesh(child)
		if found != null:
			return found
	return null
