extends Node
## SUMMONING-SICKNESS WAVES viewing harness (sickness_overlay.gd). Boots the real game on the clean board with a few
## ready Forwards, then plays fresh Forwards on both sides so their waves appear, and loops: wake one (end of
## turn), give another Haste. Run WINDOWED (never --headless):
##   godot --resolution 1280x720 res://tools/sickness_demo.tscn
## With `-- --shots <dir>` it saves labelled frames (a run of zoomed frames 0.2 s apart, the board, wake, haste) and quits.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _shots_dir := ""
var _cam: Camera3D


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
	_cam = get_viewport().get_camera_3d()
	var field = game.get("field")
	for id in [1, 41]:   # ready, pre-placed: no waves
		var c: Card = game.create_card(id, "player")
		game.add_child(c)
		field.play_card(c, false, false)
	var opp: Card = game.create_card(50, "opponent")
	game.add_child(opp)
	field.play_card(opp, true, true, true)
	await get_tree().create_timer(0.5).timeout
	var squire: Card = _play(game, field, 25)
	var belt: Card = _play(game, field, 99)
	await Vfx.idle()
	if not _shots_dir.is_empty():
		await _wait(0.8)
		await _shot("0_board", null)
		for i in 12:
			await _shot("z%02d" % i, squire)
			await _wait(0.2)
		squire.turn_end()
		await _wait(0.3)
		await _shot("w_wake", squire)
		belt.add_status_effect("haste", 1)
		await _wait(0.12)
		await _shot("h_haste", belt)
		get_tree().quit()
		return
	while true:
		await get_tree().create_timer(4.0).timeout
		squire.turn_end()
		await get_tree().create_timer(1.5).timeout
		belt.add_status_effect("haste", 1)
		await get_tree().create_timer(2.5).timeout
		for card in [squire, belt]:
			game.call("break_card", card)
		await Vfx.idle()
		await get_tree().create_timer(0.5).timeout
		squire = _play(game, field, 25)
		belt = _play(game, field, 99)
		await Vfx.idle()


func _play(game: Node, field, id: int) -> Card:
	var c: Card = game.create_card(id, "player")
	game.add_child(c)
	field.play_card(c, false, true, true)
	return c


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## A full frame, or a zoom around one card.
func _shot(label: String, card: Card) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if card != null:
		var centre: Vector2 = _cam.unproject_position(card.global_position)
		var half := Vector2i(int(img.get_height() * 0.16), int(img.get_height() * 0.16))
		var rect := Rect2i(Vector2i(centre) - half, half * 2).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img = img.get_region(rect)
		img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_LANCZOS)
	img.save_png("%s/%s.png" % [_shots_dir, label])
	print("[SicknessDemo] %s" % label)
