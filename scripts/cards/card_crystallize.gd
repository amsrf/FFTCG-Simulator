extends Node3D
## THE MATERIALISING CARD'S CRYSTALS: real, tall prisms standing on the card. Presentation only.
##
## The card shader draws the build as flat crystal TRIANGLES (teleport_crystal in card.gdshader). This node raises a
## real faceted prism out of every one of those triangles, in the same two layers and at the same moments:
##   layer 0  the lavender lattice: starts first, slower, LOW crystals
##   layer 1  the element lattice: starts later, faster, TALL crystals that end up towering over the first
## Each prism's footprint is its triangle, so together they compose the card; each has its own height and a lean, and
## those near the border lean outward, so the cluster overflows the card's outline a little. When the art is revealed
## every prism breaks off, tumbling and shrinking away.
##
## The triangles are the shader's own jittered lattice (tri_vertex / tri_locate / tri_arrival / tri_peak), rebuilt here
## from the same integer PCG hash. KEEP THE CONSTANTS BELOW IN STEP WITH THE SHADER'S teleport_* UNIFORMS, or the
## prisms stop lining up with the flat triangles under them.
##
## Driven by CardTeleport.play_in(): setup(), set_build(0..1) through the build, set_tremble(0..1) through the glow
## beat, shatter() when the reveal begins.

const ELEMENTS := preload("res://scripts/core/elements.gd")
const SHADER := preload("res://shaders/card_crystal_prism.gdshader")

## Per layer: the shader's lattice (teleport_tri_cols/rows = 8/11 with hash salt 1, teleport_white_tri_* = 5/7 with
## salt 2) and the prisms' height range in card-local metres (the card face is 0.429 x 0.6).
const LAYERS := [
	{"cols": 8, "rows": 11, "salt": 1, "low": 0.035, "high": 0.085},
	{"cols": 5, "rows": 7, "salt": 2, "low": 0.10, "high": 0.22},
]
## Share of each layer's triangles that grow a crystal. The tall layer is SPARSE: separate crystals standing among the
## low ones rather than a solid wall (the flat triangles under them still complete the card).
const DENSITY := [1.0, 0.6]
## Some element crystals are spires: this chance, this much taller.
const SPIRE_CHANCE := 0.22
const SPIRE_SCALE := 1.3
## The shader's teleport_tri_jitter, teleport_white_delay, teleport_tri_grow, teleport_scatter and
## teleport_cluster_variation.
const LATTICE_JITTER := 0.30
const WHITE_DELAY := 0.32
const GROW := 0.38
const SCATTER := 0.28
const CLUSTER_VARIATION := 0.24
## How far a prism's tip leans off its base, as a fraction of its height: a random part, and a part pointing away
## from the card's centre (zero in the middle, full at the border) - that one is the overflow.
const LEAN_RANDOM := 0.12
const LEAN_OUTWARD := 0.10
## The unit crystal: a six-sided column (the triangle with CORNER_CUT of each edge cut off at both ends), walls up to
## SHOULDER of the height, narrowed to TAPER of the footprint there, then six facets to an off-centre point.
const CORNER_CUT := 0.27
const SHOULDER := 0.66
const TAPER := 0.86
## Clear of the card face, so the prisms' feet do not z-fight it.
const FLOOR := 0.002
const SHATTER_SECONDS := 0.45

static var _unit_mesh: ArrayMesh = null

## The demo flips this with the shader's teleport_build_from_top.
var from_top := true

var _multimeshes: Array[MultiMesh] = []
var _materials: Array[ShaderMaterial] = []
## Per layer, per prism: centre, peak (where it sprouts), affine basis, arrival terms, burst velocity, spin.
var _shards: Array = []
var _shattering := false

func setup(face: Vector2, element, seed_value: int) -> void:
	if _unit_mesh == null:
		_unit_mesh = _build_unit_prism()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var index: int = ELEMENTS.index_of(element)
	var tint: Color = ELEMENTS.ACCENT[index] if index >= 0 else Color(0.55, 0.85, 1.0)
	var tints: Array[Color] = [tint.lerp(Color(0.88, 0.72, 1.0), 0.55).darkened(0.25), tint]
	for layer in LAYERS.size():
		var spec: Dictionary = LAYERS[layer]
		var shards: Array = []
		for tri: Dictionary in triangles(spec.cols, spec.rows, spec.salt):
			if rng.randf() < DENSITY[layer]:
				shards.append(_make_shard(tri, spec, layer, face, rng))
		_shards.append(shards)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _unit_mesh
		multimesh.instance_count = shards.size()
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("tint", tints[layer])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.extra_cull_margin = 2.0
		add_child(instance)
		_multimeshes.append(multimesh)
		_materials.append(material)
	set_build(0.0)

