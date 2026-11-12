extends Node3D
## THE DESTROY BURST: how a broken card leaves the field (reference: Clips/destroy, frames 145-205 - three cards
## break there at once; this is ONE of those bursts). Presentation only, every piece procedural. Spawned by CardShards
## (style DESTROY_BURST), which owns where and when.
##
##   0 .. POP_SECONDS          the card's own picture washes to white, swells and is gone; a white flash
##   ~0.02 .. ~1.3             CRYSTAL SHARDS in the card's element colour are thrown out, tumbling and glinting,
##                             slowing in the air and drifting down the screen as they fade and shrink
##   ~0.03 .. ~0.8             ONE wind swirl curls out of the card and opens into a large, clear bubble
##   ~0.30 .. ~1.3             four-point sparkles twinkle where the shards went
##
## The board camera looks almost straight down (~80 degrees) and is orthographic, so everything is laid out in the
## CAMERA'S SCREEN PLANE (its right/up axes), not on the board: a burst on the board would be squashed into an
## ellipse, and anything rising toward the camera would not move on screen at all.
##
## `sample(seconds)` is deterministic for a given seed, so a demo can freeze any moment. The node lives in world
## space (top_level), frees itself and emits `finished` after LIFETIME.
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the headless cache.

signal finished

const SHARD_SHADER := preload("res://shaders/destroy_shard.gdshader")
const SWIRL_SHADER := preload("res://shaders/destroy_swirl.gdshader")
const SPARKLE_SHADER := preload("res://shaders/destroy_sparkle.gdshader")
const POP_SHADER := preload("res://shaders/destroy_card_pop.gdshader")
const GLOW_SHADER := preload("res://shaders/fire_glow.gdshader")

const POP_SECONDS := 0.12
const FLASH_SECONDS := 0.22
const SWIRL_START := 0.03
const SWIRL_SECONDS := 0.75
const SPARKLE_SECONDS := 0.36
const LIFETIME := 1.5

const SHARDS := 24
const SPARKLES := 14

## Drawn after every other transparent surface: the board and the cards are in the transparent pass too, and by
## distance sorting the board would otherwise be drawn over the burst wherever it lies outside the card.
const RENDER_PRIORITY := 20

## A card with no element (or an unknown one) breaks into clear, pale-blue crystal.
const DEFAULT_TINT := Color(0.70, 0.90, 1.0)

var _centre := Vector3.ZERO
var _height := 0.6      # the card's on-screen height in metres; every size below is relative to it
var _right := Vector3.RIGHT
var _up := Vector3.FORWARD
var _toward := Vector3.UP
## Momentum the card had when it broke (a clash knockback), so the cloud carries on the way the card was going.
var _drift := Vector3.ZERO
var _tint := DEFAULT_TINT
var _age := 0.0
var _seed := 0
var _done := false

var _shards: Array = []
var _sparkles: Array = []
var _shard_mesh: MultiMesh
var _sparkle_mesh: MultiMesh
var _swirl: MeshInstance3D
var _swirl_mat: ShaderMaterial
var _swirl_turn := 5.0
var _pop: MeshInstance3D
var _pop_mat: ShaderMaterial
var _pop_basis := Basis.IDENTITY
var _flash: MeshInstance3D
var _flash_mat: ShaderMaterial

## Probe hooks, kept on the CPU: the headless dummy renderer does not store MultiMesh instance data. The array is
## LIVE (cleared and refilled every frame): duplicate() it to compare two moments.
var _visible_shards: PackedVector3Array = PackedVector3Array()
var _visible_sparkles: int = 0


func _ready() -> void:
	top_level = true
	set_process(false)


