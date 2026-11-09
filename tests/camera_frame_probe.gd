extends Node
## Camera-framing scoreboard: where every zone lands on screen under the CURRENT camera.
##
## The migration away from orthographic needs a number, not an opinion. This prints the screen
## rectangle of each hand and board row, so a candidate camera can be judged against the targets:
##   * player hand band at the bottom edge,
##   * opponent hand band at the top edge,
##   * four board rows filling the middle 55-70%,
##   * no core row clipped left or right,
##   * nearly-square field cards.
##
## Run headless; it needs no rendering.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _cam: Camera3D = null

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	await get_tree().process_frame
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	_cam = get_viewport().get_camera_3d()
	if _cam == null:
		print("[Frame] no camera")
		get_tree().quit()
		return
	print("[Frame] projection=%s fov=%.1f pos=%s" % [
		"perspective" if _cam.projection == Camera3D.PROJECTION_PERSPECTIVE else "orthographic",
		_cam.fov, str(_cam.global_position)])
	var view: Vector2 = get_viewport().get_visible_rect().size
	print("[Frame] viewport %.0fx%.0f" % [view.x, view.y])

	# --stack-card=3,4,5: put real cards on the Stack and measure the fan. Without this the debug
	# board has an empty stack, so the stack presentation can only be judged by eye.
	var stack_ids: PackedStringArray = _stack_ids_from_args()
	if not stack_ids.is_empty():
		var stack_node: Node = game.get("stack")
		for id_text in stack_ids:
			var card = game.call("create_card", int(id_text), "player")
			if card != null:
				game.add_child(card)
				stack_node.call("add_card_to_tree", card)
				card.call("enter_zone", Card.Zone.STACK)
		stack_node.call("update_card_positions")
		await get_tree().create_timer(0.6).timeout
		_report_cards(stack_node.get("cards"), "stack cards")
		for card in stack_node.get("cards"):
			print("[Frame] stack card %-18s rot=%s world_scale=%.2f" % [
				card.card_name, str(card.rotation_degrees),
				card.global_transform.basis.get_scale().x])

	_report_hand(game, "Player/Hand", "player hand")
	_report_hand(game, "Opponent/Hand", "opponent hand")
	_report_row(game, "field", "front_cards", "player front")
	_report_row(game, "field", "back_cards", "player back")
	_report_row(game, "field", "opponent_front_cards", "opponent front")
	_report_row(game, "field", "opponent_back_cards", "opponent back")
	_report_node(game, "Player/Deck", "player deck")
	_report_node(game, "Player/Graveyard", "player grave")
	_report_node(game, "Opponent/Deck", "opponent deck")
	_report_node(game, "Opponent/Graveyard", "opponent grave")
	_report_node(game, "Player/DamageZone", "player damage")
	_report_node(game, "Opponent/DamageZone", "opponent damage")
	_report_node(game, "Stack", "stack")
	_report_node(game, "Assistant/ButtonRack", "button rack")
	_report_node(game, "Assistant/ButtonRack/ConfirmButton", "confirm button")
	print("[Frame] RESULT: measured")
	get_tree().quit()

func _stack_ids_from_args() -> PackedStringArray:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stack-card="):
			return arg.split("=", true, 1)[1].split(",", false)
	return PackedStringArray()

func _report_hand(game: Node, path: String, label: String) -> void:
	var hand: Node = game.get_node_or_null(path)
	if hand == null:
		print("[Frame] %-18s (missing)" % label)
		return
	var cards: Array = hand.get("cards")
	_report_cards(cards, label)

func _report_row(game: Node, owner_name: String, array_name: String, label: String) -> void:
	var holder: Variant = game.get(owner_name)
	if holder == null:
		print("[Frame] %-18s (missing field)" % label)
		return
	var cards: Array = holder.get(array_name)
	_report_cards(cards, label)

func _report_cards(cards: Array, label: String) -> void:
	if cards.is_empty():
		print("[Frame] %-18s (empty)" % label)
		return
	var box: Rect2 = _cards_rect(cards)
	var view: Vector2 = get_viewport().get_visible_rect().size
	print("[Frame] %-18s n=%2d  x %4.0f-%4.0f (%3.0f%%)  y %4.0f-%4.0f (%3.0f-%.0f%%)" % [
		label, cards.size(), box.position.x, box.end.x, 100.0 * box.size.x / view.x,
		box.position.y, box.end.y, 100.0 * box.position.y / view.y, 100.0 * box.end.y / view.y])

func _report_node(game: Node, path: String, label: String) -> void:
	var node: Node3D = game.get_node_or_null(path) as Node3D
	if node == null:
		print("[Frame] %-18s (missing)" % label)
		return
	var p: Vector2 = _cam.unproject_position(node.global_position)
	print("[Frame] %-18s centre at (%.0f, %.0f)  (%3.0f%%, %3.0f%%)" % [
		label, p.x, p.y, 100.0 * p.x / get_viewport().get_visible_rect().size.x,
		100.0 * p.y / get_viewport().get_visible_rect().size.y])

func _cards_rect(cards: Array) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for card in cards:
		var c: Card = card as Card
		if c == null:
			continue
		var half: Vector2 = c._card_face_size() * 0.5
		for corner in [Vector3(-half.x, 0.0, -half.y), Vector3(half.x, 0.0, -half.y),
				Vector3(-half.x, 0.0, half.y), Vector3(half.x, 0.0, half.y)]:
			var p: Vector2 = _cam.unproject_position(c.global_transform * corner)
			lo.x = minf(lo.x, p.x)
			lo.y = minf(lo.y, p.y)
			hi.x = maxf(hi.x, p.x)
			hi.y = maxf(hi.y, p.y)
	return Rect2(lo, hi - lo)
