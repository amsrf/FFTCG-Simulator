extends Node3D
## Headless probe for the targeting arrow.
##
## Run it instead of the game:
##   "<godot>" --headless res://tests/arrow_probe.tscn --quit-after 900
##
## It drives BallisticArrow's own functions directly — no mouse, no menu — and prints the
## numbers that otherwise have to be judged by eye or by hand-explaining symptoms. Each
## check below corresponds to a bug that actually happened:
##
##   * the curve collapsing into a straight line (world-Y bow, foreshortened camera)
##   * the curve having two extrema (two Bezier segments with a handled midpoint)
##   * the arrowhead detached from the shaft (a straight back-off from the tip)
##   * the origin frozen at the world origin (a stack card still mid-tween)
#---
## It asserts nothing about how the arrow LOOKS — colour, glow and taste still need eyes.

const ARROW_SCENE := preload("res://ballistic_arrow.tscn")
const CARD_SCENE := preload("res://card.tscn")

## A typical targeting case: two cards level on screen, 1.2 m apart.
const FROM := Vector3(-0.6, 0.0, 0.0)
const TO := Vector3(0.6, 0.0, 0.0)

var _failures: Array[String] = []

func _ready() -> void:
	print("\n[ArrowProbe] ================= targeting arrow =================")
	var arrow: BallisticArrow = ARROW_SCENE.instantiate()
	add_child(arrow)

	_check_shape(arrow)
	_check_screen_clamp(arrow)
	_check_mesh(arrow)
	_check_origin_follows(arrow)

	_check_ice_cluster()
	_check_ice_projectile()
	_check_demo_browser()
	_report()
	get_tree().quit()

## The camera's own axes as they land on the board, then the curve they produce: the chord
## is horizontal on screen here, so the measured arch height should equal `peak_ratio`
## exactly.
func _check_shape(arrow: BallisticArrow) -> void:
	var up: Vector3 = arrow._screen_up()
	print("[ArrowProbe] screen-up %s | screen-right %s" % [up, arrow._screen_right()])
	print("[ArrowProbe] span %.2f m | peak_ratio %.2f" % [FROM.distance_to(TO), arrow.peak_ratio])

	var pts: PackedVector3Array = arrow._sample_curve(FROM, TO)
	var apexes: int = arrow._count_direction_changes(pts, up)
	var inflections: int = arrow._count_inflections(pts)
	var peak: float = arrow._peak_over_chord(pts)
	print("[ArrowProbe] samples %d | apexes %d | inflections %d | measured peak %.2fx"
		% [pts.size(), apexes, inflections, peak])

	_expect(apexes == 1, "curve has exactly 1 apex (got %d)" % apexes)
	_expect(inflections == 0, "curve has 0 inflections (got %d)" % inflections)
	_expect(absf(peak - arrow.peak_ratio) < 0.05,
		"measured peak %.2f matches peak_ratio %.2f" % [peak, arrow.peak_ratio])

## An absurd arch must be trimmed so its apex stays inside the window.
func _check_screen_clamp(arrow: BallisticArrow) -> void:
	var cam: Camera3D = $Camera3D
	var up: Vector3 = arrow._screen_up()
	var saved: float = arrow.peak_ratio
	arrow.peak_ratio = 6.0
	var clamped: float = arrow._peak_ratio_for(FROM, TO, up, FROM.distance_to(TO))
	arrow.peak_ratio = saved

	var mid: Vector3 = (FROM + TO) * 0.5
	var room_px: float = cam.unproject_position(mid).y - arrow.screen_margin
	var px_per_m: float = cam.unproject_position(mid).y - cam.unproject_position(mid + up).y
	print("[ArrowProbe] clamp: asked 6.00, allowed %.2f (%.0f px of room, %.0f px per metre)"
		% [clamped, room_px, px_per_m])
	_expect(clamped < 6.0, "an over-tall arch is clamped down (got %.2f)" % clamped)
	_expect(clamped >= BallisticArrow.MIN_PEAK_RATIO, "the clamp respects MIN_PEAK_RATIO")