## `card_pose`: the card mesh's global transform when it broke. `art`: a copy of its material (anything with a
## `texture_albedo`), `card_mesh`: its face mesh; either may be null and the pop is skipped. `tint`: the crystal
## colour (the card's element). Call after adding.
func setup(card_pose: Transform3D, art: Material, card_mesh: Mesh, burst_seed: int, drift := Vector3.ZERO,
		tint := DEFAULT_TINT) -> void:
	_centre = card_pose.origin
	var basis_scale: Vector3 = card_pose.basis.get_scale()
	var face_height := 0.6
	if card_mesh != null:
		var aabb := card_mesh.get_aabb()
		if aabb.size.z > 0.0:
			face_height = aabb.size.z
	_height = face_height * maxf((absf(basis_scale.x) + absf(basis_scale.z)) * 0.5, 0.01)
	_seed = burst_seed
	_drift = drift
	_tint = tint
	global_transform = Transform3D.IDENTITY
	var cam_basis := _camera_basis()
	_right = cam_basis.x
	_up = cam_basis.y
	_toward = cam_basis.z
	var rng := RandomNumberGenerator.new()
	rng.seed = burst_seed
	_build_pop(card_pose, art, card_mesh)
	_build_flash()
	_build_swirl(rng)
	_build_shards(rng)
	_build_sparkles(rng)
	sample(0.0)
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	sample(_age)
	if _age >= LIFETIME and not _done:
		_done = true
		finished.emit()
		queue_free()


func shard_count() -> int:
	return _shards.size()

func shard_tint() -> Color:
	return _tint

func visible_shard_positions() -> PackedVector3Array:
	return _visible_shards

func visible_sparkle_count() -> int:
	return _visible_sparkles

## The card picture's opacity right now (1 = the card is still there, 0 = it has popped).
func pop_opacity() -> float:
	if _pop_mat == null or not _pop.visible:
		return 0.0
	var fade = _pop_mat.get_shader_parameter("fade")
	return float(fade) if fade is float else 0.0

## How far the swirl has opened into the bubble (0 = all curls, 1 = all bubble).
func swirl_bubble() -> float:
	var value = _swirl_mat.get_shader_parameter("bubble")
	return float(value) if value is float else 0.0

## The swirl's diameter in card heights.
func swirl_size() -> float:
	return _swirl.scale.x / maxf(_height, 0.0001)


# --- build ------------------------------------------------------------------------------------------------------------

func _build_pop(card_pose: Transform3D, art: Material, card_mesh: Mesh) -> void:
	var texture: Variant = null
	if art is ShaderMaterial:
		texture = (art as ShaderMaterial).get_shader_parameter("texture_albedo")
	if card_mesh == null or not texture is Texture2D:
		return
	_pop_mat = ShaderMaterial.new()
	_pop_mat.shader = POP_SHADER
	_pop_mat.render_priority = RENDER_PRIORITY
	_pop_mat.set_shader_parameter("texture_albedo", texture)
	_pop = MeshInstance3D.new()
	_pop.name = "CardPop"
	_pop.mesh = card_mesh
	_pop.material_override = _pop_mat
	_pop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pop)
	_pop_basis = card_pose.basis
	_pop.global_transform = card_pose


func _build_flash() -> void:
	_flash_mat = _material(GLOW_SHADER)
	_flash_mat.set_shader_parameter("rays", 0.0)
	_flash_mat.set_shader_parameter("core_size", 0.40)
	_flash_mat.set_shader_parameter("glow_color", Color(1.0, 1.0, 1.0).lerp(_tint, 0.35))
	_flash_mat.set_shader_parameter("core_color", Color(1.0, 1.0, 1.0))
	_flash = _add_billboard("Flash", _height * 1.9, _flash_mat, RENDER_PRIORITY + 2)


## ONE swirl, centred on the card: the gust curls out of it and opens into the bubble.
func _build_swirl(rng: RandomNumberGenerator) -> void:
	_swirl_mat = _material(SWIRL_SHADER)
	_swirl_mat.set_shader_parameter("seed", float(_seed % 977) * 0.173)
	_swirl = _add_billboard("Swirl", 1.0, _swirl_mat, RENDER_PRIORITY)
	_swirl_turn = rng.randf_range(4.5, 6.0) * (1.0 if rng.randf() < 0.5 else -1.0)


