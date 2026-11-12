@tool
extends Node3D
## Purely visual timeline. Local origin is the impact point; +Y is above the card.
@export var autoplay := false
@export var drop_height := 1.20
@export var crystal_scale := 0.48
@export var rise_seconds := 0.95
@export var rise_height := 0.45
@export var hover_seconds := 0.20
@export var fall_seconds := 0.32
@export var debris_seconds := 1.05
@export var frost_seconds := 3.0
@export var frost_radius := 0.65
## How hard the hit was (VfxEvent.damage_tier: 0 = up to 3000 ... 3 = 9000+). Bigger hits conjure a bigger crystal of
## a different cut, raised higher before it falls. See TIERS and set_damage_tier().
@export_range(0, 3) var damage_tier := 1:
	set(value):
		damage_tier = clampi(value, 0, 3)
		if is_node_ready():
			_apply_tier()

## Where the crystal is held before the drop, as a direction from the impact point (local space), and which way its
## long axis points. Straight up suits a side view (the demo). The board camera looks almost straight DOWN from close by,
## where a crystal rising straight up rushes at the lens, slides off the target and is seen end-on — so the damage cue
## sets both from the camera instead (see ice_projectile_cue.gd).
@export var fall_direction := Vector3.UP
@export var spike_axis := Vector3.UP

## Per tier: the crystal's size, how high it is held before the drop, how far it climbs while forming, and the frost
## left on the card. Tier 1 is the original tuning.
const TIERS := [
	{"scale": 0.38, "drop": 0.90, "rise": 0.30, "frost": 0.50},   # weak: one slender needle
	{"scale": 0.48, "drop": 1.20, "rise": 0.45, "frost": 0.65},   # medium: the hand-made Blender spike
	{"scale": 0.58, "drop": 1.40, "rise": 0.52, "frost": 0.80},   # high: a heavy six-sided prism
	{"scale": 0.68, "drop": 1.60, "rise": 0.60, "frost": 0.95},   # maximum: a massive eight-sided crystal
]
var _spike: MeshInstance3D
var _ice_light: OmniLight3D
var _ground: MeshInstance3D
var _conjure: Node3D
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
		_geometry["shapes"] = [_needle_shape(), _geometry.spike, _prism_shape(), _spear_shape()]
	var material := preload("res://assets/effects/ice/ice_material.tres")
	_spike = _piece(_geometry.spike, material.duplicate())
	_ice_light = OmniLight3D.new()
	_ice_light.light_color = Color(0.22, 0.72, 1.0)
	_ice_light.omni_range = 1.15
	_ice_light.light_energy = 0.0
	_ice_light.shadow_enabled = false
	add_child(_ice_light)
	_conjure = preload("res://scripts/vfx/ice_conjure.gd").new()
	add_child(_conjure)
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2.ONE * frost_radius * 2.0
	var ground_material := ShaderMaterial.new()
	ground_material.shader = preload("res://shaders/ice_ground.gdshader")
	_ground = _piece(ground_mesh, ground_material)
	_ground.position.y = 0.003
	_ground.material_override.render_priority = -1   # drawn before the crystal and shards, which then cover it
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for entry in _geometry.fragments:
		var shard_material := material.duplicate() as ShaderMaterial
		shard_material.set_shader_parameter("mesh_origin", entry.center)
		var fragment := _piece(entry.mesh, shard_material)
		_fragments.append(fragment)
		_centers.append(entry.center)
		_radii.append(fragment.mesh.get_aabb().size.length() * 0.5 * crystal_scale)
	_prepare_scatter(17)
	_apply_tier()
	reset()
	if Engine.is_editor_hint():
		show_conjured()
	elif autoplay:
		play()

## Vertex colour carries what the crystal shader needs and a mesh cannot otherwise say:
##   R        1 on a CUT face (the inside of a broken piece), 0 on the crystal's own faces.
##   G, B, A  per triangle, each falls to 0 along ONE of its three edges — but only if that edge is a HARD one (the
##            neighbouring triangle faces another way, or there is none). The diagonal across a flat facet stays at 1,
##            so the shader's edge highlight follows the cut of the crystal and not its triangulation.
func set_damage_tier(tier: int) -> void:
	damage_tier = tier

func _apply_tier() -> void:
	var tier: Dictionary = TIERS[damage_tier]
	crystal_scale = tier.scale
	drop_height = tier.drop
	rise_height = tier.rise
	_spike.mesh = _geometry.shapes[damage_tier]
	# The ground plane was built at the original radius; scale it rather than rebuild it.
	_ground.scale = Vector3.ONE * (float(tier.frost) / 0.65)
	_ice_light.omni_range = 1.15 * crystal_scale / 0.48
	for i in _fragments.size():
		_radii[i] = _fragments[i].mesh.get_aabb().size.length() * 0.5 * crystal_scale

