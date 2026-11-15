extends Node
## Viewing harness for the PITS (scripts/game/pit.gd) and the pit intake (Graveyard._swallow): boots the real game on
## the `debug` preset, waits for the board to settle, then discards the first card of the player's hand into the
## Break Zone pit (or, with --removed, receives it into the Removed pit; with --mill, mills the top of the deck).
##   Space  discard another card     M  mill one     R  remove one from hand to the Removed pit
##   --break: break the opponent's first Forward instead (it shatters, then rests hidden in their pit)
## Screenshots: tools/shot.tscn ... -- --scene res://tools/pit_demo.tscn --as-scene 1 --seconds <t> --freeze=<s>
## where <s> is the time AFTER the discard starts to freeze at. Or --shots=0.2,0.5,0.8 --shot-dir=<abs dir>: save a PNG
## of the viewport at each of those times after the discard (real time, so a frame or so late), for a contact sheet.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const SETTLE_SECONDS := 1.5

var _game: Node = null
var _shots: Array = []
var _shot_dir := "user://"

func _ready() -> void:
	MatchSetup.config = MatchSetup.resolve_config()
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	var freeze := -1.0
	var mode := "discard"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--freeze="):
			freeze = argument.trim_prefix("--freeze=").to_float()
		elif argument == "--mill":
			mode = "mill"
		elif argument == "--removed":
			mode = "removed"
		elif argument == "--break":
			mode = "break"
		elif argument == "--click-pit":
			mode = "click"
		elif argument.begins_with("--shots="):
			for part in argument.trim_prefix("--shots=").split(","):
				_shots.append(part.to_float())
		elif argument.begins_with("--shot-dir="):
			_shot_dir = argument.trim_prefix("--shot-dir=")
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	_act(mode)
	if not _shots.is_empty():
		var began: int = Time.get_ticks_msec()
		for at in _shots:
			while (Time.get_ticks_msec() - began) / 1000.0 < at:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path := "%s/pit_%04d.png" % [_shot_dir, int(at * 1000.0)]
			get_viewport().get_texture().get_image().save_png(path)
			print("[PitDemo] shot %.2f s -> %s" % [at, path])
	if freeze >= 0.0:
		await get_tree().create_timer(freeze).timeout
		Engine.time_scale = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: _act("discard")
			KEY_M: _act("mill")
			KEY_R: _act("removed")

func _act(mode: String) -> void:
	var hand = _game.get_node("Player/Hand")
	match mode:
		"mill":
			_game.call("mill_player", 1, 1)
		"break":
			_game.call("_debug_break_first_forward", true)
		"click":
			_click_pit()
		"removed":
			if hand.cards.is_empty():
				return
			var card: Card = hand.cards[0]
			hand.cards.erase(card)
			hand.update_card_positions()
			_game.get_node("Player/Removed").receive(card)
		_:
			if hand.cards.is_empty():
				return
			hand.discard_card(hand.cards[0])


## A REAL click on the Break Zone pit: a mouse move and press pushed through the viewport at the pit's screen position,
## so it goes through 3D picking exactly as a player's click does. Prints whether the zone window opened.
func _click_pit() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var pit: Node3D = _game.get_node("Player/Graveyard").get("pit")
	var at: Vector2 = cam.unproject_position(pit.global_position + Vector3.UP * 0.08)
	var before: int = _game.get_child_count()
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	get_viewport().push_input(move)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		get_viewport().push_input(click)
		await get_tree().physics_frame
		await get_tree().physics_frame
	await get_tree().process_frame
	print("[PitDemo] clicked the pit at %s: zone window %s" % [str(at),
		"OPENED" if _game.get_child_count() > before else "did NOT open"])
