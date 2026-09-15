extends Node3D
class_name BallisticArrow
## The targeting arrow: a ribbon of light from the source card to the target card,
## with a real arrowhead, an additive glow and a flow running along its length.
##
## HOW IT IS BUILT (and why the distortion is gone):
##
##  1. The curve is a `Curve3D` and it is ONE cubic segment, from the source straight to
##     the target. That single segment is the fix for the "two extrema" shape — see the
##     note on `peak_ratio` below. It is `tessellate()`d into a polyline.
##  2. Every direction the shader needs is computed HERE, on the CPU, once per sample:
##     the tangent, the side vector, and `t` (how far along the arc that sample is).
##     They are baked into the vertex UVs and COLORS.
##  3. The mesh is emitted at UNIT (stub) width, so the shader scales it out along the
##     baked side vector and the widening stays smooth through the bend. Nothing is
##     re-derived from screen-space derivatives or from neighbouring UVs.
##  4. The arrowhead is real geometry — triangles aligned to the final tangent — sharing
##     the same fragment look, so it matches the shaft instead of looking like a decal.
##  5. The shape is ASSERTED, not assumed: every rebuild counts the curve's apexes and
##     inflections and warns if it is not a single clean arch. See _check_shape().
##
## TWO THINGS THAT WOULD OTHERWISE BITE:
##  * Godot stores vertex COLOR as 8-bit UNSIGNED normalized. A side vector with a
##    negative component would clamp to 0 and deform the ribbon, so the CPU bakes
##    `side * 0.5 + 0.5` and the shader decodes it back.
##  * Because the shader expands the mesh, the mesh's own AABB is far too small, and the
##    renderer would cull the arrow off-screen. `extra_cull_margin` below covers the
##    widest possible ribbon.
##
## Public API (kept — callers elsewhere rely on it):
##   set_is_aiming(active, source_position)   # positions are GLOBAL
##   lock_arc(target_position) / unlock_arc()
##   set_arc_color(colour)
##   update_arc(start, end) / hide_arc()

const ARC_MATERIAL := preload("res://shaders/target_arc_material.tres")

## Half-width, in metres, that the ribbon vertices are baked at. It only exists so the
## triangles are not degenerate before the shader widens them; the shader subtracts the
## same value back out. Must match the material's `edge_stub`.
const EDGE_STUB := 0.001

@export_group("Curve")
## Curve shape. Both ends are vertical by construction — the arrow leaves the source
## straight up and arrives straight down on the target's centre — and `peak_ratio`
## below sets how tall the arch between them is.
##
## WHY ONE SEGMENT MATTERS: with a single cubic segment from P0 to P3 and both controls
## on the up axis, the up-coordinate is u(t) with control values (u0, u0+a, u3+b, u3).
## Its derivative is a quadratic,
##     u'(t) = a(1-t)^2 + 2(1-t)t(u3 + b - u0 - a) - b t^2
## With equal controls (a = b) that becomes -2*D*t^2 + 2(D-a)t + a = 0 for D = u3 - u0,
## whose roots are t = ((D - a) -/+ sqrt(D^2 + a^2)) / (2D): for D > 0 one root is
## negative and the other is inside (0, 1); for D < 0 one is above 1 and the other is
## inside (0, 1); for D = 0 it degenerates to the single root t = 1/2. So there is always
## exactly one apex. _check_shape() verifies that at runtime rather than trusting the
## reasoning above. Splitting the curve into two segments and giving the midpoint its
## own handles (the previous attempt) destroys it: the interior handles pull against the
## end ones and a second extremum appears, which is the S-shaped wiggle you saw.
## The arch's height, as a multiple of the distance between the two cards. This is the
## knob that shapes the curve: the control points are derived from it (see
## _sample_curve), which keeps the two ends vertical — leaving the source straight UP and
## arriving straight DOWN onto the target — while the middle overshoots above the target
## before coming back down onto it. 1.2 is what the reference asks for; lower it if the
## arch sweeps too far across the board for your camera.
@export var peak_ratio: float = 1.2
## Sideways lean of the DEPARTURE only, as a fraction of the span. 0 (the default) means
## the departure is exactly straight up, which is what the reference shows. It cannot be
## applied at the target end — a sideways term there would stop the arrival being
## vertical — but it is the escape hatch for the one degenerate case: when the two cards
## are exactly collinear with the screen's up axis, a pure arch collapses onto a line.
@export var lean: float = 0.0
## Bow PERPENDICULAR to the chord, instead of along the screen's up axis.
##
## The default (screen-up) gives the classic camera-facing hop, and it is right whenever the
## two cards are roughly level on screen: the chord is horizontal, so screen-up is already
## perpendicular to it. It breaks for a link between the two battle rows — a block — whose
## chord runs straight up the screen. Bowing along the chord makes the arch run along it and
## read as a long loop instead of a bow (measured: 1.54 m of path for an 0.85 m span, with a
## peak of 0.00x). This mode rotates the bow with the chord, so a same-row link still gets
## the classic hop and a cross-row link gets a sideways one.
@export var bow_perpendicular: bool = false
## How far above the board the whole arrow sits, in metres. The ribbon is built in the
## board plane — the same height as the card faces — and a co-planar additive ribbon is
## at the mercy of draw order, so parts of it can end up behind a card. A few centimetres
## of height settles that for a camera looking down, at no visual cost.
@export var arc_height: float = 0.035
## Curve3D tessellation: subdivision stages and the angle tolerance in degrees.
@export var max_stages: int = 6
@export var tolerance_degrees: float = 1.5
## Below this distance the arrow is not drawn at all (it would be a dot).
@export var min_distance: float = 0.9
## Keep the arch inside the window: its apex is held at least `screen_margin` pixels below
## the top edge, so a tall overshoot never leaves the visible area. `peak_ratio` is the
## shape you want; this only ever REDUCES it, and only when it would not fit.
@export var clamp_to_screen: bool = true
@export var screen_margin: float = 90.0
## Floor for that clamp, so a target near the top of the screen still gets a visible bend
## instead of a straight line.
const MIN_PEAK_RATIO := 0.2

