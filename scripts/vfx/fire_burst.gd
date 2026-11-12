extends Node3D
## ONE FIRE BURST ON ONE CARD: magic sparks spiral in to the card's centre, gather into a white-hot core, and the core
## detonates into a fireball. Presentation only, every piece procedural (no art assets).
##
##   0 .. CHARGE_SECONDS   CHARGE   motes spiral inward from a circle just around the card, accelerating, while a dashed ring closes
##                                  in on the board and a starry core grows and brightens at the centre
##   CHARGE_SECONDS        DETONATE the core pops, a flash, the fireball swells (white -> yellow -> orange -> red ->
##                                  smoke), a ragged shockwave races out along the board, embers are thrown outward
##   .. + EMBER_SECONDS    the last embers die and the node frees itself
##
## The cue (fire_burst_cue.gd) owns the RULES-facing beats - the card's recoil and the release of a held break - at
## exactly `delay + CHARGE_SECONDS`. This node lives under the tree root and frees itself, so the cue (and with it the
## presentation queue) can move on while the smoke and embers finish.
##
## The board camera looks almost straight down, so everything that must READ travels in the board plane (the spiral,
## the rings, the embers' outward flight); the core and fireball are camera-facing quads.
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the headless cache.

const SPARK_SHADER := preload("res://shaders/fire_spark.gdshader")
const GLOW_SHADER := preload("res://shaders/fire_glow.gdshader")
const BALL_SHADER := preload("res://shaders/fire_ball.gdshader")
const RING_SHADER := preload("res://shaders/fire_ring.gdshader")

const CHARGE_SECONDS := 0.30
const BLAST_SECONDS := 1.25
const SHOCK_SECONDS := 0.45
const EMBER_SECONDS := 1.0
## The longer of the fireball (BLAST_SECONDS) and the embers (EMBER_SECONDS).
const LIFETIME := CHARGE_SECONDS + BLAST_SECONDS
const GRAVITY := 4.5

## Per damage tier (<=3000, <=6000, <9000, 9000+).
const TIER_SCALE := [0.80, 1.0, 1.20, 1.45]
const TIER_MOTES := [22, 30, 40, 52]
const TIER_EMBERS := [18, 28, 40, 56]

var _centre := Vector3.ZERO
var _height := 0.6   # the card's on-screen height in metres; every size below is relative to it
var _tier := 1
var _delay := 0.0
var _age := 0.0
var _seed := 0

var _motes: Array = []
## Where the visible motes are this frame. Kept on the CPU for the probe: the headless dummy renderer does not store
## MultiMesh instance data, so the mesh itself cannot be read back there.
var _visible_motes: PackedVector3Array = PackedVector3Array()
var _embers: Array = []
var _mote_mesh: MultiMesh
var _ember_mesh: MultiMesh
var _core: MeshInstance3D
var _core_mat: ShaderMaterial
var _flash: MeshInstance3D
var _flash_mat: ShaderMaterial
var _ball: MeshInstance3D
var _ball_mat: ShaderMaterial
var _charge_ring_mat: ShaderMaterial
var _shock: MeshInstance3D
var _shock_mat: ShaderMaterial


func _ready() -> void:
	set_process(false)


## `pose`: where the card WAS (a pre-damage snapshot): a card the hit broke is already in the Break Zone. Call after
## adding to the tree.
func setup(target: Node3D, pose: Variant, burst_seed: int, delay: float, damage_tier: int = 1) -> void:
	var at: Transform3D = pose if pose is Transform3D else target.global_transform
	_centre = at.origin
	var basis_scale: Vector3 = at.basis.get_scale()
	var card_scale: float = maxf((absf(basis_scale.x) + absf(basis_scale.z)) * 0.5, 0.01)
	var face := Vector2(0.429, 0.6)
	if is_instance_valid(target) and target.has_method("_card_face_size"):
		var size = target.call("_card_face_size")
		if size is Vector2 and size.y > 0.0:
			face = size
	_height = face.y * card_scale
	_tier = clampi(damage_tier, 0, 3)
	_delay = maxf(delay, 0.0)
	_seed = burst_seed
	global_position = Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = burst_seed
	_build_motes(rng)
	_build_embers(rng)
	_build_quads()
	sample(0.0)
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	sample(_age)
	if _age - _delay >= LIFETIME:
		queue_free()


