extends Node
## Viewing harness for the opponent's discard reveal (Graveyard._reveal_face_down): boots the ai board and has the
## opponent discard one card after 1 s. Shoot with tools/shot.tscn --scene res://tools/discard_reveal_demo.tscn
## --as-scene 1 --seconds <t>; t ~1.4 catches the card held face-up.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("ai")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().create_timer(1.0).timeout
	# -- --count=<n>: how many cards the opponent discards (default 1).
	var count := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			count = int(arg.substr(8))
	game.discard_from(2, count)
