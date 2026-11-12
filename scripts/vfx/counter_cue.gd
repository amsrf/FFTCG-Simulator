extends VfxCue
## COUNTERED (VfxEvent.Kind.COUNTERED): the card held on its stack spot MALFUNCTIONS, then dies.
##   1. SHOCK  - violet/white electric arcs crackle over the face and off its edges, re-struck every few frames, while
##               the card glitches (small jumps in its own plane) and flickers violet. After Clips/negate2 frames 128+.
##   2. CYAN   - it turns solid cyan, and a crack network spreads out from its centre. After Clips/die frames 32+.
##   3. SHATTER - it breaks along exactly those cracks into flat cyan pieces that burst out a little, tumble and fall
##               DOWN THE SCREEN (the board camera looks nearly straight down, so world gravity would barely show).
## The real card is already in the Break Zone, hidden; it is shown when the card shatters (Vfx.release_hold).
## Driven from play() frame by frame, so freezing time (Engine.time_scale = 0) freezes the frame for screenshots.

const ARC_SHADER := preload("res://shaders/counter_arc.gdshader")
const OVERLAY_SHADER := preload("res://shaders/counter_overlay.gdshader")

const SHOCK_SECONDS := 1.0
## How often the arcs are struck anew (the crackle).
const ARC_REFRESH := 0.055
const CYAN_IN := 0.10
const CRACK_SECONDS := 0.26
const CRACK_HOLD := 0.08
const FALL_SECONDS := 1.15
## Card-face units (the face is 0.429 x 0.6).
const ARC_WIDTH := 0.055
const GLITCH := 0.006
const CYAN := Color(0.30, 0.98, 1.0)
const VIOLET := Color(0.62, 0.40, 1.0)
## The crack cells: [radius as a fraction of the card height, count]. Dense in the middle, where the card is struck.
const RINGS: Array = [[0.0, 1], [0.06, 5], [0.13, 8], [0.22, 11], [0.33, 14], [0.46, 17]]
## Gaps between the pieces (face units): the cracks open as it breaks.
const GAP := 0.0025

var _rng := RandomNumberGenerator.new()
var _card: Card = null
var _visual: Dictionary = {}
var _stand_in: Card = null
var _face: MeshInstance3D = null   # the stand-in's HandMesh: the frame everything on the face is built in
var _face_xf := Transform3D.IDENTITY
var _home := Transform3D.IDENTITY
var _size := Vector2(0.429, 0.6)
var _sites := PackedVector2Array()
var _overlay_mat: ShaderMaterial = null
var _arcs: MeshInstance3D = null
var _arc_mat: ShaderMaterial = null
var _shards: Array = []   # [{node, velocity, axis, spin, delay, basis}]
var _released := false


func play(event: VfxEvent) -> void:
	for target in event.targets:
		if is_instance_valid(target):
			_card = target
			break
	if _card != null:
		_visual = event.target_visuals.get(_card.get_instance_id(), {})
	_stand_in = _visual.get("stand_in", null)
	if not is_instance_valid(_stand_in) or _stand_in.hand_mesh == null:
		await get_tree().process_frame
		return
	_rng.seed = event.seed if event.seed != 0 else 7919
	_build()
	var t := 0.0
	var next_arc := 0.0
	var cyan_at := SHOCK_SECONDS
	var break_at := cyan_at + CYAN_IN + CRACK_SECONDS + CRACK_HOLD
	var end_at := break_at + FALL_SECONDS
	while t < end_at:
		# Something else released the hold (the match ended, the scene changed): nothing left to animate on.
		if not _released and not is_instance_valid(_stand_in):
			break
		if t < cyan_at:
			if t >= next_arc:
				next_arc = t + ARC_REFRESH
				_strike(t / SHOCK_SECONDS)
		elif t < break_at:
			_turn_cyan(t - cyan_at)
		else:
			if not _released:
				_shatter()
			_fall(t - break_at)
		await get_tree().process_frame
		t += get_process_delta_time()
	_finish()