func _build_shards(rng: RandomNumberGenerator) -> void:
	for i in SHARDS:
		# Spread evenly around the card with a jitter, so no side of the burst comes out empty.
		var angle := (float(i) + rng.randf_range(-0.4, 0.4)) / float(SHARDS) * TAU
		var length := rng.randf_range(0.18, 0.34) * _height
		_shards.append({
			"direction": Vector2(cos(angle) * 1.15, sin(angle)),
			"speed": rng.randf_range(2.2, 4.8) * _height,
			"start": rng.randf_range(0.0, 0.06),
			"life": rng.randf_range(0.75, LIFETIME - 0.2),
			"length": length,
			"width": length * rng.randf_range(0.42, 0.62),
			"flip": rng.randf() * TAU,
			"flip_speed": rng.randf_range(9.0, 18.0) * (1.0 if rng.randf() < 0.5 else -1.0),
			# Shards fly point-first, give or take a turn.
			"roll": angle + rng.randf_range(-0.5, 0.5),
			"roll_speed": rng.randf_range(-7.0, 7.0),
			"fall": rng.randf_range(0.3, 0.6) * _height,
			# A little variety inside one element: some shards paler, some deeper.
			"tone": rng.randf_range(-0.18, 0.22),
			"shape": Vector2(rng.randf(), rng.randf()),
		})
	_shard_mesh = _multimesh(_shards.size(), "Shards", SHARD_SHADER, true, RENDER_PRIORITY + 3)


func _build_sparkles(rng: RandomNumberGenerator) -> void:
	for i in SPARKLES:
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) * 1.15 * _height
		_sparkles.append({
			"offset": Vector2(cos(angle) * 1.2, sin(angle)) * radius,
			"start": rng.randf_range(0.25, LIFETIME - SPARKLE_SECONDS - 0.15),
			"size": rng.randf_range(0.20, 0.36) * _height,
			"colour": Color(1.0, 1.0, 1.0).lerp(_tint, 0.3),
		})
	_sparkle_mesh = _multimesh(_sparkles.size(), "Sparkles", SPARKLE_SHADER, false, RENDER_PRIORITY + 4)


func _material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = RENDER_PRIORITY
	material.set_shader_parameter("intensity", 0.0)
	return material


func _multimesh(count: int, node_name: String, shader: Shader, custom: bool, priority: int) -> MultiMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	mesh.use_custom_data = custom
	mesh.mesh = quad
	mesh.instance_count = count
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = priority
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 8.0
	add_child(node)
	for i in count:
		_hide_instance(mesh, i)
	return mesh


func _add_billboard(node_name: String, size: float, material: ShaderMaterial, priority: int) -> MeshInstance3D:
	material.render_priority = priority
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = quad
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 4.0
	add_child(node)
	node.global_transform = Transform3D(Basis(_right, _up, _toward), _centre)
	return node


# --- sample -----------------------------------------------------------------------------------------------------------

## The whole burst at `t` seconds after the break.
func sample(t: float) -> void:
	var centre := _origin_at(t)
	_sample_pop(t)
	_sample_flash(t, centre)
	_sample_swirl(t, centre)
	_sample_shards(t, centre)
	_sample_sparkles(t, centre)


## The cloud's centre: where the card broke, carried a little further the way it was flying.
func _origin_at(t: float) -> Vector3:
	return _centre + _drift * (1.0 - exp(-2.5 * t)) / 2.5 + _toward * 0.05


## Screen-plane offset (in metres) -> world point.
func _at(centre: Vector3, offset: Vector2) -> Vector3:
	return centre + _right * offset.x + _up * offset.y


func _sample_pop(t: float) -> void:
	if _pop == null:
		return
	var u := clampf(t / POP_SECONDS, 0.0, 1.0)
	_pop.visible = u < 1.0
	if not _pop.visible:
		return
	# Washes to white in the first third, then swells and fades: the card "blinks out".
	_pop_mat.set_shader_parameter("whiten", smoothstep(0.0, 0.25, u))
	_pop_mat.set_shader_parameter("fade", 1.0 - smoothstep(0.20, 0.85, u))
	var swell := 1.0 + 0.30 * (1.0 - pow(1.0 - u, 2.0))
	# Scaled in the CARD'S frame (right-multiplied): Basis.scaled() would scale along world axes and shear a
	# rotated card.
	_pop.global_transform = Transform3D(_pop_basis * Basis.from_scale(Vector3(swell, 1.0, swell)), _centre)


func _sample_flash(t: float, centre: Vector3) -> void:
	var u := clampf(t / FLASH_SECONDS, 0.0, 1.0)
	_flash.visible = u < 1.0
	_flash_mat.set_shader_parameter("intensity", pow(1.0 - u, 2.0) * 1.15)
	_flash.global_transform = Transform3D(Basis(_right, _up, _toward).scaled(Vector3.ONE * lerpf(0.55, 1.25, sqrt(u))),
		centre + _toward * 0.02)


