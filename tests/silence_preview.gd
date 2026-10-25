extends Node3D
## Windowed preview for the silence icon. The shot harness runs this with --as-scene 1 so the game's own
## environment and this camera are what the PNG shows.

const GAME_SCENE := preload("res://game.tscn")
const TEST_GROUNDS := preload("res://scripts/test_grounds.gd")


func _ready() -> void:
	await get_tree().process_frame
	MatchSetup.config = TEST_GROUNDS.config("clean")
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	game.player_agent = MockAgent.new()
	game.player_agent.bind(game)
	game.opponent_agent = MockAgent.new()
	game.opponent_agent.bind(game)
	await get_tree().process_frame

	var field = game.field
	var card: Card = game.create_card(182, "player")
	game.add_child(card)
	field.play_card(card, false, false)
	card.add_status_effect("abilities_nullified", 1)
	await get_tree().process_frame

	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		cam.global_position = card.global_position + Vector3(0.0, 2.6, 1.4)
		cam.look_at(card.global_position, Vector3.UP)
		if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
			cam.size = 1.1
