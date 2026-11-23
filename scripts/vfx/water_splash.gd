extends Node3D
## A WATER SPLASH ON TOP OF THE DECK: played when a Water card's effect makes its controller draw (Game.draw_cards
## with a Water source). The drawn card's flight starts at the same moment, so the card reads as bursting up out of
## the splash. Presentation only, every piece procedural (no art assets), and it never holds the presentation queue.
##
##   0.00 .. 0.18   the CROWN: white water flung out in uneven jets from the deck top (camera-facing quad)
##   0.04 .. 0.46   it clears to a thin sheet, its middle drains into a ragged foaming ring, and it fades
##   0.00 .. ~0.9   DROPLETS thrown up and out along parabolas, falling back past the deck top and fading
##   0.02 / 0.14 / 0.28 + RING_SECONDS   three RIPPLES spread across the deck top, each fainter than the last
##
## The board camera looks almost straight down, so the part that must READ travels in the board plane (the ripples, the
## droplets' outward flight); the upward throw mostly reads as the droplets swelling toward the camera.
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the headless cache.

const RING_SHADER := preload("res://shaders/water_ring.gdshader")
const DROP_SHADER := preload("res://shaders/water_drop.gdshader")
const CROWN_SHADER := preload("res://shaders/water_crown.gdshader")

const DROPLETS := 48
const RING_STARTS := [0.02, 0.14, 0.28]
const RING_STRENGTH := [0.95, 0.70, 0.45]
const RING_SECONDS := 0.75
const CROWN_OPEN_SECONDS := 0.18
const CROWN_FADE_FROM := 0.16
const CROWN_FADE_SECONDS := 0.30
## Gravity in card heights per second squared.
const GRAVITY := 7.0
const LIFETIME := 1.1
## Drawn after the board and the cards (both are in the transparent pass), like the fire burst.
const RENDER_PRIORITY := 20

var _centre := Vector3.ZERO
var _height := 0.84
var _tint := Color(0.32, 0.58, 1.0)
var _seed := 0
var _age := 0.0

var _drops: Array = []
## Where the visible droplets are this frame. Kept on the CPU for the probe: the headless dummy renderer does not store
## MultiMesh instance data.
var _visible_drops: PackedVector3Array = PackedVector3Array()
var _drop_mesh: MultiMesh
var _rings: Array = []          # [MeshInstance3D, ShaderMaterial]
var _crown: MeshInstance3D
var _crown_mat: ShaderMaterial


func _ready() -> void:
	set_process(false)


## `centre`: the top of the deck (world). `height`: a deck card's height in world metres; every size is relative to it.
## Call after adding to the tree.
func setup(centre: Vector3, height: float, tint: Color, splash_seed: int) -> void:
	_centre = centre
	_height = maxf(height, 0.05)
	_tint = tint
	_seed = splash_seed
	global_position = Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = splash_seed
	_build_drops(rng)
	_build_rings()
	_build_crown()
	sample(0.0)
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	sample(_age)
	if _age >= LIFETIME:
		queue_free()


## Probe hooks.
func centre() -> Vector3:
	return _centre

func droplet_count() -> int:
	return _drops.size()

func visible_droplet_positions() -> PackedVector3Array:
	return _visible_drops

func crown_spread() -> float:
	return float(_crown_mat.get_shader_parameter("spread")) if _crown.visible else 0.0

func ring_radii() -> Array:
	var out: Array = []
	for entry in _rings:
		out.append(float(entry[1].get_shader_parameter("ring_radius")) if entry[0].visible else -1.0)
	return out


# --- build ------------------------------------------------------------------------------------------------------------

func _build_drops(rng: RandomNumberGenerator) -> void:
	var foam := Color(0.90, 0.97, 1.0)
	for i in DROPLETS:
		var angle := rng.randf() * TAU
		var out_speed := rng.randf_range(0.9, 2.3) * _height
		_drops.append({
			"start": Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.05, 0.16) * _height,
			"velocity": Vector3(cos(angle) * out_speed, rng.randf_range(1.6, 3.2) * _height, sin(angle) * out_speed),
			"launch": rng.randf_range(0.0, 0.08),
			"width": rng.randf_range(0.055, 0.10) * _height,
			"color": _tint.lerp(foam, rng.randf_range(0.35, 0.8)),
		})
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_drop_mesh = MultiMesh.new()
	_drop_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_drop_mesh.use_colors = true
	_drop_mesh.mesh = quad
	_drop_mesh.instance_count = _drops.size()
	var material := ShaderMaterial.new()
	material.shader = DROP_SHADER
	material.render_priority = RENDER_PRIORITY + 1
	var node := MultiMeshInstance3D.new()
	node.name = "Droplets"
	node.multimesh = _drop_mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 8.0
	add_child(node)


