extends Node3D
## THE BLOCK LINK: a targeting line from an ATTACKER to the BLOCKER in its way, after the reference clip
## (~/Desktop/Clips/arrow3, frames 71-120). It LOOPS until it is freed (the clash starts, the blocker changes, the
## combat ends), each loop:
##   1. DRAW   (`draw_seconds`, clip frames 75-87) — a bright SPARK leaves the attacker and races along the arch,
##             drawing the line behind it; when the spark reaches the blocker the line is complete;
##   2. HOLD   (`hold_seconds`, frames 87-100) — the whole line, still, a soft glow where it landed;
##   3. VANISH (`vanish_seconds`, frames 100-117) — the line is erased FROM THE BACK (the attacker's end) toward the
##             blocker, dimming as it goes;
##   4. PAUSE  (`loop_pause_seconds`) — then again.
## The line is clean and STABLE — a thin white-hot core with a pink-red glow (shaders/block_link.gdshader). Its shape
## never moves or distorts; only the visible span does. No arrowhead: the head is the spark.
##
## The arch rises in WORLD Y (its height): from the attacker's TOP EDGE — its printed top, the end of its long axis
## that FACES the blocker (`attacker_top_edge()`; the screen-top edge is the far side for the opponent's attacker and
## made the curve hook back over the card) — up to an apex `apex_ratio` of the chord above the higher end (between
## `min_apex` and `max_apex` m), and down onto the blocker's face CENTRE. Both ends follow the cards every frame. Built in GLOBAL
## space (`top_level`).
##
## The API the probes read: `is_aiming`, `start_pos` (the attacker's top edge), `locked_target` (the blocker's centre),
## `points()` (the sampled curve, ending at `end_pos`) and `phase_at(age)` (the deterministic timeline).
##
## TWO TARGETS. During an attack the link points at the DEFENDING PLAYER (`setup_point()`: a point just past the
## screen's top or bottom edge, so the arc leaves the screen); once a blocker is chosen it is rebuilt to the BLOCKER
## (`setup()`), and the arc plunges `penetration` m into that card, the opaque card hiding the end (depth-tested).

const LINE_SHADER := preload("res://shaders/block_link.gdshader")
const HALO_SHADER := preload("res://shaders/orb_halo.gdshader")

@export var draw_seconds: float = 0.42
@export var hold_seconds: float = 0.45
@export var vanish_seconds: float = 0.55
@export var loop_pause_seconds: float = 0.2
## The spark that draws the line (m), and how bright it burns.
@export var spark_size: float = 0.13
@export var spark_intensity: float = 3.0
## The apex's height above the higher end: this fraction of the chord, and never less than `min_apex` (m).
@export var apex_ratio: float = 0.9
@export var min_apex: float = 0.6
## ...and never more than this (m): the link to the defending player spans the whole board, and an arch scaled to that
## rose most of the way to the camera, which flattened it on screen into a straight line.
@export var max_apex: float = 1.3
## The link to the PLAYER may lean very slightly out of its vertical plane (the plane through world Y and the line
## between its two ends), by this fraction of the chord, toward the attacker's side of the screen. Kept SMALL on
## purpose: the arc belongs in that vertical plane, and 0.2 visibly swung it off to the side (the user's call).
@export var player_bow_ratio: float = 0.04
## The ribbon's full width (the glow's reach; the core is a fraction of it, set on the material).
@export var ribbon_width: float = 0.085
## The glow on the blocker where the line lands (m), and its colour.
@export var landing_glow_size: float = 0.32
@export var glow_color: Color = Color(1.0, 0.07, 0.20)
## How far below the blocker's face the line ends: the opaque card hides that stretch, so the arc PLUNGES INTO the
## card instead of stopping on it (the line is depth-tested).
@export var penetration: float = 0.16
const SAMPLES := 64

var is_aiming: bool = false
var start_pos: Vector3 = Vector3.ZERO
var locked_target: Vector3 = Vector3.ZERO
## A party's links start their loops a little apart.
var loop_offset: float = 0.0
## A frozen moment for screenshots (tools/block_link_demo): >= 0 pins the animation's age.
var frozen_age: float = -1.0

var _from: Card = null
var _to: Card = null
## A target that is a POINT, not a card (the defending player, off screen): a Callable returning a global position.
var _to_point: Callable = Callable()
## Where the line actually ends (global): under the blocker's face, or the player point.
var end_pos: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _mesh := ImmediateMesh.new()
var _line_mat := ShaderMaterial.new()
var _landing: MeshInstance3D = null
var _landing_mat := ShaderMaterial.new()
var _spark: MeshInstance3D = null
var _spark_mat := ShaderMaterial.new()
var _points: PackedVector3Array = PackedVector3Array()