## Both parts must be in the mesh, and the head's base must sit where the shaft ends.
func _check_mesh(arrow: BallisticArrow) -> void:
	arrow.update_arc(FROM, TO)
	var mesh: ArrayMesh = arrow.line.mesh
	var surfaces: int = 0 if mesh == null else mesh.get_surface_count()
	print("[ArrowProbe] mesh surfaces %d" % surfaces)
	_expect(surfaces == 2, "the shaft and the head are separate surfaces of one mesh")
	if surfaces < 2:
		return

	var shaft: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var head: PackedVector3Array = mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
	# Head vertex order is (tip, wing_l, notch, tip, notch, wing_r), so the two wings are
	# the head's base corners and their midpoint is where the head attaches.
	var head_base: Vector3 = (head[1] + head[5]) * 0.5
	var nearest: float = INF
	for s in shaft:
		nearest = minf(nearest, head_base.distance_to(s))
	print("[ArrowProbe] shaft %d verts (%d tris) | head %d verts (%d tris) | head base to nearest shaft vertex %.4f m (edge_stub %.4f)"
		% [shaft.size(), shaft.size() / 3, head.size(), head.size() / 3, nearest, BallisticArrow.EDGE_STUB])

	_expect(shaft.size() > 30, "the shaft has vertices")
	_expect(head.size() == 6, "the head is two triangles")
	# The shaft's last ring sits +/- EDGE_STUB from its centre line, so a correctly
	# attached head is about that far from the nearest shaft vertex. A head built by
	# backing off from the tip instead would land off the curve and be clearly further.
	_expect(nearest < 0.01, "the head's base touches the shaft (%.4f m away)" % nearest)

## The origin must be re-read from the source card, not captured once.
func _check_origin_follows(arrow: BallisticArrow) -> void:
	var card: Card = CARD_SCENE.instantiate()
	add_child(card)
	card.initialize(12, "player")
	card.global_position = Vector3(0.0, 0.0, 0.4)

	arrow.set_is_aiming_from_card(true, card)
	var before: Vector3 = arrow.start_pos
	# Stand in for Stack.animate_card(): the card is still moving when targeting starts.
	card.global_position = Vector3(0.0, 0.0, 0.9)
	arrow._process(0.0)
	var after: Vector3 = arrow.start_pos
	print("[ArrowProbe] card %s | origin %s -> %s (card moved 0.50 m, origin moved %.3f m)"
		% [card.card_name, before, after, before.distance_to(after)])

	_expect(before.distance_to(after) > 0.4, "the origin follows its source card")
	_expect(card.get_global_top_centre().distance_to(card.global_position) > 0.1,
		"the origin is the card's TOP edge, not its centre")
	arrow.set_is_aiming_from_card(false, card)

func _expect(condition: bool, what: String) -> void:
	if condition:
		print("[ArrowProbe]  ok  %s" % what)
	else:
		_failures.append(what)
		print("[ArrowProbe] FAIL %s" % what)

func _report() -> void:
	if _failures.is_empty():
		print("[ArrowProbe] RESULT: all checks passed\n")
		return
	print("[ArrowProbe] RESULT: %d check(s) FAILED" % _failures.size())
	for f in _failures:
		print("[ArrowProbe]   x %s" % f)
	print("")

## Basic asset/replay smoke check, kept in the allowed isolated visual harness.
func _check_ice_cluster() -> void:
	var preset = load("res://assets/vfx/elements/ice.tres")
	_expect(preset.impact_scene != null and preset.board_impact_scene != null, "Ice single and board cues load")
	var cue = preset.impact_scene.instantiate()
	add_child(cue)
	cue.queue_free()
	var cluster = load("res://assets/effects/ice/ice_cluster.tscn").instantiate()
	add_child(cluster)
	cluster.show_raised()
	_expect(cluster.get_child_count() == 7, "Ice enclosure has six crystals and ground")
	for piece in cluster.get_children():
		_expect(piece.mesh.get_surface_count() == 1 and piece.visible, "Ice piece has visible geometry")
	var motion: Tween = cluster.play()
	_expect(motion.is_valid(), "Ice growth starts")
	cluster.reset()
	_expect(not motion.is_valid(), "Ice reset cancels previous animation")
	cluster.queue_free()

