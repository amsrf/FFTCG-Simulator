extends Node3D
## One life crystal exploding (scripts/ui/life_crown.gd): a white flash, shards of the crystal flung outward and
## falling, and a few sparks. Lives in the CROWN's frame, which faces the camera: local XY is the screen plane, +Z
## points at the viewer, and one unit is the centre crystal's height. Frees itself after `LIFETIME`.
##
## Setup is `burst()`, called after add_child() (never `_ready()`, which runs inside add_child() before the caller has
## placed the node; see crystal_shards.gd for the history).

const CRYSTAL_SHADER := preload("res://shaders/life_crystal.gdshader")
const HALO_SHADER := preload("res://shaders/life_crystal_halo.gdshader")

const LIFETIME := 0.95
const SHARDS := 14
const SPARKS := 10
const DRAG := 3.2
const GRAVITY := 2.4
const FLASH_SECONDS := 0.28
const SHRINK_FROM := 0.35

## Built per burst, NOT cached in a static var: a static resource outlives the scene and is reported as leaked at exit.
var _shard_mesh: ArrayMesh = null

var _age: float = 0.0
var _size: float = 1.0
var _shards: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _flash: MeshInstance3D = null
var _flash_mat: ShaderMaterial = null
var _started: bool = false

## `size` is the crystal's scale in the crown (the centre one is 1.0); `seed` makes every burst look different but
## each one reproducible.
func burst(size: float, seed: int, body: Color = Color(0.42, 0.015, 0.03), glow: Color = Color(1.0, 0.07, 0.06)) -> void:
	_size = size
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var shard_mat := ShaderMaterial.new()
	shard_mat.shader = CRYSTAL_SHADER
	shard_mat.set_shader_parameter("foot_glow", 0.6)
	shard_mat.set_shader_parameter("body", body)
	shard_mat.set_shader_parameter("glow", glow)
	shard_mat.set_shader_parameter("glow_energy", 2.0)
	for i in range(SHARDS):
		var mi := MeshInstance3D.new()
		mi.mesh = _shard()
		mi.material_override = shard_mat
		add_child(mi)
		# Start inside the crystal's body (it is ~0.3 wide and 1.0 tall, foot at the bottom; this node sits mid-way).
		var start := Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.35, 0.35), 0.0) * size
		var dir := Vector3(start.x * 2.5 + rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 1.3), rng.randf_range(-0.2, 0.6)).normalized()
		var s := rng.randf_range(0.10, 0.22) * size
		_shards.append({
			"node": mi, "pos": start, "vel": dir * rng.randf_range(1.6, 3.2) * size,
			"axis": Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(),
			"spin": rng.randf_range(6.0, 16.0) * (1.0 if rng.randf() < 0.5 else -1.0),
			"angle": rng.randf_range(0.0, TAU), "scale": Vector3(s * 0.55, s, s * 0.55),
		})
	for i in range(SPARKS):
		var q := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * 0.09 * size
		q.mesh = quad
		var m := ShaderMaterial.new()
		m.shader = HALO_SHADER
		m.set_shader_parameter("intensity", 2.2)
		m.set_shader_parameter("colour", glow)
		m.render_priority = 11
		q.material_override = m
		add_child(q)
		var a := rng.randf_range(0.0, TAU)
		_sparks.append({"node": q, "mat": m, "pos": Vector3.ZERO,
			"vel": Vector3(cos(a), sin(a) * 0.8 + 0.4, 0.3) * rng.randf_range(2.5, 4.5) * size})
	_flash = MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(1.2, 1.5) * size
	_flash.mesh = fq
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = HALO_SHADER
	_flash_mat.set_shader_parameter("intensity", 1.6)
	_flash_mat.set_shader_parameter("flash", 1.0)
	_flash_mat.set_shader_parameter("colour", glow)
	_flash_mat.render_priority = 12
	_flash.material_override = _flash_mat
	_flash.position = Vector3(0, 0, 0.2)
	add_child(_flash)
	_started = true
	_apply(0.0)

func _process(delta: float) -> void:
	if not _started:
		return
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	_apply(delta)

func _apply(delta: float) -> void:
	var t: float = _age / LIFETIME
	var shrink: float = 1.0 - clampf((t - SHRINK_FROM) / (1.0 - SHRINK_FROM), 0.0, 1.0)
	var damp: float = exp(-DRAG * delta)
	for s in _shards:
		var v: Vector3 = s["vel"]
		v = v * damp + Vector3(0, -GRAVITY * _size, 0) * delta
		s["vel"] = v
		s["pos"] = (s["pos"] as Vector3) + v * delta
		s["angle"] = float(s["angle"]) + float(s["spin"]) * delta
		var node: MeshInstance3D = s["node"]
		node.transform = Transform3D(Basis(s["axis"], s["angle"]).scaled(s["scale"] * maxf(shrink, 0.001)), s["pos"])
	for k in _sparks:
		var v2: Vector3 = k["vel"]
		v2 = v2 * exp(-DRAG * 1.4 * delta)
		k["vel"] = v2
		k["pos"] = (k["pos"] as Vector3) + v2 * delta
		(k["node"] as MeshInstance3D).position = k["pos"]
		(k["mat"] as ShaderMaterial).set_shader_parameter("intensity", 2.2 * clampf(1.0 - t * 1.6, 0.0, 1.0))
	var f: float = clampf(_age / FLASH_SECONDS, 0.0, 1.0)
	_flash.scale = Vector3.ONE * lerpf(0.6, 2.0, 1.0 - pow(1.0 - f, 3.0))
	_flash_mat.set_shader_parameter("intensity", 1.6 * (1.0 - f) * (1.0 - f))

## A probe hook: how many shards are still visibly sized.
func live_shards() -> int:
	return _shards.size() if _age < LIFETIME else 0

## One shard: an elongated six-sided bipyramid, flat-shaded, 1.0 tall with its centre at the origin.
func _shard() -> ArrayMesh:
	if _shard_mesh != null:
		return _shard_mesh
	var ring: Array[Vector3] = []
	for i in range(6):
		var a := TAU * float(i) / 6.0
		ring.append(Vector3(cos(a) * 0.5, randf_range(-0.08, 0.08), sin(a) * 0.5))
	var top := Vector3(0, 0.5, 0)
	var bottom := Vector3(0, -0.5, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(6):
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 6]
		# Clockwise seen from outside (Godot's front faces).
		for tri in [[top, a, b], [bottom, a, b]]:
			var c: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
			var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0])
			if n.dot(c) > 0.0:
				# Counter-clockwise from outside: swap to clockwise.
				tri = [tri[0], tri[2], tri[1]]
			var outward: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized() * -1.0
			for p in tri:
				st.set_normal(outward)
				st.add_vertex(p)
	_shard_mesh = st.commit()
	return _shard_mesh
