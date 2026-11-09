extends Node
## THE PASS BUTTON: only the player holding priority has one, and its label says what passing does.
## - "Next Phase": your turn, empty stack (you are done; the phase moves on once the opponent passes too).
## - "Pass": something on the stack, or the opponent's turn.

const GAME_SCENE := preload("res://game.tscn")

var _checks := 0
var _fails := 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	print("[PassButton] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _label(button) -> String:
	return str((button.get_node("ButtonTextViewport/Control/CenterContainer/Label") as Label).text)

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	for _i in range(4):
		await get_tree().process_frame
	var assistant = game.assistant
	var button = assistant.passPhaseButton
	var stack = game.stack
	GlobalVariables.refresh_mode()

	game.turn_owner = 1
	game.priority_holder = 1
	assistant.show_pass_priority_button()
	print("[PassButton] my turn, empty stack: visible=%s text=%s" % [button.visible, _label(button)])
	_expect(button.visible and _label(button) == "Next Phase", "my turn, empty stack, my priority: Next Phase")

	game.priority_holder = 2
	_expect(not button.visible, "the moment the opponent holds priority, I have no button")
	GlobalVariables.refresh_mode()
	assistant._on_player_mode_change(GlobalVariables.get_player_mode())
	_expect(not button.visible, "and a free moment on screen does not bring it back")

	var effect: Card = game.create_card(4, "player")
	stack.add_child(effect)
	stack.cards.append(effect)
	game.priority_holder = 1
	print("[PassButton] stack waiting: visible=%s text=%s" % [button.visible, _label(button)])
	_expect(button.visible and _label(button) == "Pass", "something on the stack: Pass")
	stack.cards.erase(effect)
	effect.queue_free()

	game.turn_owner = 2
	game.priority_holder = 1
	_expect(button.visible and _label(button) == "Pass", "the opponent's turn, empty stack: Pass (got %s)" % _label(button))

	game.match_over = true
	game.priority_holder = 1
	_expect(not button.visible, "no button once the match is over")

	print("[PassButton] %d checks | failures: %d" % [_checks, _fails])
	print("[PassButton] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