func _check_ice_projectile() -> void:
	var projectile = load("res://assets/effects/ice/ice_projectile.tscn").instantiate()
	add_child(projectile)
	var ice_meshes: Array[Mesh] = [projectile._spike.mesh]
	for fragment in projectile._fragments:
		ice_meshes.append(fragment.mesh)
	var rounded_vertices := 0
	for mesh in ice_meshes:
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(0, vertices.size(), 3):
			var face_normal := (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i]).normalized()
			if face_normal.length_squared() < 0.5:
				continue
			for corner in range(3):
				if absf(face_normal.dot(normals[i + corner])) < 0.999:
					rounded_vertices += 1
	_expect(rounded_vertices == 0, "Ice faces retain flat normals instead of rounding across edges (%d rounded vertices)" % rounded_vertices)
	projectile.sample(0.0)
	var start_height: float = projectile._spike.position.y
	_expect(projectile._spike.visible and projectile._spike.scale.is_equal_approx(Vector3.ONE * projectile.crystal_scale), "Complete full-size crystal is visible from the start")
	projectile.sample(projectile.rise_seconds)
	_expect(projectile._spike.position.y > start_height + 0.4, "Intact crystal ascends before holding")
	var hold_position: Vector3 = projectile._spike.position
	projectile.sample(projectile.rise_seconds + projectile.hover_seconds * 0.9)
	_expect(projectile._spike.position.is_equal_approx(hold_position), "Complete crystal freezes before falling")
	for fragment in projectile._fragments:
		_expect(not fragment.visible, "Fracture pieces remain hidden before impact")
	var impact: float = projectile.impact_time()
	projectile.sample(impact - 0.001)
	_expect(projectile._spike.visible and projectile._spike.position.y < 0.02, "Intact crystal reaches the card before breaking")
	projectile.sample(impact)
	_expect(not projectile._spike.visible and projectile._fragments.size() == 64, "Impact keeps the sixty-four fitted shards")
	_expect(projectile._fragments[0].material_override.get_shader_parameter("show_interior") == true, "Impact reveals fracture interiors")
	var spread := 0.0
	projectile.sample(impact + 0.35)
	for fragment in projectile._fragments:
		_expect(fragment.visible and fragment.position.y >= 0.0, "Ice debris stays above impact plane")
		spread = maxf(spread, Vector2(fragment.position.x, fragment.position.z).length())
	_expect(spread > 0.30, "Ice fragments splatter beyond card edges")
	projectile.sample(projectile.duration())
	_expect(not projectile._spike.visible and not projectile._fragments[0].visible, "Ice presentation ends with no visible debris")
	projectile.play()
	projectile.reset()
	_expect(not projectile._playing and not projectile._spike.visible, "Ice replay can be cancelled cleanly")
	projectile.queue_free()

func _check_demo_browser() -> void:
	var entries: Array = preload("res://scripts/demo_catalog.gd").entries()
	var paths: Array = []
	for entry in entries:
		paths.append(entry.path)
		_expect(not "probe" in entry.path, "Demo browser excludes automated probes")
	_expect(paths.has("res://tools/ice_projectile_demo.tscn") and paths.has("res://CardShatterPreview.tscn"), "Demo browser finds tool demos and root previews")
	var menu = load("res://demo_menu.tscn").instantiate()
	add_child(menu)
	_expect(menu._rows.size() == entries.size(), "Every discovered demo gets a menu button")
	menu._filter("ice projectile")
	var visible_count := 0
	for button in menu._rows:
		if button.visible:
			visible_count += 1
	_expect(visible_count == 1, "Search narrows list to Ice Projectile")
	menu._filter("no such demo qqq")
	_expect(menu._empty.visible, "Empty searches show a clear message")
	menu.queue_free()
	var navigation = preload("res://scripts/demo_navigation.gd").new()
	add_child(navigation)
	_expect(navigation.process_mode == Node.PROCESS_MODE_ALWAYS, "Demo navigation remains usable while paused")
	navigation.queue_free()
