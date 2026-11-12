extends Node
## POWER-UP viewing harness (card_power_fx.gd / power_up_burst.gd). Boots the real game on the clean board, puts
## Forwards on both sides, then buffs one of mine by +3000 every few seconds, so the look can be judged from the
## board camera. Run WINDOWED (never --headless).
##
## With `-- --shots <dir>` it saves a numbered frame sequence of the first power-up, cropped around the card, and
## quits: `godot --resolution 1280x720 res://tools/power_up_demo.tscn -- --shots C:/tmp/pu`

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const SHOT_TIMES := [0.0, 0.05, 0.10, 0.16, 0.25, 0.40, 0.55, 0.70, 0.82, 0.95, 1.10, 1.30, 1.50, 1.75, 2.05, 2.4]

var _shots_dir := ""


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at: int = args.find("--shots")
	if at >= 0 and at + 1 < args.size():
		_shots_dir = args[at + 1]
		DirAccess.make_dir_recursive_absolute(_shots_dir)
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = game.get("field")
	var mine: Array = []
	for id in [41, 1, 41]:
		var c: Card = game.create_card(id, "player")
		game.add_child(c)
		field.play_card(c, false, false)
		mine.append(c)
	for id in [41, 1]:
		var c: Card = game.create_card(id, "opponent")
		game.add_child(c)
		field.play_card(c, false, true)
	await get_tree().create_timer(1.5).timeout
	var subject: Card = mine[1]
	var n := 0
	while true:
		n += 1
		subject.add_power_modifier("demo:%d" % n, 3000)
		if not _shots_dir.is_empty():
			await _shoot(subject)
			get_tree().quit()
			return
		await get_tree().create_timer(3.5).timeout


func _shoot(card: Card) -> void:
	var start: int = Time.get_ticks_msec()
	var cam: Camera3D = get_viewport().get_camera_3d()
	for i in SHOT_TIMES.size():
		while (Time.get_ticks_msec() - start) / 1000.0 < float(SHOT_TIMES[i]):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var centre: Vector2 = cam.unproject_position(card.global_position)
		var half := Vector2i(int(img.get_width() * 0.16), int(img.get_height() * 0.30))
		var rect := Rect2i(Vector2i(centre) - half, half * 2).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(rect).save_png("%s/f%02d.png" % [_shots_dir, i])
		print("[PowerUpDemo] shot %d at %.2f s" % [i, (Time.get_ticks_msec() - start) / 1000.0])
