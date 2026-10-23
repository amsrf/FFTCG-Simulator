extends Node
## TURN HISTORY probe — the ledger conditions will read.
##
## Deliberately checks the WIRING, not just the data structure: that playing a Character records at the field, that
## casting a Summon records at the cast, that the setup board records NOTHING, and that "this turn" is a filter on
## turn_number rather than a deletion.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[History] ok   %s" % what)
	else:
		_fails += 1
		print("[History] FAIL %s" % what)


func _activities() -> Array:
	var out: Array = []
	for entry in _game.call("actions_this_turn"):
		out.append(str(entry.get("activity", "")))
	return out


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- the setup board is not history ---------------------------------------------------------------
	# The debug preset pre-places cards on both sides. None of that was "played", so the turn starts empty.
	print("[History] at start: %s" % str(_activities()))
	_expect(_activities().is_empty(), "pre-placed setup cards are NOT recorded as played")

	# --- a Character played onto the field ------------------------------------------------------------
	var field = _game.get("field")
	var forward: Card = _game.call("create_card", 41, "player")
	_game.add_child(forward)
	field.play_card(forward, false)          # record defaults to true
	await get_tree().process_frame
	var acts: Array = _activities()
	print("[History] after playing Squall: %s" % str(acts))
	_expect(acts.has("Forward Squall was played"), "playing a Forward records it by name and type")

	var entries: Array = _game.call("actions_this_turn")
	var actor: int = 0
	for e in entries:
		if str(e.get("activity", "")) == "Forward Squall was played":
			actor = int(e.get("actor", 0))
	_expect(actor == 1, "and the record says P1 did it (actor %d)" % actor)
	_expect(_game.call("played_this_turn", "Forward", 1), "played_this_turn(Forward, P1) is true")
	_expect(not _game.call("played_this_turn", "Backup", 1), "played_this_turn(Backup, P1) is false")

	# --- a Summon cast onto the stack -----------------------------------------------------------------
	var summon: Card = _game.call("create_card", 4, "player")     # Ifrit
	var stack = _game.get("stack")
	stack.add_child(summon)
	stack.set("casting_card", summon)
	stack.cast_card()
	await get_tree().process_frame
	_expect(_game.call("cast_this_turn", "Ifrit", 1), "casting a Summon records 'Casted Ifrit' for its caster")
	_expect(not _game.call("cast_this_turn", "Ifrit", 2), "and not for the opponent")
	_expect(not _game.call("cast_this_turn", "Shiva", 1), "a card that was not cast is not in the history")

	# --- "this turn" is a filter, not a deletion ------------------------------------------------------
	var turn_before: int = int(_game.get("turn_number"))
	var this_turn_actions: int = _activities().size()
	# Same statement next_phase() makes at the turn boundary.
	_game.set("turn_number", turn_before + 1)
	_expect(_activities().is_empty(), "the next turn starts empty")
	var all_turns: Dictionary = _game.get("turn_history")
	_expect(all_turns.has(turn_before) and (all_turns[turn_before] as Array).size() == this_turn_actions,
		"and the previous turn is still there, intact")
	_expect(not _game.call("cast_this_turn", "Ifrit", 1),
		"so 'cast this turn' stops being true once the turn ends")

	print("[History] %d checks | failures: %d" % [_checks, _fails])
	print("[History] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