func _sample_swirl(t: float, centre: Vector3) -> void:
	var u := (t - SWIRL_START) / SWIRL_SECONDS
	_swirl.visible = u >= 0.0 and u < 1.0
	if not _swirl.visible:
		return
	var grow := 1.0 - pow(1.0 - u, 3.0)
	# From the card's own size out to about two card heights across.
	var size := _height * lerpf(0.65, 2.1, grow)
	_swirl.global_transform = Transform3D(Basis(_right, _up, _toward).scaled(Vector3.ONE * size), centre)
	# The gust turns fast and slows as it opens; the curls hand over to the bubble around a third of the way in.
	_swirl_mat.set_shader_parameter("spin", _swirl_turn * (1.0 - exp(-3.0 * u)) / 3.0)
	_swirl_mat.set_shader_parameter("curl", 1.0 - smoothstep(0.22, 0.55, u))
	_swirl_mat.set_shader_parameter("bubble", smoothstep(0.18, 0.45, u))
	_swirl_mat.set_shader_parameter("intensity", smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.40, 1.0, u)))


func _sample_shards(t: float, centre: Vector3) -> void:
	_visible_shards.clear()
	for i in _shards.size():
		var s: Dictionary = _shards[i]
		var age := t - float(s.start)
		var life: float = s.life
		if age < 0.0 or age >= life:
			_hide_instance(_shard_mesh, i)
			continue
		# Thrown out hard, caught by the air, then drifting down the screen.
		var drag := 2.8
		var out: float = float(s.speed) * (1.0 - exp(-drag * age)) / drag
		var direction: Vector2 = s.direction
		var offset := direction * out + Vector2(0.0, -float(s.fall) * age * age)
		var at := _at(centre, offset)
		_visible_shards.append(at)
		# TUMBLE: the flip turns the shard about its long axis, so its width breathes through edge-on and the lit
		# facet swaps sides - that swap is the glint that makes it read as a crystal.
		var flip: float = float(s.flip) + float(s.flip_speed) * age
		var facing := cos(flip)
		var roll: float = float(s.roll) + float(s.roll_speed) * age
		var long_axis := _right * cos(roll) + _up * sin(roll)
		var short_axis := _toward.cross(long_axis).normalized()
		var k := age / life
		# Pops in, holds, and shrinks away over its last third (it never just switches off).
		var size := smoothstep(0.0, 0.05, age) * (1.0 - smoothstep(0.62, 1.0, k) * 0.75)
		var width: float = float(s.width) * maxf(absf(facing), 0.30) * size
		_shard_mesh.set_instance_transform(i, Transform3D(
			Basis(short_axis * width, long_axis * float(s.length) * size, _toward), at))
		var tone: float = s.tone
		var colour := _tint.lightened(tone) if tone > 0.0 else _tint.darkened(-tone)
		colour.a = 1.0 - smoothstep(0.70, 1.0, k)
		_shard_mesh.set_instance_color(i, colour)
		var shape: Vector2 = s.shape
		_shard_mesh.set_instance_custom_data(i, Color(shape.x, shape.y, clampf(facing * 0.5 + 0.5, 0.0, 1.0), 0.0))


func _sample_sparkles(t: float, centre: Vector3) -> void:
	_visible_sparkles = 0
	for i in _sparkles.size():
		var s: Dictionary = _sparkles[i]
		var u := (t - float(s.start)) / SPARKLE_SECONDS
		if u < 0.0 or u >= 1.0:
			_hide_instance(_sparkle_mesh, i)
			continue
		_visible_sparkles += 1
		# A twinkle: pops open fast, closes slower, with a slight turn.
		var pulse := sin(PI * pow(u, 0.6))
		var size: float = float(s.size) * pulse
		var turn := 0.6 * u
		var axis := _right * cos(turn) + _up * sin(turn)
		var side := _toward.cross(axis)
		_sparkle_mesh.set_instance_transform(i, Transform3D(Basis(axis * size, side * size, _toward),
			_at(centre, s.offset)))
		var colour: Color = s.colour
		colour.a = pulse
		_sparkle_mesh.set_instance_color(i, colour)


func _hide_instance(mesh: MultiMesh, i: int) -> void:
	mesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.0001), _centre))
	mesh.set_instance_color(i, Color(0, 0, 0, 0))


func _camera_basis() -> Basis:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		return cam.global_transform.basis.orthonormalized()
	return Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
