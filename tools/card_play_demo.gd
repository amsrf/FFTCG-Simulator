extends Node
## Viewing harness for how a Character is played (card_hologram.gd). Boots a board with a few Forwards already down,
## casts one from hand through the real payment path and saves every 2nd frame (1/30 s of game time) to --out-dir.
## Run windowed with --fixed-fps 60, so every frame is exactly 1/60 s however long the PNG takes to write:
##   godot --resolution 1920x1080 --fixed-fps 60 res://tools/card_play_demo.tscn -- --out-dir <dir> [--big] [--every N] [--frames N]
## --big raises the card's cost to 9 (slam tier 2: the camera jolt).

const GAME_SCENE := preload("res://scenes/game/game.tscn")

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := "user://card_play"
	for i in args.size():
		if args[i] == "--out-dir" and i + 1 < args.size():
			out_dir = args[i + 1]
	var big := args.has("--big")
	# --frames N: how many frames to run after the payment (default 120 = 2 s; the neighbours' jump needs ~200).
	var frames := 120
	for i in args.size():
		if args[i] == "--frames" and i + 1 < args.size():
			frames = maxi(int(args[i + 1]), 1)
	var every := 2
	for i in args.size():
		if args[i] == "--every" and i + 1 < args.size():
			every = maxi(int(args[i + 1]), 1)
	# --ground <name>: boot a test ground instead (e.g. power_entries) and play the first card in hand.
	var ground := ""
	for i in args.size():
		if args[i] == "--ground" and i + 1 < args.size():
			ground = args[i + 1]
	if ground != "":
		MatchSetup.config = preload("res://scripts/core/test_grounds.gd").config(ground)
	else:
		MatchSetup.config = MatchSetup.build_config("clean", {
			"player_hand": [25, 6],
			"player_field": [{"id": 37, "tapped": false}],
			"opponent_field": [{"id": 15, "tapped": false}, {"id": 2, "tapped": false}],
			"player_deck": range(101, 131),
			"opponent_deck": range(141, 171),
		})
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().create_timer(1.5).timeout
	var hand = game.get("hand")
	var card: Card = hand.cards[1] if big and ground == "" else hand.cards[0]
	if big:
		card.cost = 9
	hand.charge(card)
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	game.get("assistant").on_charge_complete()
	for frame in frames:
		await RenderingServer.frame_post_draw
		if frame % every == 0:
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/f_%03d.png" % [out_dir, frame])
	get_tree().quit()
