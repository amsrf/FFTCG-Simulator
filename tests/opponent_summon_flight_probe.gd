extends Node
## Measures the OPPONENT SUMMON FLIGHT: where the card starts, where it passes, and where it
## lands, in screen percentages. This is the objective version of "does it leave from the middle
## of the hand, reach the screen centre, and finish at the stack?".

const GAME_SCENE := preload("res://game.tscn")

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	await get_tree().process_frame
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var hand: Node = game.get_node("Opponent/Hand")
	var card: Card = game.call("create_card", 62, "opponent")
	hand.call("add_card", card)
	await get_tree().create_timer(0.2).timeout

	var cam: Camera3D = get_viewport().get_camera_3d()
	var view: Vector2 = get_viewport().get_visible_rect().size
	var mid: Vector3 = hand.global_transform * hand.call("calculate_card_position", hand.cards.size() / 2)
	print("[OppSummon] hand middle world=%s screen=%s" % [str(mid), str(_screen(cam, view, mid))])

	var started: bool = bool(hand.call("charge", card))
	print("[OppSummon] charge=%s type=%s controller=%s" % [str(started), card.type, card.controller])
	await get_tree().process_frame
	_report(cam, view, card, 0.0)
	var t0: int = Time.get_ticks_msec()
	var next_report: float = 0.10
	var min_height: float = 1e9
	var min_line: String = ""
	while true:
		await get_tree().process_frame
		var elapsed: float = float(Time.get_ticks_msec() - t0) / 1000.0
		if elapsed >= next_report:
			var h: float = _report(cam, view, card, elapsed)
			if h < min_height:
				min_height = h
				min_line = "t=%.2f proj_height=%.0f" % [elapsed, h]
			next_report += 0.10
		if elapsed >= 1.25:
			break
	print("[OppSummon] THINNEST at %s" % min_line)
	var stack: Stack = game.get("stack")
	if card != null and is_instance_valid(card) and stack != null:
		var expected_pos: Vector3 = stack.to_global(stack.calculate_card_position(card.index))
		var expected_basis: Basis = (stack.global_transform.basis.orthonormalized() * stack.call("_stack_card_local_basis", card)).orthonormalized()
		var pos_err: float = card.global_position.distance_to(expected_pos)
		var rot_err: float = rad_to_deg(card.global_transform.basis.orthonormalized().get_rotation_quaternion().angle_to(expected_basis.get_rotation_quaternion()))
		print("[OppSummon] FINAL pos_err=%.5f rot_err=%.3f deg world_scale=%.3f revealed=%s" % [
			pos_err, rot_err, card.global_transform.basis.get_scale().x, str(card.revealed)])
	print("[OppSummon] RESULT: measured")
	get_tree().quit()

func _report(cam: Camera3D, view: Vector2, card: Card, t: float) -> float:
	if card == null or not is_instance_valid(card):
		print("[OppSummon] t=%.2f card invalid" % t)
		return 0.0
	var p: Vector2 = _screen(cam, view, card.global_position)
	var hw: float = 0.2055
	var hh: float = 0.2975
	var pts: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			pts.append(cam.unproject_position(card.to_global(Vector3(sx * hw, 0.0, sy * hh))))
	var minx: float = pts[0].x
	var maxx: float = pts[0].x
	var miny: float = pts[0].y
	var maxy: float = pts[0].y
	for q in pts:
		minx = minf(minx, q.x)
		maxx = maxf(maxx, q.x)
		miny = minf(miny, q.y)
		maxy = maxf(maxy, q.y)
	var view_dir: Vector3 = -cam.global_transform.basis.z.normalized()
	var normal: Vector3 = card.global_transform.basis.y.normalized()
	print("[OppSummon] t=%.2f screen=%5.1f,%5.1f (%3.0f%%, %3.0f%%) scale=%.2f rot=%s proj=%.0fx%.0f n·v=%.2f rev=%s" % [
		t, p.x, p.y, 100.0 * p.x / view.x, 100.0 * p.y / view.y,
		card.global_transform.basis.get_scale().x, str(card.rotation_degrees),
		maxx - minx, maxy - miny, normal.dot(view_dir), str(card.revealed)])
	return maxy - miny

func _screen(cam: Camera3D, view: Vector2, world: Vector3) -> Vector2:
	return cam.unproject_position(world)
