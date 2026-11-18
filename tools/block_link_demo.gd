extends Node
## Viewing harness for the block link (scripts/vfx/block_link.gd): boots the debug board and links an opponent
## Forward (attacker) to one of ours (blocker). Shoot it with tools/shot.tscn --scene res://tools/block_link_demo.tscn
## --seconds 2 -- [--swap] [--player] --age=<s> (the link's age is frozen at <s>: draw 0.42 s, hold 0.45 s, vanish 0.55 s, pause 0.2 s per loop).

const GAME_SCENE := preload("res://scenes/game/game.tscn")

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().create_timer(1.0).timeout
	var field = game.field
	var theirs: Array = field.get_front_cards_for("opponent")
	var mine: Array = field.get_front_cards_for("player")
	if theirs.is_empty() or mine.is_empty():
		return
	# --swap: OUR Forward attacks and theirs blocks (the other seat's view of the same link).
	# --player: no blocker yet, so the link points at the defending player, off screen.
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var swap: bool = "--swap" in args
	field.attacker_card = mine[mini(1, mine.size() - 1)] if swap else theirs.front()
	if "--player" in args:
		field.show_attack_link()
	else:
		field.show_block_arc(theirs.front() if swap else mine[mini(1, mine.size() - 1)])
	# -- --age=<s>: freeze every link at that age (draw 0.42, hold 0.45, vanish 0.55, pause 0.2 s per loop).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--age="):
			for link in field.block_arrows:
				link.frozen_age = float(arg.substr(6))