# --- THE CUTS -------------------------------------------------------------------------------------------------------
# Generated, not modelled: each is a few crystals built from rings of jittered points, so the facets are irregular the
# way the Blender spike's are. Same conventions as that spike (see the JSON): the point of impact is the local origin,
# the crystal hangs point-down along +Y up to about 1.65, and triangles wind so (b - a) x (c - a) points INWARD.
# The shatter reuses the spike's fragments at the tier's scale; they are gone in a blink, so they need not fit exactly.

## Weak: one long, slender needle, sharp at both ends.
static func _needle_shape() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 101
	var tris: Array = []
	_crystal(tris, Vector3.ZERO, Vector3.UP, 1.62, 0.13, 6, rng, 0.42, 0.22)
	return _make_mesh(tris)

## High: a thick six-sided prism with flat shoulders and a short point.
static func _prism_shape() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 202
	var tris: Array = []
	_crystal(tris, Vector3.ZERO, Vector3.UP, 1.45, 0.24, 6, rng, 0.30, 0.10)
	return _make_mesh(tris)

## Maximum: one massive eight-sided crystal, long lower point and a broad crown.
static func _spear_shape() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	var tris: Array = []
	_crystal(tris, Vector3.ZERO, Vector3.UP, 1.62, 0.30, 8, rng, 0.40, 0.16)
	return _make_mesh(tris)

## One crystal into `out` (flat xyz triangle list): pointed at `base`, along `axis`, `length` long. `tip` and `cap` are
## the fractions of the length taken by the lower point and the upper point (0 = flat end). Every ring point is jittered
## in radius and angle, so no two facets are the same.
static func _crystal(out: Array, base: Vector3, axis: Vector3, length: float, radius: float, sides: int,
		rng: RandomNumberGenerator, tip: float, cap: float) -> void:
	var u := axis.cross(Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u).normalized()
	var phase := rng.randf() * TAU
	var lower: Array[Vector3] = []
	var upper: Array[Vector3] = []
	for k in sides:
		var a := phase + TAU * float(k) / float(sides) + rng.randf_range(-0.18, 0.18)
		var r := radius * rng.randf_range(0.82, 1.15)
		var dir := u * cos(a) + v * sin(a)
		lower.append(base + axis * length * tip + dir * r)
		upper.append(base + axis * length * (1.0 - cap) + dir * r * rng.randf_range(0.72, 0.92))
	var bottom := base
	var top := base + axis * length + (u * rng.randf_range(-1, 1) + v * rng.randf_range(-1, 1)) * radius * 0.25
	for k in sides:
		var n := (k + 1) % sides
		if tip > 0.0:
			_tri(out, bottom, lower[k], lower[n], base, axis)
		else:
			_tri(out, base + axis * 0.0, lower[k], lower[n], base, axis)
		_tri(out, lower[k], upper[k], upper[n], base, axis)
		_tri(out, lower[k], upper[n], lower[n], base, axis)
		if cap > 0.0:
			_tri(out, upper[k], top, upper[n], base, axis)
		else:
			_tri(out, upper[k], base + axis * length, upper[n], base, axis)

## Add a triangle wound like the Blender spike: (b - a) x (c - a) pointing back toward the crystal's axis.
static func _tri(out: Array, a: Vector3, b: Vector3, c: Vector3, base: Vector3, axis: Vector3) -> void:
	var centre := (a + b + c) / 3.0
	var on_axis := base + axis * (centre - base).dot(axis)
	# Every face of these crystals leans away from the axis, the end points included (their centres sit off-axis too).
	var outward := centre - on_axis
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var swap := b
		b = c
		c = swap
	for p in [a, b, c]:
		out.append(p.x)
		out.append(p.y)
		out.append(p.z)

