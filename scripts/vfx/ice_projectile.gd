@tool
extends Node3D
## Purely visual timeline. Local origin is the impact point; +Y is above the card.
@export var autoplay := false
@export var drop_height := 1.20
@export var crystal_scale := 0.48
@export var rise_seconds := 0.95
@export var rise_height := 0.45
@export var hover_seconds := 0.35
@export var fall_seconds := 0.32
@export var debris_seconds := 1.05
var _spike: MeshInstance3D
var _fragments: Array[MeshInstance3D] = []
var _centers: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _spins: Array[Vector3] = []
var _radii: Array[float] = []
var _age := 0.0
var _playing := false
static var _geometry: Dictionary = {}

func _ready() -> void:
	if _geometry.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/effects/ice/ice_projectile_meshes.json"))
		_geometry["spike"] = _make_mesh(data.spike)
		var pieces: Array = []
		for entry in data.fragments:
			pieces.append({"mesh": _make_mesh(entry.vertices, entry.internal), "center": Vector3(entry.center[0], entry.center[1], entry.center[2])})
		_geometry["fragments"] = pieces
	var material := preload("res://assets/effects/ice/ice_material.tres")
	_spike = _piece(_geometry.spike, material)
	for entry in _geometry.fragments:
		var shard_material := material.duplicate() as ShaderMaterial
		shard_material.set_shader_parameter("mesh_origin", entry.center)
		var fragment := _piece(entry.mesh, shard_material)
		_fragments.append(fragment)
		_centers.append(entry.center)
		_radii.append(fragment.mesh.get_aabb().size.length() * 0.5 * crystal_scale)
	_prepare_scatter(17)
	reset()
	if Engine.is_editor_hint():
		show_conjured()
	elif autoplay:
		play()

static func _make_mesh(values: Array, internal: Array = []) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Preserve the Blender crystal facets; the default smooth group rounds edges.
	surface.set_smooth_group(-1)
	for i in range(0, values.size(), 3):
		var cut_face := not internal.is_empty() and int(internal[i / 9]) == 1
		surface.set_color(Color(1 if cut_face else 0, 0, 0, 1))
		surface.add_vertex(Vector3(values[i], values[i + 1], values[i + 2]))
	surface.generate_normals()
	return surface.commit()

func _piece(mesh: Mesh, material: Material) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = material
	add_child(piece)
	return piece

func impact_time() -> float:
	return rise_seconds + hover_seconds + fall_seconds

func duration() -> float:
	return impact_time() + debris_seconds

func play(seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = randi()
	_prepare_scatter(seed_value)
	_age = 0.0
	_playing = true
	sample(0.0)
	set_process(true)

func reset() -> void:
	_playing = false
	set_process(false)
	if is_instance_valid(_spike):
		_spike.hide()
	for fragment in _fragments:
		fragment.hide()

func show_conjured() -> void:
	reset()
	sample(rise_seconds)

func _process(delta: float) -> void:
	if not _playing or Engine.is_editor_hint():
		return
	_age += delta
	sample(_age)
	if _age >= duration():
		reset()

func _prepare_scatter(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_velocities.clear()
	_spins.clear()
	for i in _fragments.size():
		var center := _centers[i]
		var angle := atan2(center.z, center.x) + rng.randf_range(-0.35, 0.35)
		var speed := rng.randf_range(0.75, 1.65)
		_velocities.append(Vector3(cos(angle) * speed, rng.randf_range(0.55, 1.45), sin(angle) * speed))
		_spins.append(Vector3(rng.randf_range(-9, 9), rng.randf_range(-9, 9), rng.randf_range(-9, 9)))

func _set_interior_visible(enabled: bool) -> void:
	for fragment in _fragments:
		fragment.material_override.set_shader_parameter("show_interior", enabled)

## Absolute-time sampling also lets the preview/probe inspect exact impact frames.
func sample(seconds: float) -> void:
	var impact := impact_time()
	_spike.visible = seconds < impact
	if seconds < impact:
		var rising := smoothstep(0.0, rise_seconds, seconds)
		var height := drop_height - rise_height * (1.0 - rising)
		var falling := clampf((seconds - rise_seconds - hover_seconds) / fall_seconds, 0.0, 1.0)
		_spike.position = Vector3.UP * height * (1.0 - falling * falling)
		_spike.rotation = Vector3(0, 0.3, 0)
		_spike.scale = Vector3.ONE * crystal_scale
		for fragment in _fragments:
			fragment.hide()
		return
	_set_interior_visible(true)
	for i in _fragments.size():
		var fragment := _fragments[i]
		fragment.visible = seconds >= impact and seconds < duration()
		if not fragment.visible:
			continue
		var elapsed := maxf(0.0, seconds - impact)
		var shrink := 1.0 - smoothstep(debris_seconds * 0.50, debris_seconds, elapsed)
		var origin := _centers[i].rotated(Vector3.UP, 0.3) * crystal_scale
		var velocity := _velocities[i]
		var pos := origin + velocity * elapsed + Vector3.DOWN * 4.9 * elapsed * elapsed
		# A small damped bounce, then slide/shrink on the floor. Sphere bound
		# keeps rotating chunks above the impact plane after first contact.
		var floor_height := minf(origin.y, _radii[i]) * shrink
		if pos.y < floor_height:
			var landing := (velocity.y + sqrt(velocity.y * velocity.y + 19.6 * maxf(origin.y - floor_height, 0.0))) / 9.8
			var after := maxf(0.0, elapsed - landing)
			pos.y = floor_height + maxf(0.0, after * 0.65 - 4.9 * after * after)
		fragment.position = pos
		fragment.rotation = Vector3(0, 0.3, 0) + _spins[i] * elapsed
		fragment.scale = Vector3.ONE * maxf(0.001, crystal_scale * shrink)
