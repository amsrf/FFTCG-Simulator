@tool
extends Node3D
## Custom faceted crystals and downloaded ground, built by tools/build_ice_meshes.py.
@export var autoplay := false
@export var rise_seconds := 0.30
@export var hold_seconds := 0.55
@export var retreat_seconds := 0.35
var _pieces: Array[MeshInstance3D] = []
var _sizes: Array[Vector3] = []
var _motion: Tween
static var _meshes: Dictionary = {}

func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.38, 0.78, 0.94)
	material.metallic = 0.25
	material.roughness = 0.22
	material.emission_enabled = true
	material.emission = Color(0.08, 0.24, 0.30)
	material.emission_energy_multiplier = 0.35
	var placements := [Vector3(-0.19, 0.67, -0.22), Vector3(0.18, 0.82, -0.20),
		Vector3(-0.21, 0.92, 0.03), Vector3(0.20, 0.72, 0.07),
		Vector3(-0.14, 0.76, 0.24), Vector3(0.15, 0.96, 0.25)]
	_add_piece("ground", Vector3.ZERO, Vector3(0.95, 0.5, 0.95), 0.0, material)
	for i in placements.size():
		var p: Vector3 = placements[i]
		_add_piece("crystal", Vector3(p.x, 0, p.z), Vector3(1.25, p.y, 1.25), float(i) * 1.1, material)
	if Engine.is_editor_hint():
		show_raised()
		return
	reset()
	if autoplay:
		play()

func _add_piece(kind: String, location: Vector3, size: Vector3, yaw: float, material: Material) -> void:
	var piece := MeshInstance3D.new()
	piece.mesh = _mesh(kind)
	piece.material_override = material
	piece.position = location
	piece.rotation.y = yaw
	add_child(piece)
	_pieces.append(piece)
	_sizes.append(size)

static func _mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var values: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/effects/ice/%s_mesh.json" % kind))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Preserve the Blender crystal facets; the default smooth group rounds edges.
	surface.set_smooth_group(-1)
	for i in range(0, values.size(), 3):
		surface.add_vertex(Vector3(values[i], values[i + 1], values[i + 2]))
	surface.generate_normals()
	var result := surface.commit()
	_meshes[kind] = result
	return result

func reset() -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()
	for piece in _pieces:
		piece.visible = false
		piece.scale = Vector3.ONE * 0.001

func show_raised() -> void:
	reset()
	for i in _pieces.size():
		_pieces[i].visible = true
		_pieces[i].scale = _sizes[i]

func play() -> Tween:
	reset()
	_motion = create_tween().set_parallel(true)
	for i in _pieces.size():
		var piece := _pieces[i]
		piece.visible = true
		piece.scale = Vector3(_sizes[i].x, 0.001, _sizes[i].z)
		var delay := float(i) * 0.035
		_motion.tween_property(piece, "scale", _sizes[i], rise_seconds).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_motion.tween_property(piece, "scale", Vector3.ONE * 0.001, retreat_seconds).set_delay(0.21 + rise_seconds + hold_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return _motion