static func _make_mesh(values: Array, internal: Array = []) -> ArrayMesh:
	var points: Array[Vector3] = []
	for i in range(0, values.size(), 3):
		points.append(Vector3(values[i], values[i + 1], values[i + 2]))
	var triangles: int = points.size() / 3
	var normals: Array[Vector3] = []
	var cut: Array[bool] = []
	var sharing: Dictionary = {}   # edge key -> triangles using it
	for t in triangles:
		var a := points[t * 3]
		var b := points[t * 3 + 1]
		var c := points[t * 3 + 2]
		normals.append((b - a).cross(c - a).normalized())
		cut.append(not internal.is_empty() and int(internal[t]) == 1)
		for k in 3:
			var key := _edge_key(points[t * 3 + (k + 1) % 3], points[t * 3 + (k + 2) % 3])
			if not sharing.has(key):
				sharing[key] = []
			sharing[key].append(t)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Preserve the Blender crystal facets; the default smooth group rounds edges.
	surface.set_smooth_group(-1)
	for t in triangles:
		# hard[j]: is the edge OPPOSITE vertex j a real edge of the crystal?
		var hard: Array[bool] = []
		for j in 3:
			var users: Array = sharing[_edge_key(points[t * 3 + (j + 1) % 3], points[t * 3 + (j + 2) % 3])]
			var is_hard: bool = users.size() < 2
			for other in users:
				if other != t and (normals[other].dot(normals[t]) < 0.995 or cut[other] != cut[t]):
					is_hard = true
			hard.append(is_hard)
		for k in 3:
			var channel := [1.0, 1.0, 1.0]
			for j in 3:
				if hard[j] and j != k:
					channel[j] = 0.0
			surface.set_color(Color(1.0 if cut[t] else 0.0, channel[0], channel[1], channel[2]))
			surface.add_vertex(points[t * 3 + k])
	surface.generate_normals()
	return surface.commit()

static func _edge_key(a: Vector3, b: Vector3) -> String:
	var first := "%d,%d,%d" % [roundi(a.x * 10000.0), roundi(a.y * 10000.0), roundi(a.z * 10000.0)]
	var second := "%d,%d,%d" % [roundi(b.x * 10000.0), roundi(b.y * 10000.0), roundi(b.z * 10000.0)]
	return first + "|" + second if first < second else second + "|" + first

func _piece(mesh: Mesh, material: Material) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = material
	add_child(piece)
	return piece

func impact_time() -> float:
	return rise_seconds + hover_seconds + fall_seconds

func duration() -> float:
	return impact_time() + maxf(debris_seconds, frost_seconds)

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
	if is_instance_valid(_ice_light):
		_ice_light.light_energy = 0.0
	if is_instance_valid(_conjure):
		_conjure.hide()
	if is_instance_valid(_ground):
		_ground.hide()
	if is_instance_valid(_spike):
		_spike.hide()
	for fragment in _fragments:
		fragment.hide()

func show_conjured() -> void:
	reset()
	sample(rise_seconds)
	_conjure.hide()

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
	_ground.visible = seconds >= impact and seconds < impact + frost_seconds
	_ground.material_override.set_shader_parameter("age", seconds - impact)
	_ground.material_override.set_shader_parameter("lifetime", frost_seconds)
	_conjure.visible = seconds >= 0.0 and seconds < duration()
	var forming := clampf(seconds / rise_seconds, 0.0, 1.0)
	_spike.material_override.set_shader_parameter("materialize", forming)
	var rising := smoothstep(0.0, rise_seconds, seconds)
	var height := drop_height - rise_height * (1.0 - rising)
	var held := fall_direction.normalized()
	var axis := spike_axis.normalized()
	_ice_light.position = held * height + axis * crystal_scale * 0.7
	_ice_light.light_energy = forming * 0.22 if seconds < impact else 0.16 * (1.0 - smoothstep(impact, impact + 0.4, seconds))
	if seconds >= impact:
		_ice_light.position.y = 0.12
	_conjure.sample(seconds, rise_seconds, impact, held * height, crystal_scale)
	_spike.visible = seconds < impact
	if seconds < impact:
		var falling := clampf((seconds - rise_seconds - hover_seconds) / fall_seconds, 0.0, 1.0)
		_spike.position = held * height * (1.0 - falling * falling)
		_ice_light.position = _spike.position + axis * crystal_scale * 0.7
		# Ease rotation to the same final orientation used by the fitted shards, spinning about the crystal's own axis.
		var spin := 0.3 - TAU * 0.65 * pow(1.0 - forming, 2.0)
		var lean := Basis(Quaternion(Vector3.UP, axis)) if axis.dot(Vector3.UP) < 0.9999 else Basis()
		_spike.basis = (lean * Basis(Vector3.UP, spin)).scaled(Vector3.ONE * crystal_scale)
		for fragment in _fragments:
			fragment.hide()
		return
	_set_interior_visible(true)
	for i in _fragments.size():
		var fragment := _fragments[i]
		fragment.visible = seconds >= impact and seconds < impact + debris_seconds
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