## How many motes gather / embers fly (probe hooks).
func mote_count() -> int:
	return _motes.size()

func ember_count() -> int:
	return _embers.size()

func visible_mote_positions() -> PackedVector3Array:
	return _visible_motes


# --- build ------------------------------------------------------------------------------------------------------------

func _build_motes(rng: RandomNumberGenerator) -> void:
	var gold := Color(1.0, 0.78, 0.30)
	var ember := Color(1.0, 0.38, 0.08)
	for i in int(TIER_MOTES[_tier]):
		var start := rng.randf_range(0.0, 0.10)
		_motes.append({
			"angle": rng.randf() * TAU,
			"radius": rng.randf_range(0.55, 0.90) * _height * TIER_SCALE[_tier],
			"lift": rng.randf_range(0.02, 0.30) * _height,
			# Every mote turns the SAME way, so the whole field reads as one vortex.
			"swirl": rng.randf_range(1.3, 2.4),
			"start": start,
			"end": CHARGE_SECONDS - rng.randf_range(0.0, 0.04),
			"width": rng.randf_range(0.040, 0.065) * _height,
			"color": gold.lerp(ember, rng.randf()),
		})
	_mote_mesh = _spark_multimesh(_motes.size(), "Motes")


func _build_embers(rng: RandomNumberGenerator) -> void:
	for i in int(TIER_EMBERS[_tier]):
		var angle := rng.randf() * TAU
		var speed: float = rng.randf_range(0.9, 2.8) * _height * TIER_SCALE[_tier]
		_embers.append({
			"start": Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.02, 0.18) * _height
				+ Vector3.UP * rng.randf_range(0.02, 0.15) * _height,
			"velocity": Vector3(cos(angle) * speed, rng.randf_range(0.6, 2.2) * _height, sin(angle) * speed),
			"life": rng.randf_range(0.40, EMBER_SECONDS),
			"width": rng.randf_range(0.030, 0.050) * _height,
			"phase": rng.randf() * 40.0,
		})
	_ember_mesh = _spark_multimesh(_embers.size(), "Embers")


func _spark_multimesh(count: int, node_name: String) -> MultiMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	mesh.mesh = quad
	mesh.instance_count = count
	var material := ShaderMaterial.new()
	material.shader = SPARK_SHADER
	material.render_priority = RENDER_PRIORITY + 1
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 8.0
	add_child(node)
	return mesh


func _build_quads() -> void:
	var scale_f: float = TIER_SCALE[_tier]
	# The charge ring and the shockwave lie on the board, just above the card face.
	var ring_plane := PlaneMesh.new()
	ring_plane.size = Vector2.ONE * _height * 1.9 * scale_f
	_charge_ring_mat = _material(RING_SHADER)
	_charge_ring_mat.set_shader_parameter("dashes", 12.0)
	_charge_ring_mat.set_shader_parameter("ring_width", 0.035)
	_charge_ring_mat.set_shader_parameter("ring_color", Color(1.0, 0.55, 0.12))
	_charge_ring_mat.set_shader_parameter("seed", float(_seed % 997))
	_add_mesh("ChargeRing", ring_plane, _charge_ring_mat).global_position = _centre + Vector3.UP * 0.008

	var shock_plane := PlaneMesh.new()
	shock_plane.size = Vector2.ONE * _height * 2.3 * scale_f
	_shock_mat = _material(RING_SHADER)
	_shock_mat.set_shader_parameter("dashes", 0.0)
	_shock_mat.set_shader_parameter("seed", float(_seed % 991) * 0.37)
	_shock = _add_mesh("Shockwave", shock_plane, _shock_mat)
	_shock.global_position = _centre + Vector3.UP * 0.01

	# Camera-facing: the gathering core, the detonation flash and the fireball.
	_core_mat = _material(GLOW_SHADER)
	_core = _add_billboard("Core", _height * 1.1 * scale_f, _core_mat)
	_flash_mat = _material(GLOW_SHADER)
	_flash_mat.set_shader_parameter("rays", 0.0)
	_flash_mat.set_shader_parameter("core_size", 0.45)
	_flash_mat.set_shader_parameter("glow_color", Color(1.0, 0.70, 0.30))
	_flash = _add_billboard("Flash", _height * 2.1 * scale_f, _flash_mat)
	_ball_mat = _material(BALL_SHADER)
	_ball_mat.set_shader_parameter("seed", float(_seed % 613) * 0.11)
	_ball = _add_billboard("Fireball", _height * 1.9 * scale_f, _ball_mat)