func _init() -> void:
	top_level = true

## Link `attacker` to the card `blocker` (the arc plunges into it).
func setup(attacker: Card, blocker: Card) -> void:
	_from = attacker
	_to = blocker
	is_aiming = attacker != null and blocker != null
	_build_nodes()

## Link `attacker` to a POINT (the defending player off screen): `point` returns its global position each frame.
func setup_point(attacker: Card, point: Callable) -> void:
	_from = attacker
	_to_point = point
	is_aiming = attacker != null and point.is_valid()
	_build_nodes()

func targets_card() -> bool:
	return _to != null

func _build_nodes() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	add_child(mi)
	_line_mat.shader = LINE_SHADER
	_line_mat.render_priority = 100
	_line_mat.set_shader_parameter("glow_color", glow_color)
	_landing = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * landing_glow_size
	_landing.mesh = quad
	_landing_mat.shader = HALO_SHADER
	_landing_mat.set_shader_parameter("halo_color", glow_color.lerp(Color.WHITE, 0.35))
	_landing_mat.set_shader_parameter("falloff", 2.2)
	_landing_mat.set_shader_parameter("skirt_amount", 0.45)
	_landing_mat.render_priority = 101
	_landing.material_override = _landing_mat
	_landing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_landing)
	# THE SPARK: a small white-hot point with a pink skirt, drawn above the line.
	_spark = MeshInstance3D.new()
	var spark_quad := QuadMesh.new()
	spark_quad.size = Vector2.ONE * spark_size
	_spark.mesh = spark_quad
	_spark_mat.shader = HALO_SHADER
	_spark_mat.set_shader_parameter("halo_color", Color(1.0, 0.82, 0.88))
	_spark_mat.set_shader_parameter("falloff", 3.2)
	_spark_mat.set_shader_parameter("skirt_amount", 0.7)
	_spark_mat.render_priority = 102
	_spark.material_override = _spark_mat
	_spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spark)
	_rebuild()

## The sampled curve, attacker first (global).
func points() -> PackedVector3Array:
	return _points

## The timeline at `age` seconds: [draw_from, draw_to, spark_t, landing, flare].
##   draw_from..draw_to is the visible span (0 = attacker, 1 = blocker; empty when draw_to <= draw_from);
##   spark_t is where the spark is (< 0: no spark); landing (0..1) is the glow on the blocker; flare (0..1) is the
##   spark burning out on the blocker just after it lands.
func phase_at(age: float) -> Array:
	var k: float = age - loop_offset
	if k < 0.0:
		return [0.0, 0.0, -1.0, 0.0, 0.0]
	var cycle: float = draw_seconds + hold_seconds + vanish_seconds + loop_pause_seconds
	var into: float = fmod(k, cycle)
	if into < draw_seconds:
		var t: float = ease(into / maxf(draw_seconds, 0.0001), -1.6)
		return [0.0, t, t, 0.0, 0.0]
	into -= draw_seconds
	if into < hold_seconds:
		# The spark has landed: it flares out on the blocker as the landing glow comes up.
		var h: float = into / maxf(hold_seconds, 0.0001)
		return [0.0, 1.0, 1.0 if h < 0.25 else -1.0, smoothstep(0.0, 0.3, h), clampf(h / 0.25, 0.0, 1.0)]
	into -= hold_seconds
	if into < vanish_seconds:
		var v: float = ease(into / maxf(vanish_seconds, 0.0001), -1.4)
		return [v, 1.0, -1.0, 1.0 - v, 0.0]
	return [1.0, 0.0, -1.0, 0.0, 0.0]

func _process(delta: float) -> void:
	_age = frozen_age if frozen_age >= 0.0 else _age + delta
	_rebuild()