## Overlay + arc nodes on the stand-in's face, and the crack sites.
func _build() -> void:
	_face = _stand_in.hand_mesh
	_size = _stand_in._card_face_size()
	_face_xf = _face.global_transform
	_home = _stand_in.global_transform
	var h := _size.y
	for ring in RINGS:
		var radius: float = float(ring[0]) * h
		var count: int = ring[1]
		var turn := _rng.randf() * TAU
		for i in count:
			var a := turn + TAU * float(i) / float(count) + _rng.randf_range(-0.25, 0.25) * TAU / float(count)
			var r := radius * _rng.randf_range(0.82, 1.18)
			_sites.append(Vector2(cos(a) * r, sin(a) * r) + Vector2(_rng.randf_range(-0.01, 0.01), _rng.randf_range(-0.01, 0.01)))
	var plane := PlaneMesh.new()
	plane.size = _size
	_overlay_mat = ShaderMaterial.new()
	_overlay_mat.shader = OVERLAY_SHADER
	_overlay_mat.render_priority = 2
	_overlay_mat.set_shader_parameter("card_size", _size)
	_overlay_mat.set_shader_parameter("sites", _sites)
	_overlay_mat.set_shader_parameter("site_count", _sites.size())
	_overlay_mat.set_shader_parameter("tint", VIOLET)
	_overlay_mat.set_shader_parameter("fill", 0.0)
	var overlay := MeshInstance3D.new()
	overlay.name = "CounterOverlay"
	overlay.mesh = plane
	overlay.material_override = _overlay_mat
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.position = Vector3(0.0, 0.003, 0.0)
	_face.add_child(overlay)
	_arc_mat = ShaderMaterial.new()
	_arc_mat.shader = ARC_SHADER
	_arc_mat.render_priority = 3
	_arcs = MeshInstance3D.new()
	_arcs.name = "CounterArcs"
	_arcs.material_override = _arc_mat
	_arcs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arcs.extra_cull_margin = 1.0
	_arcs.position = Vector3(0.0, 0.006, 0.0)
	_face.add_child(_arcs)


## One crackle: new arcs, a glitch jump and a violet flicker. `u` 0..1 through the shock, more arcs as it goes.
func _strike(u: float) -> void:
	var count := 3 + int(round(u * 4.0)) + (1 if _rng.randf() < 0.35 else 0)
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in count:
		var points := _arc_points()
		_ribbon(points, verts, uvs, indices)
		if _rng.randf() < 0.45:
			var from: Vector2 = points[_rng.randi_range(2, points.size() - 3)]
			var away := Vector2.from_angle(_rng.randf() * TAU) * _size.y * _rng.randf_range(0.06, 0.14)
			_ribbon(_jagged(from, from + away, 4), verts, uvs, indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_arcs.mesh = mesh
	_arc_mat.set_shader_parameter("intensity", _rng.randf_range(1.0, 1.7))
	_overlay_mat.set_shader_parameter("fill", _rng.randf_range(0.04, 0.10 + 0.16 * u))
	# The glitch: small jumps in the card's own plane, now and then a bigger one.
	var jump := GLITCH * (3.0 if _rng.randf() < 0.15 else 1.0)
	var offset := _face_xf.basis * Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)) * jump
	_stand_in.global_transform = Transform3D(_home.basis, _home.origin + offset)


## An arc from a point on (or just off) the card's edge, inward across the face.
func _arc_points() -> Array:
	var half := _size * 0.5
	var side := _rng.randi_range(0, 3)
	var t := _rng.randf_range(-0.9, 0.9)
	var out := _rng.randf_range(-0.01, 0.03)
	var start: Vector2
	var inward: Vector2
	match side:
		0:
			start = Vector2(t * half.x, -half.y - out)
			inward = Vector2.DOWN
		1:
			start = Vector2(half.x + out, t * half.y)
			inward = Vector2.LEFT
		2:
			start = Vector2(t * half.x, half.y + out)
			inward = Vector2.UP
		_:
			start = Vector2(-half.x - out, t * half.y)
			inward = Vector2.RIGHT
	var direction := inward.rotated(_rng.randf_range(-0.9, 0.9))
	var end := start + direction * _size.y * _rng.randf_range(0.20, 0.52)
	return _jagged(start, end, _rng.randi_range(7, 11))


## A zig-zag between two points: perpendicular kicks, largest mid-way.
func _jagged(from: Vector2, to: Vector2, segments: int) -> Array:
	var points: Array = [from]
	var along := to - from
	var normal := Vector2(-along.y, along.x).normalized()
	for i in range(1, segments):
		var s := float(i) / float(segments)
		var kick := _rng.randf_range(-1.0, 1.0) * along.length() * 0.16 * sin(PI * s)
		points.append(from + along * s + normal * kick)
	points.append(to)
	return points


## A strip along `points` (face-plane x/z), mitred at the joints so it does not pinch.
func _ribbon(points: Array, verts: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> void:
	var base := verts.size()
	var n := points.size()
	for k in n:
		var p: Vector2 = points[k]
		var prev: Vector2 = points[maxi(k - 1, 0)]
		var next: Vector2 = points[mini(k + 1, n - 1)]
		var tangent := (next - prev).normalized()
		var side := Vector2(-tangent.y, tangent.x) * ARC_WIDTH * 0.5
		var u := float(k) / float(n - 1)
		verts.append(Vector3(p.x + side.x, 0.0, p.y + side.y))
		verts.append(Vector3(p.x - side.x, 0.0, p.y - side.y))
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
		if k > 0:
			var a := base + (k - 1) * 2
			indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])