@export_group("Arrowhead")
## Head width as a multiple of the ribbon's widest half-width, and its length as a
## multiple of that same width. It only needs to be a little wider than the shaft to read
## as a head — pushed further it stops looking like part of the arrow and starts looking
## like a shape stuck on the end.
@export var head_width_scale: float = 1.25
@export var head_length_scale: float = 1.5
## How far the back of the head is notched in, as a fraction of the head's length.
@export var head_notch: float = 0.3

var is_aiming: bool = false
var start_pos: Vector3 = Vector3.ZERO
var is_active: bool = false
var locked: bool = false
## Where a locked arc points. Remembered so the ribbon can be rebuilt when its ORIGIN moves
## — a locked destination does not mean a frozen start (see _process).
var locked_target: Vector3 = Vector3.ZERO

@onready var line: MeshInstance3D = $Line
var _shaft_material: ShaderMaterial = null
var _head_material: ShaderMaterial = null
## The card the arrow is coming FROM, when the caller gave us one. Re-read every frame so
## the origin tracks it rather than freezing wherever it was when aiming began.
var _source_card: Card = null
var _shape_ok_reported: bool = false
var _shape_warning_state: int = -1

func _ready() -> void:
	_shaft_material = ARC_MATERIAL.duplicate()
	_head_material = ARC_MATERIAL.duplicate()
	# The head is real geometry: the shader must not widen it. Setting both widths to
	# the stub makes the vertex offset exactly zero, and a high core_ratio fills it in
	# so it reads as a solid glowing shape.
	_head_material.set_shader_parameter("thin_width", EDGE_STUB)
	_head_material.set_shader_parameter("thick_width", EDGE_STUB)
	_head_material.set_shader_parameter("core_ratio", 0.92)
	line.mesh = null
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader expands the mesh well past its baked bounds, so give the renderer room.
	line.extra_cull_margin = 2.0
	hide_arc()

func _process(_delta: float) -> void:
	if not is_aiming:
		hide_arc()
		return
	# Re-read the origin from the source card when we have one, so the arrow stays
	# attached to it while it moves. See set_is_aiming_from_card().
	var origin_moved: bool = false
	if _source_card != null and is_instance_valid(_source_card):
		var fresh: Vector3 = _source_card.get_global_top_centre()
		origin_moved = fresh.distance_to(start_pos) > 0.001
		start_pos = fresh
	if not locked:
		update_arc(start_pos, get_mouse_target_position())
	elif origin_moved:
		# A locked arc has a fixed DESTINATION, but its origin can still be moving. The AI
		# picks a target a frame or two after casting, while the Summon is still tweening
		# out of its owner's hand, and without this rebuild the ribbon stays drawn from
		# wherever the card happened to be at that instant — measured x of -0.73 instead of
		# the -4.52 it settles at. Stops rebuilding as soon as the card stops moving.
		update_arc(start_pos, locked_target)

