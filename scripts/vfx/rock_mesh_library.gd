extends RefCounted
## Shared centered, unit-sized FBX meshes for particles and editable base stones.
static var _meshes: Dictionary = {}

static func get_mesh(source_scene: PackedScene) -> Mesh:
	if source_scene == null:
		return null
	var key := source_scene.resource_path
	if _meshes.has(key):
		return _meshes[key]
	var root := source_scene.instantiate()
	var sources: Array[Dictionary] = []
	_collect(root, Transform3D.IDENTITY, sources)
	if sources.is_empty():
		root.free()
		return null
	var bounds := AABB()
	var first := true
	for source in sources:
		var box: AABB = source.placement * source.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var factor := 1.0 / maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var normalize_mesh := Transform3D(Basis().scaled(Vector3.ONE * factor), -bounds.get_center() * factor)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for source in sources:
		var mesh: Mesh = source.mesh
		for i in range(mesh.get_surface_count()):
			surface.append_from(mesh, i, normalize_mesh * source.placement)
	var result := surface.commit()
	_meshes[key] = result
	root.free()
	return result

static func _collect(node: Node, placement: Transform3D, sources: Array[Dictionary]) -> void:
	if node is Node3D:
		placement = placement * node.transform
	if node is MeshInstance3D and node.mesh != null:
		sources.append({"mesh": node.mesh, "placement": placement})
	for child in node.get_children():
		_collect(child, placement, sources)
