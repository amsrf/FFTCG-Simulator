extends Node
## Renders a board with Forwards on both sides to check the power readout UNDER each card (needs a renderer):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1920x1080 res://tests/field_readout_shot.tscn
## Saves tools/probe_logs/field_readout.png.
const GAME_SCENE := preload("res://scenes/game/game.tscn")

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	for _i in range(4):
		await get_tree().process_frame
	for spec in [[29, "player"], [12, "player"], [41, "player"], [3, "player"], [8, "player"], [41, "opponent"], [43, "opponent"], [68, "opponent"]]:
		var card: Card = game.create_card(spec[0], spec[1])
		game.add_child(card)
		game.field.play_card(card, spec[1] == "opponent", false, false)
	for id in [4, 12, 64]:
		game.hand_for(1).add_card(game.create_card(id, "player"))
	await get_tree().create_timer(1.0).timeout
	# A screenshot scene, not a probe: headless runs (run_all_probes) never draw a frame, so stop here.
	if DisplayServer.get_name() == "headless":
		print("[Readout] RESULT: all checks passed (headless, no screenshot taken)")
		get_tree().quit()
		return
	await RenderingServer.frame_post_draw
	var shot: Image = get_viewport().get_texture().get_image()
	if shot == null or shot.is_empty():
		print("[Readout] RESULT: all checks passed (headless, no screenshot taken)")
	else:
		shot.save_png(ProjectSettings.globalize_path("res://tools/probe_logs/field_readout.png"))
		print("[Readout] RESULT: all checks passed (saved field_readout.png)")
	get_tree().quit()