## Drawn after every other transparent surface. The board and the cards are in the transparent pass too, and by
## distance sorting the board was drawn OVER the fireball wherever it lay outside the card, which clipped the blast to
## the card's rectangle.
const RENDER_PRIORITY := 20

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


func _add_billboard(node_name: String, size: float, material: ShaderMaterial) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var node := _add_mesh(node_name, quad, material)
	node.global_transform = Transform3D(_camera_basis(), _centre + Vector3.UP * 0.02)
	return node


# --- sample -----------------------------------------------------------------------------------------------------------

## The whole burst at `seconds` since setup (deterministic, so a demo can freeze any moment).
func sample(seconds: float) -> void:
	var t := seconds - _delay
	visible = t >= 0.0
	if t < 0.0:
		return
	var toward_camera := _camera_basis().z
	_sample_charge(t, toward_camera)
	_sample_blast(t - CHARGE_SECONDS, toward_camera)


func _sample_charge(t: float, toward_camera: Vector3) -> void:
	var u := clampf(t / CHARGE_SECONDS, 0.0, 1.0)
	var charging := t < CHARGE_SECONDS
	# The ring of dashes closes in on the card and turns with the vortex.
	_charge_ring_mat.set_shader_parameter("ring_radius", lerpf(0.90, 0.20, u * u))
	_charge_ring_mat.set_shader_parameter("spin", -u * 1.6)
	_charge_ring_mat.set_shader_parameter("intensity",
		(smoothstep(0.0, 0.25, u) * (0.55 + 0.45 * u)) if charging else 0.0)
	# The core gathers: it grows and brightens with the arriving motes, flickering, then pops at the detonation.
	var flicker := 0.85 + 0.15 * sin(t * 47.0)
	_core.scale = Vector3.ONE * lerpf(0.25, 1.0, pow(u, 1.1))
	_core_mat.set_shader_parameter("intensity", (minf(pow(u, 0.8) * 1.3, 1.2) * flicker) if charging else 0.0)
	_core_mat.set_shader_parameter("spin", t * 4.0)

	_visible_motes.clear()
	for i in _motes.size():
		var m: Dictionary = _motes[i]
		var start: float = m.start
		var end: float = m.end
		var k := clampf((t - start) / maxf(end - start, 0.01), 0.0, 1.0)
		if t < start or k >= 1.0:
			_hide_instance(_mote_mesh, i)
			continue
		var at := _mote_position(m, k)
		_visible_motes.append(at)
		var before := _mote_position(m, maxf(k - 0.04, 0.0))
		var velocity := (at - before) / 0.04
		var alpha := smoothstep(0.0, 0.18, k) * (1.0 - smoothstep(0.9, 1.0, k))
		var length := clampf(velocity.length() * 0.06, 0.08 * _height, 0.42 * _height)
		_set_streak(_mote_mesh, i, at, velocity, length, float(m.width), toward_camera,
			Color(m.color.r, m.color.g, m.color.b, alpha))


