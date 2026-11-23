extends Node
## TURN RULES probe — two basic rules that boards and agents rely on:
##   * 5.2.3.1.1.3  a Backup ENTERS THE FIELD DULL (a Forward does not; a setup board stays active);
##   * 9.5.1.2      in the End Phase the TURN PLAYER discards down to five cards — chosen by the owner (the AI takes
##                  its cheapest), mandatory (an agent that answers nothing still loses the excess), the other
##                  player keeps a big hand, and a hand already at five is untouched.

const GAME_SCENE := preload("res://scenes/game/game.tscn")
const AGENT := preload("res://scripts/agents/agent.gd")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[TurnRules] ok   %s" % what)
	else:
		_fails += 1
		print("[TurnRules] FAIL %s" % what)

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("ai")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = _game.get("field")

	# --- Backups enter dull -------------------------------------------------------------------------------------
	var backup: Card = _game.create_card(188, "player")    # Zangan, Backup
	_game.add_child(backup)
	field.play_card(backup, false, true)
	_expect(backup.tapped, "a played Backup enters the field dull")
	var forward: Card = _game.create_card(189, "player")   # Tifa, Forward
	_game.add_child(forward)
	field.play_card(forward, false, true)
	_expect(not forward.tapped, "a played Forward enters active")
	var setup: Card = _game.create_card(206, "player")     # Biggs, Backup, placed by the setup path
	_game.add_child(setup)
	field.play_card(setup, false, false)
	_expect(not setup.tapped, "a setup-board Backup (not played) stays active")
	await Vfx.idle()
	_expect(is_equal_approx(backup.rotation_degrees.y, backup._upright_y + backup.tap_angle),
		"the dull Backup is drawn tilted once it has landed (%.1f vs upright %.1f)" % [
			backup.rotation_degrees.y, backup._upright_y])

	# --- Hand limit ---------------------------------------------------------------------------------------------
	var ai_hand: Hand = _game.hand_for(2)
	_fill(ai_hand, 2, 8)
	var top_five: Array = _costs(ai_hand.cards).slice(0, 5)
	await _game.enforce_hand_limit(2)
	_expect(ai_hand.cards.size() == 5, "the AI turn player discards down to five (%d)" % ai_hand.cards.size())
	_expect(_costs(ai_hand.cards) == top_five, "the AI chose its own discards (it keeps its five dearest: %s)" % str(top_five))

	await _game.enforce_hand_limit(2)
	_expect(ai_hand.cards.size() == 5, "a hand of exactly five is left alone")

	# An agent with no opinion (base Agent returns null) still loses the excess: the limit is mandatory.
	var silent = AGENT.new()
	silent.bind(_game)
	var original = _game.opponent_agent
	_game.opponent_agent = silent
	_fill(ai_hand, 2, 7)
	await _game.enforce_hand_limit(2)
	_expect(ai_hand.cards.size() == 5, "a silent agent still discards down to five (%d)" % ai_hand.cards.size())
	_game.opponent_agent = original

	# Only the TURN player: run a real End Phase for P2 and check P1 keeps a big hand.
	var my_hand: Hand = _game.hand_for(1)
	_fill(my_hand, 1, 7)
	_fill(ai_hand, 2, 7)
	var mine_before: int = my_hand.cards.size()
	_game.turn_owner = 2
	await _game.enforce_hand_limit(_game.turn_owner)
	_expect(my_hand.cards.size() == mine_before, "the non-turn player keeps all %d cards (%d)" % [mine_before, my_hand.cards.size()])
	_expect(ai_hand.cards.size() == 5, "the turn player is down to five")

	print("[TurnRules] RESULT: %s (%d checks, %d failed)" % ["all checks passed" if _fails == 0 else "FAILED", _checks, _fails])
	get_tree().quit()

func _fill(hand: Hand, player_id: int, target: int) -> void:
	var ids := [4, 10, 187, 190, 120, 106, 205, 92, 24, 14]
	var i := 0
	while hand.cards.size() < target:
		var c: Card = _game.create_card(ids[i % ids.size()], "player" if player_id == 1 else "opponent")
		hand.add_card(c)
		i += 1

## Costs, dearest first.
func _costs(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(int(c.cost))
	out.sort()
	out.reverse()
	return out
