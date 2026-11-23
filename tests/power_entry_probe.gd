extends Node
## POWER ENTRY probe (~/Desktop/Clips/entry 43-72): a cost 5+ Character played through the real payment path lands
## with the burst in its element colour, the measured camera shake, and a tremor through its neighbours (nearest
## first, never a corner under the wood, all back at rest). A cost 4 card keeps the plain landing.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const BURST := preload("res://scripts/vfx/power_entry_burst.gd")
const HOLOGRAM := preload("res://scripts/cards/card_hologram.gd")

var _checks := 0
var _fails := 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[PowerEntry] ok   %s" % what)
	else:
		_fails += 1
		print("[PowerEntry] FAIL %s" % what)


func _bursts() -> Array:
	return get_tree().root.get_children().filter(
		func(n): return n.get_script() == BURST and not n.is_queued_for_deletion())


func _boot() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_hand": [25, 6],
		"player_field": [{"id": 37, "tapped": false}],
		"opponent_field": [{"id": 15, "tapped": false}, {"id": 2, "tapped": false}],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().create_timer(1.0).timeout


func _cast(card: Card) -> void:
	_game.get("hand").charge(card)
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	_game.get("assistant").on_charge_complete()


func _lowest_corner(card: Card) -> float:
	var mesh: Node3D = card.hand_mesh
	var low := INF
	for corner in [Vector3(-0.2145, 0, -0.3), Vector3(0.2145, 0, -0.3), Vector3(0.2145, 0, 0.3), Vector3(-0.2145, 0, 0.3)]:
		low = minf(low, (mesh.global_transform * corner).y)
	return low