func _build_rings() -> void:
	for i in RING_STARTS.size():
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE * _height * 2.4
		var material := _material(RING_SHADER)
		material.set_shader_parameter("water_color", _tint)
		material.set_shader_parameter("seed", float((_seed + i * 37) % 997) * 0.31)
		var node := _add_mesh("Ripple%d" % i, plane, material)
		node.global_position = _centre + Vector3.UP * (0.006 + 0.001 * i)
		_rings.append([node, material])


func _build_crown() -> void:
	_crown_mat = _material(CROWN_SHADER)
	_crown_mat.set_shader_parameter("water_color", _tint)
	_crown_mat.set_shader_parameter("seed", float(_seed % 613) * 0.17)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * _height * 1.9
	_crown = _add_mesh("Crown", quad, _crown_mat)
	# Camera-facing, lifted a little toward the camera so the deck's top card cannot hide its lower half.
	var cam := _camera_basis()
	_crown.global_transform = Transform3D(cam, _centre + Vector3.UP * 0.03 + cam.z * 0.05)
	_crown_mat.render_priority = RENDER_PRIORITY + 1


func _material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = RENDER_PRIORITY
	material.set_shader_parameter("intensity", 0.0)
	return material


func _add_mesh(node_name: String, mesh: Mesh, material: ShaderMaterial) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 4.0
	add_child(node)
	return node


# --- sample -----------------------------------------------------------------------------------------------------------

## The whole splash at `t` seconds since setup (deterministic, so a demo can freeze any moment).
func sample(t: float) -> void:
	var toward_camera := _camera_basis().z
	_sample_crown(t)
	_sample_rings(t)
	_sample_drops(t, toward_camera)


func _sample_crown(t: float) -> void:
	var open := 1.0 - pow(1.0 - clampf(t / CROWN_OPEN_SECONDS, 0.0, 1.0), 3.0)
	var fade := clampf((t - CROWN_FADE_FROM) / CROWN_FADE_SECONDS, 0.0, 1.0)
	_crown.visible = fade < 1.0
	_crown_mat.set_shader_parameter("spread", lerpf(0.25, 1.0, open) + 0.08 * fade)
	_crown_mat.set_shader_parameter("hollow", smoothstep(0.04, 0.30, t))
	_crown_mat.set_shader_parameter("intensity", smoothstep(0.0, 0.04, t) * (1.0 - fade * fade))


func _sample_rings(t: float) -> void:
	for i in _rings.size():
		var node: MeshInstance3D = _rings[i][0]
		var material: ShaderMaterial = _rings[i][1]
		var s := (t - float(RING_STARTS[i])) / RING_SECONDS
		node.visible = s >= 0.0 and s < 1.0
		if not node.visible:
			continue
		material.set_shader_parameter("ring_radius", lerpf(0.12, 0.92, sqrt(s)))
		material.set_shader_parameter("ring_width", lerpf(0.07, 0.025, s))
		material.set_shader_parameter("intensity", pow(1.0 - s, 1.3) * float(RING_STRENGTH[i]))


func _sample_drops(t: float, toward_camera: Vector3) -> void:
	_visible_drops.clear()
	for i in _drops.size():
		var d: Dictionary = _drops[i]
		var dt: float = t - float(d.launch)
		if dt < 0.0:
			_hide_instance(i)
			continue
		var velocity: Vector3 = d.velocity
		var g := GRAVITY * _height
		var at: Vector3 = _centre + d.start + velocity * dt + Vector3.DOWN * (0.5 * g * dt * dt)
		var v_now: Vector3 = velocity + Vector3.DOWN * g * dt
		# Gone once it has fallen back to the deck top (a little below, so it visibly lands).
		var fallen := _centre.y - at.y
		if fallen > 0.02 * _height:
			_hide_instance(i)
			continue
		_visible_drops.append(at)
		var alpha := smoothstep(0.0, 0.05, dt) * (1.0 - smoothstep(-0.10 * _height, 0.02 * _height, fallen))
		# Beads, not streaks: barely longer than wide, stretching a little only while they fly fast.
		var length := float(d.width) * clampf(1.2 + v_now.length() / _height * 0.15, 1.2, 1.8)
		var c: Color = d.color
		_set_streak(i, at, v_now, length, float(d.width), toward_camera, Color(c.r, c.g, c.b, alpha))


func _set_streak(i: int, at: Vector3, velocity: Vector3, length: float, width: float, toward_camera: Vector3,
		color: Color) -> void:
	var along := velocity.normalized() if velocity.length() > 0.001 else Vector3.RIGHT
	var side := toward_camera.cross(along)
	side = side.normalized() if side.length() > 0.001 else Vector3.FORWARD
	var normal := along.cross(side).normalized()
	_drop_mesh.set_instance_transform(i, Transform3D(Basis(along * length, side * width, normal), at))
	_drop_mesh.set_instance_color(i, color)


func _hide_instance(i: int) -> void:
	_drop_mesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.0001), _centre))
	_drop_mesh.set_instance_color(i, Color(0, 0, 0, 0))


func _camera_basis() -> Basis:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		return cam.global_transform.basis.orthonormalized()
	return Basis.IDENTITY