func _rebuild() -> void:
	_mesh.clear_surfaces()
	var target_ok: bool = (_to != null and is_instance_valid(_to)) or (_to == null and _to_point.is_valid())
	if not is_aiming or _from == null or not is_instance_valid(_from) or not target_ok:
		if _landing != null:
			_landing.visible = false
			_spark.visible = false
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if _to != null:
		locked_target = _to.get_global_face_centre()
		end_pos = locked_target - Vector3.UP * penetration
	else:
		locked_target = _to_point.call()
		end_pos = locked_target
	start_pos = attacker_top_edge(_from, locked_target)
	var a: Vector3 = start_pos
	var b: Vector3 = end_pos
	# A quadratic Bezier peaks HALF way to its control point, so the control sits about twice the apex above the ends.
	# The apex is measured from the SURFACE ends (start, and the target's face), so plunging deeper does not lift it.
	var apex: float = clampf(a.distance_to(locked_target) * apex_ratio, min_apex, max_apex)
	var control: Vector3 = (a + locked_target) * 0.5
	control.y = maxf(a.y, locked_target.y) + apex * 2.0 - absf(a.y - locked_target.y) * 0.5
	if _to == null and cam != null:
		var chord: Vector3 = locked_target - a
		var side: Vector3 = chord.cross(-cam.global_basis.z)
		side.y = 0.0
		if side.length_squared() > 0.000001:
			side = side.normalized()
			# Toward the attacker's side of the screen (right of centre bows right).
			var right: Vector3 = cam.global_basis.x
			var attacker_right: float = (a - cam.global_position).dot(right)
			if side.dot(right) * attacker_right < 0.0:
				side = -side
			control += side * chord.length() * player_bow_ratio * 2.0
	_points.resize(SAMPLES + 1)
	for i in SAMPLES + 1:
		var t: float = float(i) / SAMPLES
		_points[i] = a.lerp(control, t).lerp(control.lerp(b, t), t)
	var phase: Array = phase_at(_age)
	var draw_from: float = phase[0]
	var draw_to: float = phase[1]
	_line_mat.set_shader_parameter("draw_from", draw_from)
	_line_mat.set_shader_parameter("draw_to", draw_to)
	# Dims a little as it is erased.
	_line_mat.set_shader_parameter("fade", 1.0 - 0.4 * draw_from)
	var basis_cam: Basis = cam.global_basis if cam != null else Basis()
	# THE SPARK at the drawing tip (and, for a moment after landing, on the blocker, shrinking away).
	var spark_t: float = phase[2]
	_spark.visible = spark_t >= 0.0
	if _spark.visible:
		var landed: float = phase[4]
		_spark.global_transform = Transform3D(basis_cam.scaled(Vector3.ONE * (1.0 + 0.6 * landed)), _sample(spark_t))
		_spark_mat.set_shader_parameter("intensity", spark_intensity * (1.0 - landed))
	# THE LANDING GLOW on the blocker, through the hold and out with the line.
	var landing: float = phase[3]
	# (Only on a card: the player point is off screen.) Just above the face, where the line goes in.
	_landing.visible = landing > 0.0 and _to != null
	if _landing.visible:
		_landing.global_transform = Transform3D(basis_cam, locked_target + Vector3.UP * 0.01)
		_landing_mat.set_shader_parameter("intensity", 1.2 * landing)
	if draw_to <= draw_from:
		return
	# A camera-facing ribbon, UV.x along the curve.
	var cam_pos: Vector3 = cam.global_position if cam != null else Vector3.UP * 10.0
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _line_mat)
	for i in SAMPLES + 1:
		var p: Vector3 = _points[i]
		var tangent: Vector3 = (_points[mini(i + 1, SAMPLES)] - _points[maxi(i - 1, 0)]).normalized()
		var across: Vector3 = tangent.cross((cam_pos - p).normalized()).normalized() * ribbon_width * 0.5
		var u: float = float(i) / SAMPLES
		_mesh.surface_set_uv(Vector2(u, 0.0))
		_mesh.surface_add_vertex(p - across)
		_mesh.surface_set_uv(Vector2(u, 1.0))
		_mesh.surface_add_vertex(p + across)
	_mesh.surface_end()

## The midpoint of the attacker's edge that faces `toward`: one end of the card's long (local Z) axis. An attacker
## faces the opponent's side, so this is its printed top edge, whichever seat it belongs to.
static func attacker_top_edge(card: Card, toward: Vector3) -> Vector3:
	var axis: Vector3 = card.global_transform.basis.z
	var half: Vector3 = axis.normalized() * card._card_face_size().y * 0.5 * axis.length()
	var a: Vector3 = card.global_position + half
	var b: Vector3 = card.global_position - half
	return a if a.distance_to(toward) <= b.distance_to(toward) else b

func _sample(t: float) -> Vector3:
	var f: float = clampf(t, 0.0, 1.0) * SAMPLES
	var i: int = mini(int(f), SAMPLES - 1)
	return _points[i].lerp(_points[i + 1], f - i)
