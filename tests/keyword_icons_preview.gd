extends Node3D
## Windowed preview for the keyword badges: three field Forwards with none, one and both keywords, one of them dull.
## Open it with F6 (it stays open), or shoot it with the shot harness and --as-scene 1.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const TEST_GROUNDS := preload("res://scripts/core/test_grounds.gd")


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

	var cards: Array[Card] = []
	for id in [1, 182, 182]:
		var card: Card = game.create_card(id, "player")
		game.add_child(card)
		game.field.play_card(card, false, false)
		cards.append(card)
	# Zoom on the three cards so the badges can be judged; F6 on this scene stays open.
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		var centre: Vector3 = (cards[0].global_position + cards[2].global_position) * 0.5
		# Keep the board camera's own orientation (a look_at from the wrong side turns the board upside down) and only
		# slide it along its view axis onto the cards.
		cam.global_position = centre + cam.global_transform.basis.z * 3.0
		if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
			cam.size = 1.6
	await get_tree().process_frame
	# Auron: no keyword. Cloud: prints Brave. Second Cloud: Brave + First Strike + cannot be
	# broken, and dull.
	cards[2].add_status_effect("first_strike", 1)
	cards[2].add_status_effect("unbreakable", 1)
	cards[2].tap()
