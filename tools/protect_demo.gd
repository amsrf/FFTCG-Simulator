extends Node
## PROTECT SHELL viewing harness (protect_shell_cue.gd / protect_shell.gd). Boots the real game on the clean board with
## Forwards on both sides, then gives one of mine "cannot be broken" every few seconds, so the shell can be judged from
## the board camera. Run WINDOWED (never --headless):
##   godot --resolution 1280x720 res://tools/protect_demo.tscn
## With `-- --shots <dir>` it FREEZES the first shell at each of SHOT_TIMES (sample(t) is deterministic), saves a
## cropped frame of each, and quits.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const SHOT_TIMES := [0.08, 0.20, 0.30, 0.40, 0.50, 0.62, 0.75, 0.95, 1.15, 1.30, 1.45, 1.57]

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
	for id in [41, 1, 3]:
		var c: Card = game.create_card(id, "player")
		game.add_child(c)
		field.play_card(c, false, false)
		mine.append(c)
	for id in [41, 1]:
		var c: Card = game.create_card(id, "opponent")
		game.add_child(c)
		field.play_card(c, true, false)
	await get_tree().create_timer(1.5).timeout
	var subject: Card = mine[1]
	while true:
		subject.add_status_effect("unbreakable", 1)
		if not _shots_dir.is_empty():
			await _shoot(subject)
			get_tree().quit()
			return
		await get_tree().create_timer(2.5).timeout
		subject.status_effects.erase("unbreakable")
		subject.refresh_status_visuals()
		await get_tree().create_timer(0.5).timeout


func _shoot(card: Card) -> void:
	await get_tree().process_frame
	var shell: Node3D = null
	for child in get_tree().root.get_children():
		if child.name.begins_with("ProtectShell"):
			shell = child
	if shell == null:
		push_error("no ProtectShell appeared")
		return
	shell.set_process(false)
	var cam: Camera3D = get_viewport().get_camera_3d()
	for i in SHOT_TIMES.size():
		shell.call("sample", float(SHOT_TIMES[i]))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var centre: Vector2 = cam.unproject_position(card.global_position)
		var half := Vector2i(int(img.get_height() * 0.13), int(img.get_height() * 0.16))
		var rect := Rect2i(Vector2i(centre) - half, half * 2).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(rect).save_png("%s/f%02d.png" % [_shots_dir, i])
		print("[ProtectDemo] shot %d at t=%.2f s" % [i, SHOT_TIMES[i]])