## Solid cyan (a white flash first), and the cracks spreading out from the centre.
func _turn_cyan(s: float) -> void:
	if _arcs.visible:
		_arcs.visible = false
		_stand_in.global_transform = _home
		if _stand_in.cost_badge != null and is_instance_valid(_stand_in.cost_badge):
			_stand_in.cost_badge.visible = false
	var flash := 1.0 - smoothstep(0.0, 0.07, s)
	_overlay_mat.set_shader_parameter("tint", CYAN.lerp(Color(0.92, 1.0, 1.0), flash))
	_overlay_mat.set_shader_parameter("fill", smoothstep(0.0, CYAN_IN, s))
	var c := clampf((s - CYAN_IN * 0.5) / CRACK_SECONDS, 0.0, 1.0)
	var reach := (1.0 - pow(1.0 - c, 2.0)) * _size.length() * 0.55
	_overlay_mat.set_shader_parameter("crack_reach", reach)


## The pieces replace the card: one flat cyan polygon per crack cell.
func _shatter() -> void:
	_released = true
	var camera := get_viewport().get_camera_3d()
	var screen_up: Vector3 = camera.global_basis.y if camera != null else Vector3.BACK
	var toward_camera: Vector3 = camera.global_basis.z if camera != null else Vector3.UP
	var world_h: float = (_face_xf.basis.z).length() * _size.y
	var max_r: float = _size.length() * 0.5
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 2
	for i in _sites.size():
		var cell := _cell(i)
		if cell.size() < 3:
			continue
		var centre := Vector2.ZERO
		for p in cell:
			centre += p
		centre /= float(cell.size())
		var shade := CYAN * _rng.randf_range(0.88, 1.08)
		shade.a = 1.0
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_color(shade)
		for k in range(1, cell.size() - 1):
			for p in [cell[0], cell[k], cell[k + 1]]:
				var q: Vector2 = centre + ((p as Vector2) - centre).limit_length(maxf(((p as Vector2) - centre).length() - GAP, 0.0))
				tool.add_vertex(Vector3(q.x - centre.x, 0.0, q.y - centre.y))
		var piece := MeshInstance3D.new()
		piece.name = "CounterShard"
		piece.mesh = tool.commit()
		piece.material_override = material
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece, true)
		var basis: Basis = _face_xf.basis
		piece.global_transform = Transform3D(basis, _face_xf * Vector3(centre.x, 0.004, centre.y))
		var r := centre.length() / max_r
		var outward := (basis * Vector3(centre.x, 0.0, centre.y))
		outward = outward.normalized() if outward.length() > 0.0001 else screen_up
		var velocity := outward * world_h * (0.12 + 0.55 * r) * _rng.randf_range(0.7, 1.2) \
			+ toward_camera * world_h * _rng.randf_range(0.0, 0.35) \
			+ screen_up * world_h * _rng.randf_range(0.10, 0.50)
		var axis := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
		if axis.length() < 0.1:
			axis = Vector3.RIGHT
		_shards.append({"node": piece, "origin": piece.global_position, "velocity": velocity, "axis": axis,
			"spin": _rng.randf_range(2.0, 9.0) * (0.4 + r), "delay": r * 0.08, "basis": basis,
			"gravity": -screen_up * world_h * _rng.randf_range(4.5, 6.5)})
	# The card itself is gone: the stand-in goes and the real card shows in the Break Zone.
	Vfx.release_hold(_card, _visual, false)


## Sutherland-Hodgman: the card rectangle clipped to the half-planes nearer site `i` than every other site.
func _cell(i: int) -> Array:
	var half := _size * 0.5
	var poly: Array = [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]
	var si: Vector2 = _sites[i]
	for j in _sites.size():
		if j == i or poly.is_empty():
			continue
		var sj: Vector2 = _sites[j]
		var normal := sj - si
		var mid := (si + sj) * 0.5
		var clipped: Array = []
		for k in poly.size():
			var a: Vector2 = poly[k]
			var b: Vector2 = poly[(k + 1) % poly.size()]
			var da := (a - mid).dot(normal)
			var db := (b - mid).dot(normal)
			if da <= 0.0:
				clipped.append(a)
			if (da <= 0.0) != (db <= 0.0):
				clipped.append(a + (b - a) * (da / (da - db)))
		poly = clipped
	return poly


func _fall(s: float) -> void:
	for shard in _shards:
		var piece: MeshInstance3D = shard.node
		if not is_instance_valid(piece):
			continue
		var t: float = maxf(s - float(shard.delay), 0.0)
		var velocity: Vector3 = shard.velocity
		var gravity: Vector3 = shard.gravity
		var shrink := 1.0 - smoothstep(FALL_SECONDS * 0.55, FALL_SECONDS, s)
		var turn := Basis(shard.axis, float(shard.spin) * t)
		piece.global_transform = Transform3D(turn * (shard.basis as Basis) * shrink,
			(shard.origin as Vector3) + velocity * t + gravity * 0.5 * t * t)


func _finish() -> void:
	if not _released:
		Vfx.release_hold(_card, _visual, false)
	for shard in _shards:
		if is_instance_valid(shard.node):
			shard.node.queue_free()
	_shards.clear()
