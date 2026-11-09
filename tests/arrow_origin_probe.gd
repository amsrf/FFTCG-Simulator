extends Node
## The stack's arrow for the LOCAL player's Summon (its stack copy) starts where it is DRAWN: at the card's top edge,
## measured in screen pixels through the arrow's real transform. `-- --fan` adds three more cards; `-- --shot` saves a
## screenshot (needs a renderer: e.g. xvfb-run ... --rendering-driver opengl3).
const GAME_SCENE := preload("res://scenes/game/game.tscn")
var _game: Node

func _card(id: int, side: String) -> Card:
	var c: Card = _game.call("create_card", id, side)
	_game.add_child(c)
	return c

var _checks := 0
var _fails := 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	print("[Arrow] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	for _i in range(4):
		await get_tree().process_frame
	var field = _game.field
	var hand = _game.hand_for(1)
	var stack = _game.stack
	var assistant = _game.assistant
	_game.set("turn_owner", 1)
	_game.set("priority_holder", 1)
	GlobalVariables.refresh_mode()
	var squall := _card(41, "opponent")
	field.play_card(squall, true, false, false)
	var mage := _card(3, "player")
	field.play_card(mage, false, false, false)
	mage.untap()
	var ifrit := _card(4, "player")
	hand.add_card(ifrit)
	await get_tree().create_timer(0.3).timeout
	hand.charge(ifrit)
	await get_tree().process_frame
	field.add_card_to_mana_conversion(mage, "火")
	assistant.on_charge_complete()
	await get_tree().process_frame
	field.set_target_card(squall)
	await get_tree().process_frame
	if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET:
		assistant.on_target_complete()
	await get_tree().create_timer(3.0).timeout
	var top: Card = stack.displayed_card()
	var cam: Camera3D = get_viewport().get_camera_3d()
	var arrow = field.review_arrow
	_expect(top == stack.cards.back() and arrow != null and arrow.is_aiming, "the landed Summon shows its arrow")
	if top != null and arrow != null:
		# WHERE IT IS DRAWN: the ribbon's first point through the arrow's REAL transform, in screen pixels.
		var verts: PackedVector3Array = arrow.line.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var drawn: Vector2 = cam.unproject_position(arrow.line.global_transform * verts[0])
		var edge: Vector2 = cam.unproject_position(top.get_global_top_centre())
		var tip: Vector2 = cam.unproject_position(arrow.line.global_transform * verts[verts.size() - 1])
		print("[Arrow] drawn start %s | card top edge %s | gap %.1f px" % [drawn, edge, drawn.distance_to(edge)])
		_expect(drawn.distance_to(edge) < 12.0, "the arrow is DRAWN from the stack card's top edge (%.1f px)" % drawn.distance_to(edge))
		_expect(arrow.line.global_transform.is_equal_approx(Transform3D.IDENTITY), "arrows draw in world space, whatever the Field's transform")
	if "--fan" in OS.get_cmdline_user_args():
		for id in [12, 29, 9]:
			stack.create_card(id, "player", "when_enter_field", squall)
		stack.update_card_positions()
		await get_tree().create_timer(1.0).timeout
	# With a renderer (not --headless), `-- --shot` saves what it looks like to tools/probe_logs/arrow_origin.png.
	if "--shot" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var shot: Image = get_viewport().get_texture().get_image()
		if shot != null:
			shot.save_png(ProjectSettings.globalize_path("res://tools/probe_logs/arrow_origin.png"))
	print("[Arrow] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
