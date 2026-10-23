extends Node
## ARGATH probe — "your opponent discards 1 card" must hit the OTHER SEAT.
##
## It shipped inverted: a card controlled by P1 made P1 discard, and one controlled by P2 made P2 discard, so the
## human saw nothing and the AI quietly lost a card. The seat mapping is silent when wrong, which is why both
## directions are asserted here.
##
##   case 1  PLAYER-controlled Argath  -> the AI discards (fully resolved, hand -1)
##   case 2  OPPONENT-controlled Argath -> the LOCAL player is asked, i.e. the game enters CHOOSE_CARD_IN_HAND
##
## Case 2 is last because its branch waits for a human click that never comes headlessly.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Argath] ok   %s" % what)
	else:
		_fails += 1
		print("[Argath] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("ai")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	var field = _game.get("field")
	var stack = _game.get("stack")
	var ai_hand = _game.get("opponent_hand")
	var player_hand = _game.get("hand")

	# --- case 1: the PLAYER plays it, so the AI must discard ---------------------------------------------
	var mine: Card = _game.create_card(33, "player")
	_game.add_child(mine)
	field.play_card(mine, false, false)
	var ai_before: int = ai_hand.cards.size()
	field.execute_card_effect(mine, "when_enter_field")
	await get_tree().process_frame
	await stack.resolve_top_effect()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(ai_hand.cards.size() == ai_before - 1,
		"a PLAYER-controlled Argath makes the AI discard (AI hand %d -> %d)" % [ai_before, ai_hand.cards.size()])

	# --- case 2: the OPPONENT plays it, so the human is asked --------------------------------------------
	var theirs: Card = _game.create_card(33, "opponent")
	_game.add_child(theirs)
	field.play_card(theirs, true, false)
	var player_before: int = player_hand.cards.size()
	field.execute_card_effect(theirs, "when_enter_field")
	await get_tree().process_frame
	stack.resolve_top_effect()
	var asked: bool = false
	for _i in range(12):
		await get_tree().process_frame
		if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND:
			asked = true
			break
	_expect(asked, "an OPPONENT-controlled Argath asks the LOCAL player to discard (mode=%s)" % str(GlobalVariables.get_player_mode()))
	_expect(player_hand.cards.size() == player_before,
		"and holds there waiting for the pick, rather than discarding for them (%d cards)" % player_hand.cards.size())

	print("[Argath] %d checks | failures: %d" % [_checks, _fails])
	print("[Argath] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