func _ready() -> void:
	await _boot()
	var hand = _game.get("hand")
	var big: Card = hand.cards[1]
	big.cost = 9
	var field = _game.get("field")
	_expect(field.slam_tier(big) == 2, "setup: the cost 9 card is a slam tier 2")
	var neighbours: Array = field.get_all_cards()
	var rest_low: Dictionary = {}
	for n in neighbours:
		rest_low[n] = _lowest_corner(n)
	var camera: Camera3D = get_viewport().get_camera_3d()
	var home: Vector3 = camera.global_position

	await _cast(big)
	var burst = null
	for _i in range(600):
		var found: Array = _bursts()
		if not found.is_empty():
			burst = found[0]
			break
		await get_tree().process_frame
	_expect(burst != null, "a cost 9 card lands with the power entry burst")
	if burst == null:
		_finish()
		return
	_expect(big.hologram.phase == "fill", "at the moment of contact (phase %s)" % big.hologram.phase)
	var tint: Color = big.hologram.tint()
	_expect(burst.get("_tint").is_equal_approx(tint), "in the card's element colour (%s)" % tint)
	var shaken: Array = burst.get("shaken")
	_expect(shaken.size() == neighbours.size(), "the shockwave reaches every card on the field (%d of %d)" % [
		shaken.size(), neighbours.size()])
	var ordered := true
	for i in range(shaken.size()):
		for j in range(shaken.size()):
			var di: float = (shaken[i].card.global_position - big.global_position).length()
			var dj: float = (shaken[j].card.global_position - big.global_position).length()
			if di < dj - 0.01 and (float(shaken[i].delay) >= float(shaken[j].delay) or float(shaken[i].strength) < float(shaken[j].strength)):
				ordered = false
	_expect(ordered, "nearer cards feel it sooner and harder")

	# Watch the shake and the tremors to the end.
	var max_shift := 0.0
	var posed: Dictionary = {}
	# ON-SCREEN LIFT of the nearest card, the number to hold against the reference (~32 px at 1080p, ~0.2 card heights,
	# measured off ~/Desktop/Clips/entry 48-52): its face centre's screen position against where it rests.
	var nearest_card: Card = null
	for n in neighbours:
		if nearest_card == null or n.global_position.distance_to(big.global_position) \
				< nearest_card.global_position.distance_to(big.global_position):
			nearest_card = n
	var rest_screen: Vector2 = camera.unproject_position(nearest_card.hand_mesh.global_position)
	var rest_h: float = (camera.unproject_position(nearest_card.hand_mesh.global_transform * Vector3(0, 0, 0.3))
		- camera.unproject_position(nearest_card.hand_mesh.global_transform * Vector3(0, 0, -0.3))).length()
	var screen_lift := 0.0
	var trace: Array = []
	var peak_lift: Dictionary = {}
	var peak_tip: Dictionary = {}
	var sank := false
	var deepest := 0.0
	var worst_yaw := 0.0
	var air_from := -1.0
	var air_to := -1.0
	var air_trace: Array = []
	var peak_grow: Dictionary = {}
	var peak_corner_px: Dictionary = {}
	var rest_corners: Dictionary = {}
	for n in neighbours:
		var pts: Array = []
		for c in [Vector3(-0.2145, 0, -0.3), Vector3(0.2145, 0, -0.3), Vector3(0.2145, 0, 0.3), Vector3(-0.2145, 0, 0.3)]:
			pts.append(camera.unproject_position(n.hand_mesh.global_transform * c))
		rest_corners[n] = pts
	# By TIME, not frames (headless frames are fast): the shake, the shockwave delays and the longest jump all fit in 1.6 s.
	var watch_until: int = Time.get_ticks_msec() + 1600
	while Time.get_ticks_msec() < watch_until:
		max_shift = maxf(max_shift, camera.global_position.distance_to(home))
		if is_instance_valid(nearest_card):
			var now: Vector2 = camera.unproject_position(nearest_card.hand_mesh.global_position)
			var up_px: float = rest_screen.y - now.y
			trace.append(Vector2(Time.get_ticks_usec() / 1000000.0, up_px))
			screen_lift = maxf(screen_lift, up_px)
			var now_h: float = (camera.unproject_position(nearest_card.hand_mesh.global_transform * Vector3(0, 0, 0.3))
				- camera.unproject_position(nearest_card.hand_mesh.global_transform * Vector3(0, 0, -0.3))).length()
			var dist_now: float = camera.global_position.distance_to(nearest_card.hand_mesh.global_position)
			var dist_rest: float = camera.global_position.distance_to(nearest_card.global_position)
			peak_grow["toward"] = maxf(float(peak_grow.get("toward", 0.0)), dist_rest - dist_now)
		for n in neighbours:
			if not is_instance_valid(n):
				continue
			if not n.hand_mesh.transform.is_equal_approx(Transform3D.IDENTITY):
				posed[n] = true
			var lift: float = _lowest_corner(n) - float(rest_low[n])
			if n == nearest_card:
				air_trace.append(Vector2(Time.get_ticks_usec() / 1000000.0, lift))
			peak_lift[n] = maxf(float(peak_lift.get(n, 0.0)), lift)
			var tip: float = rad_to_deg(n.hand_mesh.global_basis.y.normalized().angle_to(Vector3.UP))
			# The SMALLEST screen rise of the four corners (each against its own rest pixel).
			var least := INF
			var corners := [Vector3(-0.2145, 0, -0.3), Vector3(0.2145, 0, -0.3), Vector3(0.2145, 0, 0.3), Vector3(-0.2145, 0, 0.3)]
			for ci in 4:
				var now_px: Vector2 = camera.unproject_position(n.hand_mesh.global_transform * corners[ci])
				least = minf(least, (rest_corners[n][ci] as Vector2).y - now_px.y)
			peak_corner_px[n] = maxf(float(peak_corner_px.get(n, 0.0)), least)
			# NO TURN IN THE BOARD PLANE: the pose relative to the card's rest is a pure tip about a HORIZONTAL axis.
			var delta: Quaternion = (n.hand_mesh.global_basis.orthonormalized() \
				* n.global_basis.orthonormalized().inverse()).get_rotation_quaternion()
			if delta.get_angle() > deg_to_rad(1.0):
				worst_yaw = maxf(worst_yaw, absf(delta.get_axis().normalized().y))
			peak_tip[n] = maxf(float(peak_tip.get(n, 0.0)), tip)
			deepest = maxf(deepest, float(rest_low[n]) - _lowest_corner(n))
			if _lowest_corner(n) < float(rest_low[n]) - 0.002:
				sank = true
		await get_tree().process_frame
	var viewport_h: float = get_viewport().get_visible_rect().size.y
	var depth: float = -(camera.global_transform.affine_inverse() * big.global_position).z
	var px: float = max_shift / (2.0 * depth * tan(deg_to_rad(camera.fov) * 0.5) / viewport_h) * (1080.0 / viewport_h)
	_expect(px > 12.0 and px < 30.0, "the camera shakes (~%.0f px at 1080p at its widest; reference ~20)" % px)
	_expect(camera.global_position.is_equal_approx(home), "and comes back exactly home")
	_expect(posed.size() == neighbours.size(), "every neighbour visibly jumps (%d of %d)" % [posed.size(), neighbours.size()])
	# SECONDS (headless frames are not 1/60 s): from first leaving rest (> 2% of its height) to 90% of its top, and how
	# long it stays above 0.1 card heights.
	var snap_seconds := 99.0
	var first := -1.0
	var above_from := -1.0
	var above_to := -1.0
	for sample in trace:
		if first < 0.0 and sample.y > rest_h * 0.02:
			first = sample.x
		if first >= 0.0 and snap_seconds > 90.0 and sample.y >= screen_lift * 0.9:
			snap_seconds = sample.x - first
		if sample.y > rest_h * 0.1:
			if above_from < 0.0:
				above_from = sample.x
			above_to = sample.x
	var scale_1080: float = 1080.0 / get_viewport().get_visible_rect().size.y
	print("[PowerEntry] nearest card on screen: rests %.0f px tall (1080p); rises at most %.1f px = %.2f card heights; up in %.3f s; %.2f s above 0.1 card heights" % [
		rest_h * scale_1080, screen_lift * scale_1080, screen_lift / maxf(rest_h, 1.0), snap_seconds, above_to - above_from])
	# Each card rolls its own size (+-15%), so the band is the reference's ~0.23 with that spread on top.
	_expect(screen_lift / maxf(rest_h, 1.0) >= 0.17 and screen_lift / maxf(rest_h, 1.0) <= 0.7,
		"ON SCREEN the nearest card rises well up the screen (>= 0.17 card heights): %.2f" % (screen_lift / maxf(rest_h, 1.0)))
	_expect(snap_seconds <= 0.08, "and is THROWN up: %.3f s from leaving the wood to its top (fast, but a few frames)" % snap_seconds)
	# The user: ~0.1 s in the air was "too fast", ~0.57 s "too slow".
	var top_lift := 0.0
	for sample in air_trace:
		top_lift = maxf(top_lift, sample.y)
	for sample in air_trace:
		if sample.y > top_lift * 0.1:
			if air_from < 0.0:
				air_from = sample.x
			air_to = sample.x
	# Air time = the lowest corner more than 10% of its top height off the wood (the jump is along the line of sight now, so the
	# screen position barely says when it is up). The two rejected versions: ~0.2 s too fast, ~0.65 s too slow.
	_expect(air_to - air_from >= 0.28 and air_to - air_from <= 0.5,
		"and hangs between the two rejected timings: %.2f s off the wood (~0.2 too fast, ~0.65 too slow)" \
		% (air_to - air_from))
	_expect(worst_yaw < 0.02, "no neighbour turns in the board plane: it only tips (worst vertical axis share %.3f)" % worst_yaw)
	# EVERY corner leaves its rest spot ON SCREEN: a big tip with a jump along the line of sight kept one edge on the
	# same pixels, so the card read as leaning on that edge (the user: "the card never left the ground").
	for n in neighbours:
		_expect(float(peak_corner_px.get(n, 0.0)) >= 12.0,
			"%s: even its lowest-moving corner rises %.0f px on screen (1080p) - the whole card leaves the ground" % [
				n.card_name if "card_name" in n else str(n), float(peak_corner_px.get(n, 0.0)) * 1080.0 / viewport_h])
	var nearest: Card = null
	for n in neighbours:
		if nearest == null or n.global_position.distance_to(big.global_position) < nearest.global_position.distance_to(big.global_position):
			nearest = n
	_expect(float(peak_lift.get(nearest, 0.0)) > 0.04 and float(peak_tip.get(nearest, 0.0)) > 8.0,
		"the nearest card is LAUNCHED: it leaves the wood (%.3f m, lowest corner) tipped %.0f degrees" % [
			float(peak_lift.get(nearest, 0.0)), float(peak_tip.get(nearest, 0.0))])
	var rolls: Array = []
	for n in neighbours:
		rolls.append(n.damage_fx.hop_params)
	var alike := false
	for i in range(rolls.size()):
		for j in range(i + 1, rolls.size()):
			if absf(float(rolls[i].get("tilt", 0.0)) - float(rolls[j].get("tilt", 0.0))) < 0.01 \
					and absf(float(rolls[i].get("wobble", 0.0)) - float(rolls[j].get("wobble", 0.0))) < 0.01:
				alike = true
	_expect(not alike, "no two neighbours jump alike (each rolls its own tip direction and tip)")
	_expect(not sank, "no neighbour ever puts a corner under the wood (deepest %.4f m below rest)" % deepest)
	var all_rest := true
	for n in neighbours:
		if is_instance_valid(n) and not n.hand_mesh.transform.is_equal_approx(Transform3D.IDENTITY):
			all_rest = false
	_expect(all_rest, "and all of them are back at rest")
	_expect(_bursts().is_empty(), "the burst frees itself")

	# THE JUMPER'S COST: the same blow throws a cheap card higher than a heavy one.
	var jumper: Card = neighbours[0]
	var saved_cost = jumper.cost
	var heights: Array = []
	for c in [1, 8]:
		var low := INF
		var high := 0.0
		for _k in range(6):
			jumper.cost = c
			jumper.damage_fx.normalize()
			jumper.damage_fx.play_tremor(jumper.global_position + Vector3.RIGHT, 1.0, 0.0)
			var h: float = float(jumper.damage_fx.hop_params.get("height_m", 0.0))
			low = minf(low, h)
			high = maxf(high, h)
		jumper.damage_fx.normalize()
		heights.append(Vector2(low, high))
	jumper.cost = saved_cost
	_expect(heights[0].x > heights[1].y,
		"a cost 1 card jumps higher than a cost 8 one (%.2f-%.2f m vs %.2f-%.2f m)" % [
			heights[0].x, heights[0].y, heights[1].x, heights[1].y])

	# A cost 4 card: the plain landing, no burst.
	_game.queue_free()
	await get_tree().process_frame
	await _boot()
	var small: Card = _game.get("hand").cards[0]
	small.cost = 4
	_expect(_game.get("field").slam_tier(small) == 0, "setup: a cost 4 card is a slam tier 0")
	await _cast(small)
	var any := false
	for _i in range(240):
		if not _bursts().is_empty():
			any = true
		await get_tree().process_frame
	_expect(not any and small.is_drawn_on_field(), "a cost 4 card lands without the power entry")
	_finish()


func _finish() -> void:
	print("[PowerEntry] %d checks | failures: %d" % [_checks, _fails])
	print("[PowerEntry] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
