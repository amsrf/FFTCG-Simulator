extends Node
## The EX BURST reveal in the REAL game, through the real damage camera: boots game.tscn (debug preset), puts an EX
## BURST card (101) on top of a deck and deals 1 damage. For screenshots:
##   tools/shot.tscn ... -- --scene res://tools/ex_burst_ingame.tscn --as-scene 1 --freeze=<s after the hit> --frames 900
## (--side=opponent for the opponent's damage zone; --card=<id> for another EX BURST card, e.g. 4 Ifrit for an arrow).

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const EX_CARD := 101

func _ready() -> void:
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	var freeze := -1.0
	var side := "player"
	var card_id := EX_CARD
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--freeze="):
			freeze = argument.trim_prefix("--freeze=").to_float()
		elif argument.begins_with("--card="):
			card_id = argument.trim_prefix("--card=").to_int()
		elif argument.begins_with("--side="):
			side = argument.trim_prefix("--side=")
	await get_tree().create_timer(1.0).timeout
	var card: Card = game.call("create_card", card_id, side)
	game.add_child(card)
	var target_side: PlayerSide = game.get("player") if side == "player" else game.get("opponent")
	target_side.deck.deck_cards.push_front(card)
	target_side.take_damage(1)
	if freeze >= 0.0:
		await get_tree().create_timer(freeze).timeout
		Engine.time_scale = 0.0

func _exit_tree() -> void:
	Engine.time_scale = 1.0