func _make_shard(tri: Dictionary, spec: Dictionary, layer: int, face: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	# Card UV: x across, y DOWN the card; the card's bottom edge is local +Z.
	var corners: Array[Vector3] = []
	for uv: Vector2 in tri.corners:
		corners.append(Vector3((uv.x - 0.5) * face.x, 0.0, (uv.y - 0.5) * face.y))
	var centre := (corners[0] + corners[1] + corners[2]) / 3.0
	var centre_uv: Vector2 = (tri.corners[0] + tri.corners[1] + tri.corners[2]) / 3.0
	var id: Vector2i = tri.id
	# tri_peak(): the point the flat triangle grows out of, so the prism sprouts from the same spot.
	var r := _rand(id.x, id.y, spec.salt + 21) - Vector2(0.5, 0.5)
	var m := Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0) + Vector3(r.x, r.y, -r.x - r.y) * 0.30
	var peak := corners[0] * m.x + corners[1] * m.y + corners[2] * m.z
	# tri_arrival() without its vertical term (that one depends on from_top, see _arrival()).
	var cluster := Vector2i(floori(centre_uv.x * 5.0), floori(centre_uv.y * 7.0))
	var offset := (_rand(cluster.x, cluster.y, spec.salt + 31).x - 0.5) * CLUSTER_VARIATION \
		+ (_rand(id.x, id.y, spec.salt + 13).x - 0.5) * SCATTER
	var height := rng.randf_range(spec.low, spec.high)
	if layer == 1 and rng.randf() < SPIRE_CHANCE:
		height *= SPIRE_SCALE
	var outward := Vector3(centre.x / (face.x * 0.5), 0.0, centre.z / (face.y * 0.5))
	var lean := (Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * LEAN_RANDOM + outward * LEAN_OUTWARD) * height
	# The unit prism's base corners are (0,0), (1,0), (0,1) about their centroid and it is 1 tall: an affine basis
	# maps it onto this triangle, this height and this lean exactly. Keep it right-handed, or the prism turns inside
	# out and is culled.
	var up := Vector3(lean.x, height, lean.z)
	var basis := Basis(corners[1] - corners[0], up, corners[2] - corners[0])
	if basis.determinant() < 0.0:
		basis = Basis(corners[2] - corners[0], up, corners[1] - corners[0])
	var away := Vector3(centre.x, 0.0, centre.z)
	away = away.normalized() if away.length() > 0.001 else Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	return {
		"centre": centre + Vector3.UP * FLOOR,
		"peak": peak + Vector3.UP * FLOOR,
		"basis": basis,
		"vertical": centre_uv.y,
		"offset": offset,
		"velocity": Vector3.UP * rng.randf_range(0.30, 0.65) + away * rng.randf_range(0.18, 0.45),
		"spin": Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.4), rng.randf_range(-1, 1)).normalized()
			* rng.randf_range(4.0, 9.0),
	}

## The build, 0..1: every prism rises out of its triangle when the shader's flat triangle arrives (the same arrival,
## the same growth window, the element layer delayed and catching up).
func set_build(built: float) -> void:
	if _shattering:
		return
	var squeeze := 1.0 - GROW
	for layer in _shards.size():
		var layer_built := built if layer == 0 else clampf((built - WHITE_DELAY) / (1.0 - WHITE_DELAY), 0.0, 1.0)
		var shards: Array = _shards[layer]
		for i in shards.size():
			var s: Dictionary = shards[i]
			var arrival := clampf((s.vertical if from_top else 1.0 - s.vertical) + s.offset, 0.0, 1.0)
			var grown := smoothstep(0.0, 1.0, clampf((layer_built - arrival * squeeze) / GROW, 0.0, 1.0))
			_multimeshes[layer].set_instance_transform(i, _grown_transform(s, grown))

## A prism `grown` 0..1: its footprint spreads from the sprouting point while it shoots up, overshooting its height
## a little before settling.
static func _grown_transform(s: Dictionary, grown: float) -> Transform3D:
	var basis: Basis = s.basis
	if grown <= 0.0:
		return Transform3D(basis.scaled(Vector3.ONE * 0.0001), s.peak)
	var spread := lerpf(0.12, 1.0, sqrt(grown))
	var rise := grown * (1.0 + 0.22 * sin(PI * grown))
	return Transform3D(Basis(basis.x * spread, basis.y * rise, basis.z * spread),
		(s.peak as Vector3).lerp(s.centre, spread))

## The glow beat before the break: the whole cluster heats toward white.
func set_tremble(amount: float) -> void:
	for material in _materials:
		material.set_shader_parameter("heat", clampf(amount, 0.0, 1.0))

## The prisms break off the card and burst. Frees this node when done.
func shatter() -> void:
	if _shattering:
		return
	_shattering = true
	_sample_shatter(0.0)
	var burst := create_tween()
	burst.tween_method(_sample_shatter, 0.0, 1.0, SHATTER_SECONDS)
	burst.tween_callback(queue_free)