## Accelerating inward along a tightening spiral: slow at the rim, fast into the core.
func _mote_position(m: Dictionary, k: float) -> Vector3:
	var pull := k * k
	var radius: float = float(m.radius) * (1.0 - pull)
	var angle: float = float(m.angle) + float(m.swirl) * pull
	return _centre + Vector3(cos(angle), 0.0, sin(angle)) * radius + Vector3.UP * (float(m.lift) * (1.0 - pull) + 0.03)


func _sample_blast(bt: float, toward_camera: Vector3) -> void:
	var detonated := bt >= 0.0
	_flash.visible = detonated
	_ball.visible = detonated and bt < BLAST_SECONDS
	_shock.visible = detonated and bt < SHOCK_SECONDS
	if not detonated:
		for i in _embers.size():
			_hide_instance(_ember_mesh, i)
		return
	# Flash: a white-gold pop that dies in a tenth of a second.
	_flash_mat.set_shader_parameter("intensity", exp(-bt * 14.0) * 1.1)
	# Fireball: swells fast (cubic ease-out) and then KEEPS drifting outward while it dissipates. It never contracts:
	# the shader thins it into holes and wisps all over and fades it, rather than eroding it from the rim inward,
	# which read as the explosion shrinking back.
	var grow := 1.0 - pow(1.0 - clampf(bt / 0.25, 0.0, 1.0), 3.0)
	var age := clampf(bt / BLAST_SECONDS, 0.0, 1.0)
	_ball.scale = Vector3.ONE * (lerpf(0.25, 1.0, grow) + 0.25 * age)
	_ball_mat.set_shader_parameter("age", age)
	_ball_mat.set_shader_parameter("intensity", 1.0)
	# Shockwave: races out along the board, thinning as it fades.
	var s := clampf(bt / SHOCK_SECONDS, 0.0, 1.0)
	_shock_mat.set_shader_parameter("ring_radius", lerpf(0.10, 0.92, sqrt(s)))
	_shock_mat.set_shader_parameter("ring_width", lerpf(0.10, 0.03, s))
	_shock_mat.set_shader_parameter("intensity", pow(1.0 - s, 1.4))

	for i in _embers.size():
		var e: Dictionary = _embers[i]
		var life: float = e.life
		if bt >= life:
			_hide_instance(_ember_mesh, i)
			continue
		var velocity: Vector3 = e.velocity
		var at: Vector3 = _centre + e.start + velocity * bt + Vector3.DOWN * (0.5 * GRAVITY * _height * bt * bt)
		var v_now := velocity + Vector3.DOWN * GRAVITY * _height * bt
		at.y = maxf(at.y, _centre.y + 0.005)
		var u := bt / life
		var hot := Color(1.0, 0.85, 0.40).lerp(Color(0.90, 0.16, 0.03), u)
		var flicker := 0.75 + 0.25 * sin(float(e.phase) + bt * 38.0)
		var length := clampf(v_now.length() * 0.07, 0.06 * _height, 0.30 * _height)
		_set_streak(_ember_mesh, i, at, v_now, length, float(e.width), toward_camera,
			Color(hot.r, hot.g, hot.b, pow(1.0 - u, 1.2) * flicker))


func _set_streak(mesh: MultiMesh, i: int, at: Vector3, velocity: Vector3, length: float, width: float,
		toward_camera: Vector3, color: Color) -> void:
	var along := velocity.normalized() if velocity.length() > 0.001 else Vector3.RIGHT
	var side := toward_camera.cross(along)
	side = side.normalized() if side.length() > 0.001 else Vector3.FORWARD
	var normal := along.cross(side).normalized()
	mesh.set_instance_transform(i, Transform3D(Basis(along * length, side * width, normal), at))
	mesh.set_instance_color(i, color)


func _hide_instance(mesh: MultiMesh, i: int) -> void:
	mesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.0001), _centre))
	mesh.set_instance_color(i, Color(0, 0, 0, 0))


func _camera_basis() -> Basis:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		return cam.global_transform.basis.orthonormalized()
	return Basis.IDENTITY