## Where the mouse is pointing on the board plane (the table's surface).
func get_mouse_target_position() -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return start_pos
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var board := Plane(Vector3.UP, 0.0)
	var hit = board.intersects_ray(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
	return start_pos if hit == null else hit

## Both positions are GLOBAL (world) points.
func update_arc(start: Vector3, end: Vector3) -> void:
	if start.distance_to(end) < min_distance:
		hide_arc()
		return
	show_arc()
	# Lift the whole arrow just clear of the board. A pure translation, so the curve's
	# shape, tangents and side vectors are unchanged — it only puts the ribbon in front of
	# the card faces instead of exactly level with them.
	_build(start + Vector3.UP * arc_height, end + Vector3.UP * arc_height)

## Older name for the same thing; kept so existing callers keep working.
func set_target_position(starting_position: Vector3, target_pos: Vector3) -> void:
	update_arc(starting_position, target_pos)

func show_arc() -> void:
	is_active = true
	line.visible = true

func hide_arc() -> void:
	is_active = false
	if line != null:
		line.visible = false

func lock_arc(pos: Vector3) -> void:
	locked_target = pos
	update_arc(start_pos, pos)
	locked = true

func unlock_arc() -> void:
	locked = false

func set_is_aiming(value: bool, source: Vector3 = Vector3.ZERO) -> void:
	# An explicit position means "aim from exactly here", so stop following any card.
	_source_card = null
	is_aiming = value
	start_pos = source
	if value:
		locked = false
		show_arc()
	else:
		hide_arc()

## Aim from a CARD rather than from a fixed point: the origin is re-read from the card
## every frame.
##
## This matters for stack effects. A freshly created card is positioned through a 0.3 s
## Tween (Stack.update_card_positions -> animate_card), so at the instant targeting starts
## it is still at the world origin — which a top-down camera projects to the MIDDLE OF THE
## SCREEN. Freezing that position left the arrow originating there forever. Following the
## card keeps the arrow attached to its top edge while it settles, and if the card moves
## afterwards.
func set_is_aiming_from_card(value: bool, card: Card) -> void:
	set_is_aiming(value, card.get_global_top_centre() if card != null else Vector3.ZERO)
	_source_card = card if value else null

## Recolour the beam from a single colour: the core is lifted towards white and the
## rest kept saturated, so a caller can hand over e.g. orange and still get a coherent
## beam rather than a flat one.
func set_arc_color(new_color: Color) -> void:
	for mat in [_shaft_material, _head_material]:
		if mat == null:
			continue
		mat.set_shader_parameter("glow_color", new_color)
		mat.set_shader_parameter("core_color", new_color.lerp(Color.WHITE, 0.65))

# ---------------------------------------------------------------- geometry ----------

func _build(from: Vector3, to: Vector3) -> void:
	var points: PackedVector3Array = _sample_curve(from, to)
	var count: int = points.size()
	if count < 3:
		return
	_check_shape(points)

	# Per-sample tangent and side, computed ONCE here, never in the shader.
	var tangents: Array[Vector3] = []
	var sides: Array[Vector3] = []
	var last_side: Vector3 = _screen_right()
	for i in range(count):
		var prev: Vector3 = points[maxi(i - 1, 0)]
		var next: Vector3 = points[mini(i + 1, count - 1)]
		var tangent: Vector3 = next - prev
		if tangent.length_squared() < 0.0000000001:
			tangent = to - from
		if tangent.length_squared() < 0.0000000001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		tangents.append(tangent)
		# side = tangent x UP keeps the ribbon lying flat on the board.
		var side: Vector3 = tangent.cross(Vector3.UP)
		if side.length_squared() < 0.00000001:
			# Nearly vertical tangent: reuse the previous plane instead of flipping.
			side = last_side
		side = side.normalized()
		sides.append(side)
		last_side = side

	# t: fraction of the total arc length at each sample.
	var ts: Array[float] = []
	var total: float = 0.0
	ts.append(0.0)
	for i in range(1, count):
		total += points[i].distance_to(points[i - 1])
		ts.append(total)
	for i in range(count):
		ts[i] = ts[i] / maxf(total, 0.00001)

	# The head is sized from the ribbon's WIDEST half-width, read from the material so
	# there is a single source of truth for the widths.
	var thick: float = _float_param(_shaft_material, "thick_width", 0.075)
	var head_half: float = thick * head_width_scale
	var head_len: float = minf(thick * head_length_scale, total * 0.4)

	# The shaft stops where the head begins (with a little overlap so no seam shows).
	var shaft_last: int = count - 1
	var tip: Vector3 = points[count - 1]
	while shaft_last > 1 and points[shaft_last].distance_to(tip) < head_len * 0.85:
		shaft_last -= 1

	var mesh: ArrayMesh = _build_shaft(points, sides, ts, shaft_last)
	mesh = _build_head(mesh, points[shaft_last], tip, sides[shaft_last], tangents[shaft_last], head_half)
	# Applied per surface, defensively: if SurfaceTool.commit(existing) ever fails to
	# append, the shaft still gets its material instead of the arrow going untextured.
	var surfaces: int = mesh.get_surface_count()
	if surfaces >= 1:
		mesh.surface_set_material(0, _shaft_material)
	if surfaces >= 2:
		mesh.surface_set_material(1, _head_material)
	line.mesh = mesh

## `peak_ratio`, reduced as far as needed to keep the arch's apex inside the window.
##
## The apex sits above the middle of the chord, so its screen position can be solved
## directly: project the chord's midpoint, then a point one metre further along the
## screen-up axis — the difference is how many pixels a metre of arch costs there. That
## gives the tallest arch that still leaves `screen_margin` pixels above it, so a tall
## overshoot can never leave the visible area.
##
## The result is floored at MIN_PEAK_RATIO, so a target near the top of the screen still
## gets a visible bend instead of collapsing into a straight line.
func _peak_ratio_for(from: Vector3, to: Vector3, up: Vector3, span: float) -> float:
	if not clamp_to_screen:
		return peak_ratio
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or span < 0.0001:
		return peak_ratio
	var mid: Vector3 = (from + to) * 0.5
	var here: Vector2 = cam.unproject_position(mid)
	var one_metre_away: Vector2 = cam.unproject_position(mid + up)
	# Positive when moving along the world "up" axis moves up the screen, which it does for
	# a camera looking down at the board. Note viewport y grows DOWNWARDS.
	var px_per_metre: float = here.y - one_metre_away.y
	if px_per_metre < 1.0:
		return peak_ratio
	var room_px: float = here.y - screen_margin
	var allowed: float = room_px / px_per_metre / span
	return clampf(minf(peak_ratio, allowed), MIN_PEAK_RATIO, peak_ratio)

## ONE cubic segment from the source to the target, tessellated into a polyline.
##
## Curve3D's in/out controls are offsets RELATIVE to their own point, so a two-point
## curve is Bezier(P0, P0 + out(0), P1 + in(1), P1).
##
## `peak_ratio` drives the shape: the two controls are placed symmetrically, and with
## both equal to h the curve's deviation from the chord at its middle is 3h/4 times the
## chord's HORIZONTAL extent. So h = peak_ratio / 0.75 gives a peak of exactly
## `peak_ratio` when the two cards are level on screen, and a smaller peak when the arrow
## runs more vertically — the number printed by _check_shape makes that visible. Equal
## controls also keep the control polygon convex, which is what guarantees no inflection.
func _sample_curve(from: Vector3, to: Vector3) -> PackedVector3Array:
	var span: float = from.distance_to(to)
	var up: Vector3 = _bow_axis(from, to)
	# Not `peak_ratio` directly: _peak_ratio_for() trims it when the arch would overshoot
	# past the top of the window. With a perpendicular bow the apex does not move up the
	# screen at all, which that function detects and leaves the ratio alone.
	var handle: float = _peak_ratio_for(from, to, up, span) / 0.75

	var curve := Curve3D.new()
	curve.add_point(from)
	curve.add_point(to)
	# Departure: straight up the screen (plus `lean`, which is 0 by default and only
	# exists as an escape hatch when the two cards are collinear on screen).
	curve.set_point_out(0, up * (span * handle) + _screen_right() * (span * lean))
	# Arrival: the tangent at the end is `to - (to + in)`, so a control point "above" the
	# target makes the arrow come straight down onto its centre. Deliberately no sideways
	# term here — that is what keeps the arrival vertical.
	curve.set_point_in(1, up * (span * handle))

	return curve.tessellate(max_stages, tolerance_degrees)

## Runtime assertion on the curve's shape, because this mesh is rebuilt every frame and
## a wrong-looking curve would otherwise be a silent, repeating defect.
##
## Required: exactly ONE apex along the screen's up axis (a single arch) and ZERO
## inflection points in the screen plane (an inflection is precisely what an S-shaped
## wiggle is). It also reports the arch's height, so the number `peak_ratio` is supposed
## to produce can be checked against what is actually on screen.
## The direction the arch bulges in.
##
## The default is the screen's up axis — the classic camera-facing hop, right whenever the
## two cards are roughly level on screen. With `bow_perpendicular` the bow is instead kept
## perpendicular to the chord AS SEEN ON SCREEN: take the chord's screen direction (its
## components along the camera's right and up axes), rotate it a quarter turn, and flip it so
## it still bulges away from the board rather than across it. A same-row chord therefore
## still hops up the screen, while a cross-row chord — a block between the two rows — bows
## sideways instead of running along itself.
func _bow_axis(from: Vector3, to: Vector3) -> Vector3:
	var up: Vector3 = _screen_up()
	if not bow_perpendicular:
		return up
	var right: Vector3 = _screen_right()
	var chord: Vector3 = to - from
	var bow: Vector3 = right * (-chord.dot(up)) + up * chord.dot(right)
	if bow.length() < 0.0001:
		return up
	bow = bow.normalized()
	return -bow if bow.dot(up) < 0.0 else bow

func _check_shape(points: PackedVector3Array) -> void:
	var bow: Vector3 = _screen_up()
	if points.size() >= 2:
		bow = _bow_axis(points[0], points[points.size() - 1])
	var apexes: int = _count_direction_changes(points, bow)
	var inflections: int = _count_inflections(points)
	var peak: float = _peak_over_chord(points)
	if apexes == 1 and inflections == 0:
		if not _shape_ok_reported:
			_shape_ok_reported = true
			print("[BallisticArrow] curve shape OK: 1 apex, 0 inflections, peak %.2fx the card distance" % peak)
		_shape_warning_state = -1
		return
	var state: int = apexes * 100 + inflections
	if state != _shape_warning_state:
		_shape_warning_state = state
		push_warning("[BallisticArrow] curve shape is wrong: %d apex(es) along the bow axis (want 1), %d inflection(s) (want 0), peak %.2fx. Ease `peak_ratio`, or set `bow_perpendicular` for a cross-row link." % [apexes, inflections, peak])

## The arch's height above the straight line joining the two ends, as a fraction of that
## line's length — the number `peak_ratio` is meant to produce.
func _peak_over_chord(points: PackedVector3Array) -> float:
	if points.size() < 2:
		return 0.0
	var up: Vector3 = _screen_up()
	var right: Vector3 = _screen_right()
	var a := Vector2(points[0].dot(right), points[0].dot(up))
	var d := Vector2(points[points.size() - 1].dot(right), points[points.size() - 1].dot(up)) - a
	var length: float = d.length()
	if length < 0.0001:
		return 0.0
	var normal := Vector2(-d.y, d.x) / length
	var peak: float = 0.0
	for p in points:
		var q := Vector2(p.dot(right), p.dot(up))
		peak = maxf(peak, absf((q - a).dot(normal)))
	return peak / length

## How many times the samples' projection onto `axis` reverses direction.
func _count_direction_changes(points: PackedVector3Array, axis: Vector3) -> int:
	var changes: int = 0
	var last_dir: float = 0.0
	for i in range(points.size() - 1):
		var delta: float = points[i + 1].dot(axis) - points[i].dot(axis)
		if absf(delta) < 0.000001:
			continue
		var dir: float = signf(delta)
		if last_dir != 0.0 and not is_equal_approx(dir, last_dir):
			changes += 1
		last_dir = dir
	return changes

## How many times the curve swaps its turning direction, in the screen plane. Zero means
## a single smooth bow; one or more means an S-curve.
func _count_inflections(points: PackedVector3Array) -> int:
	var up: Vector3 = _screen_up()
	var right: Vector3 = _screen_right()
	var inflections: int = 0
	var last_sign: float = 0.0
	for i in range(points.size() - 2):
		var a := Vector2(points[i].dot(right), points[i].dot(up))
		var b := Vector2(points[i + 1].dot(right), points[i + 1].dot(up))
		var c := Vector2(points[i + 2].dot(right), points[i + 2].dot(up))
		var turn: float = (b - a).cross(c - b)
		if absf(turn) < 0.0000001:
			continue
		var s: float = signf(turn)
		if last_sign != 0.0 and not is_equal_approx(s, last_sign):
			inflections += 1
		last_sign = s
	return inflections

func _build_shaft(points: PackedVector3Array, sides: Array[Vector3], ts: Array[float], last: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(last):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var sa: Vector3 = sides[i] * EDGE_STUB
		var sb: Vector3 = sides[i + 1] * EDGE_STUB
		# Two rings, each with a left and a right vertex. UV.x carries `t` (position
		# along the arc), UV.y says which edge, and COLOR carries the side vector plus
		# `t` again for the vertex shader.
		_add_vertex(st, a + sa, sides[i], ts[i], 0.0)
		_add_vertex(st, a - sa, sides[i], ts[i], 1.0)
		_add_vertex(st, b - sb, sides[i + 1], ts[i + 1], 1.0)
		_add_vertex(st, a + sa, sides[i], ts[i], 0.0)
		_add_vertex(st, b - sb, sides[i + 1], ts[i + 1], 1.0)
		_add_vertex(st, b + sb, sides[i + 1], ts[i + 1], 0.0)
	return st.commit()

## The arrowhead: real triangles aligned to the final tangent, wider than the ribbon so
## it reads as a head. Building it as geometry (rather than an SDF/discard in the
## fragment shader) keeps it stable and lets the same glow shader light it.
## The head's BASE is the shaft's last sample — not a straight-line back-off from the tip.
## On a curved approach a straight back-off lands off the curve, which is exactly what
## left the head looking detached from the shaft.
func _build_head(mesh: ArrayMesh, base: Vector3, tip: Vector3, side: Vector3, tangent: Vector3, half_width: float) -> ArrayMesh:
	var length: float = base.distance_to(tip)
	var wing_l: Vector3 = base + side * half_width
	var wing_r: Vector3 = base - side * half_width
	var notch: Vector3 = base + tangent * (length * head_notch)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# UV.x is constant across the head so the flow wave lights the whole head together
	# instead of streaking across it; UV.y runs across the head as usual.
	_add_vertex(st, tip, side, 0.0, 0.5)
	_add_vertex(st, wing_l, side, 0.0, 0.0)
	_add_vertex(st, notch, side, 0.0, 0.5)
	_add_vertex(st, tip, side, 0.0, 0.5)
	_add_vertex(st, notch, side, 0.0, 0.5)
	_add_vertex(st, wing_r, side, 0.0, 1.0)
	# Append as a second surface of the same mesh, so the arrow is one node.
	return st.commit(mesh)

## Both the shaft and the head bake a valid unit side into COLOR so the shader's
## normalise can never meet a zero vector; COLOR is 8-bit UNSIGNED in the vertex buffer,
## so the side is remapped into 0..1 here and decoded in the shader.
func _add_vertex(st: SurfaceTool, pos: Vector3, side: Vector3, t: float, edge: float) -> void:
	st.set_color(Color(side.x * 0.5 + 0.5, side.y * 0.5 + 0.5, side.z * 0.5 + 0.5, t))
	st.set_uv(Vector2(t, edge))
	st.add_vertex(pos)

# -------------------------------------------------------------------- helpers ------

## Read a float uniform back out of a material, with a fallback for a failed lookup
## (get_shader_parameter() returns null for an unknown name, and float(null) is 0.0).
func _float_param(mat: ShaderMaterial, name: String, fallback: float) -> float:
	if mat == null:
		return fallback
	var value: Variant = mat.get_shader_parameter(name)
	if value is float or value is int:
		return float(value)
	return fallback

## A direction with its world-Y component removed, normalised — turns the camera's own
## axes into directions lying flat on the board, which is the plane the arrow lives in.
func _flatten(v: Vector3) -> Vector3:
	var flat: Vector3 = v - Vector3.UP * v.dot(Vector3.UP)
	if flat.length_squared() < 0.000001:
		return Vector3.FORWARD
	return flat.normalized()

func _screen_right() -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.RIGHT
	return _flatten(cam.global_transform.basis.x)

func _screen_up() -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.FORWARD
	return _flatten(cam.global_transform.basis.y)
