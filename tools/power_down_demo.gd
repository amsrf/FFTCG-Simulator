extends Node
## POWER-DOWN viewing harness (card_power_fx.gd / power_down_drain.gd / drain_death_cue.gd). Boots the real game on the
## clean board with Forwards on both sides, then alternates: drain one of mine by -3000, restore it, and every third
## round drain a 3000 Forward to 0 (the lethal form: drain, cyan cracks, shatter). Run WINDOWED (never --headless).
##
## With `-- --shots <dir>` it saves a numbered frame sequence of one drain and then one lethal drain, cropped around
## the card, and quits: `godot --resolution 1280x720 res://tools/power_down_demo.tscn -- --shots /tmp/pd`

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const SHOT_TIMES := [0.05, 0.15, 0.24, 0.31, 0.37, 0.42, 0.50, 0.60, 0.70, 0.80, 0.90, 1.05]
const LETHAL_TIMES := [1.9, 2.05, 2.15, 2.25, 2.35, 2.45, 2.55, 2.65, 2.75, 2.85, 2.95, 3.1]

var _shots_dir := ""
var _game: Node
var _field


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at: int = args.find("--shots")
	if at >= 0 and at + 1 < args.size():
		_shots_dir = args[at + 1]
		DirAccess.make_dir_recursive_absolute(_shots_dir)
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	var mine: Array = []
	for id in [41, 1, 41]:
		mine.append(_play(id, "player", false))
	for id in [41, 1]:
		_play(id, "opponent", true)
	await get_tree().create_timer(1.5).timeout
	var subject: Card = mine[1]
	if not _shots_dir.is_empty():
		subject.add_power_modifier("demo", -3000)
		await _shoot(subject, SHOT_TIMES, "d")
		var victim: Card = mine[0]
		var where: Vector3 = victim.global_position
		victim.add_power_modifier("demo:lethal", -int(victim.power))
		_game.enforce_game_state_rules()
		await _shoot_at(where, LETHAL_TIMES, "l")
		get_tree().quit()
		return
	var n := 0
	while true:
		n += 1
		subject.add_power_modifier("demo", -3000)
		await get_tree().create_timer(2.5).timeout
		subject.remove_power_modifier("demo")
		await get_tree().create_timer(1.0).timeout
		if n % 3 == 0:
			var victim: Card = _play(41, "player", false)
			victim.set_base_power(3000)
			await get_tree().create_timer(1.0).timeout
			victim.add_power_modifier("demo:lethal", -3000)
			_game.enforce_game_state_rules()
			await get_tree().create_timer(3.0).timeout


func _play(id: int, controller: String, opponent: bool) -> Card:
	var c: Card = _game.create_card(id, controller)
	_game.add_child(c)
	_field.play_card(c, false, opponent)
	return c


func _shoot(card: Card, times: Array, tag: String) -> void:
	await _shoot_at(card.global_position, times, tag)


func _shoot_at(where: Vector3, times: Array, tag: String) -> void:
	var start: int = Time.get_ticks_msec()
	var cam: Camera3D = get_viewport().get_camera_3d()
	for i in times.size():
		while (Time.get_ticks_msec() - start) / 1000.0 < float(times[i]):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var centre: Vector2 = cam.unproject_position(where)
		var half := Vector2i(int(img.get_width() * 0.07), int(img.get_height() * 0.17))
		var rect := Rect2i(Vector2i(centre) - half, half * 2).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(rect).save_png("%s/%s%02d.png" % [_shots_dir, tag, i])
		print("[PowerDownDemo] shot %s%d at %.2f s" % [tag, i, (Time.get_ticks_msec() - start) / 1000.0])