func _sample_shatter(t: float) -> void:
	var seconds := t * SHATTER_SECONDS
	# Full size at the break, then shrinking away fast.
	var size := maxf(pow(1.0 - t, 1.4) * (1.0 - 0.15 * t), 0.0001)
	for layer in _shards.size():
		var shards: Array = _shards[layer]
		for i in shards.size():
			var s: Dictionary = shards[i]
			var at: Vector3 = (s.centre as Vector3) + (s.velocity as Vector3) * seconds * (1.0 - 0.4 * t) \
				+ Vector3.DOWN * 1.1 * seconds * seconds
			var spin: Vector3 = s.spin
			var turned := Basis(spin.normalized(), spin.length() * seconds) * (s.basis as Basis)
			_multimeshes[layer].set_instance_transform(i, Transform3D(turned.scaled(Vector3.ONE * size), at))
	for material in _materials:
		material.set_shader_parameter("heat", 0.0)
		material.set_shader_parameter("exposure", 1.0 + 1.6 * pow(1.0 - t, 3.0))

# --- the card shader's triangle lattice ---------------------------------------------------------------------------

const _U32 := 0xFFFFFFFF
const _MUL := 1664525

## tri_pcg + tri_rand from card.gdshader, in 64-bit ints masked to 32 bits.
static func _rand(x: int, y: int, salt: int) -> Vector2:
	var a := (x + 4096 * salt) & _U32
	var b := y & _U32
	a = (a * _MUL + 1013904223) & _U32
	b = (b * _MUL + 1013904223) & _U32
	a = (a + b * _MUL) & _U32
	b = (b + a * _MUL) & _U32
	a ^= a >> 16
	b ^= b >> 16
	a = (a + b * _MUL) & _U32
	b = (b + a * _MUL) & _U32
	a ^= a >> 16
	b ^= b >> 16
	return Vector2(float(a) / 4294967295.0, float(b) / 4294967295.0)

static func _vertex(i: int, j: int, cols: int, rows: int, salt: int) -> Vector2:
	var jit := (_rand(i, j, salt) - Vector2(0.5, 0.5)) * 2.0 * LATTICE_JITTER
	if i == 0 or i == cols:
		jit.x = 0.0
	if j == 0 or j == rows:
		jit.y = 0.0
	return (Vector2(i, j) + jit) / Vector2(cols, rows)

## Every triangle of one lattice: {corners: three UVs in tri_locate()'s order, id: tri_locate()'s id}.
static func triangles(cols: int, rows: int, salt: int) -> Array:
	var out: Array = []
	for cy in rows:
		for cx in cols:
			var v00 := _vertex(cx, cy, cols, rows, salt)
			var v10 := _vertex(cx + 1, cy, cols, rows, salt)
			var v01 := _vertex(cx, cy + 1, cols, rows, salt)
			var v11 := _vertex(cx + 1, cy + 1, cols, rows, salt)
			var halves: Array
			if _rand(cx, cy, salt + 7).x < 0.5:
				halves = [[v00, v10, v11], [v00, v11, v01]]
			else:
				halves = [[v00, v10, v01], [v10, v11, v01]]
			for k in 2:
				out.append({"corners": halves[k], "id": Vector2i(cx * 2 + k, cy)})
	return out

# --- the unit prism ---------------------------------------------------------------------------------------------

## One crystal: a six-sided column standing on a unit right triangle (corners (0,0), (1,0), (0,1) in x/z, about its
## centroid) with the triangle's corners cut off, 1 tall: walls narrowing slightly to the shoulder, then six facets
## to an off-centre point - a quartz column. No bottom: it stands on the card. UV.x = height.
static func _build_unit_prism() -> ArrayMesh:
	var c := Vector3(1.0 / 3.0, 0.0, 1.0 / 3.0)
	var corners: Array[Vector3] = [Vector3(0, 0, 0) - c, Vector3(1, 0, 0) - c, Vector3(0, 0, 1) - c]
	var base: Array[Vector3] = []
	for k in 3:
		var from := corners[k]
		var to := corners[(k + 1) % 3]
		base.append(from.lerp(to, CORNER_CUT))
		base.append(from.lerp(to, 1.0 - CORNER_CUT))
	var top: Array[Vector3] = []
	for p in base:
		top.append(p * TAPER + Vector3.UP * SHOULDER)
	var peak := Vector3(0.05, 1.0, -0.04)
	var inside := Vector3(0.0, 0.4, 0.0)
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for k in base.size():
		var n := (k + 1) % base.size()
		_face(vertices, uvs, base[k], base[n], top[n], inside)
		_face(vertices, uvs, base[k], top[n], top[k], inside)
		_face(vertices, uvs, top[k], top[n], peak, inside)
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)   # unused: the shader rebuilds the facet normal
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## One triangle, wound like every crystal mesh here: (b - a) x (c - a) points INTO the solid.
static func _face(vertices: PackedVector3Array, uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3,
		inside: Vector3) -> void:
	if (b - a).cross(c - a).dot((a + b + c) / 3.0 - inside) > 0.0:
		var swap := b
		b = c
		c = swap
	for p: Vector3 in [a, b, c]:
		vertices.append(p)
		uvs.append(Vector2(p.y, 0.0))
