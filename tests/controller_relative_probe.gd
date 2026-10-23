extends Node
## WHO IS "THE OPPONENT"? probe.
##
## A card that says "choose 1 Forward opponent controls" means the opponent OF ITS CONTROLLER, not a fixed seat. The
## bug this covers: the AI cast Snow's "dull an opponent's Forward" and dulled its own, because "opponent" was being
## compared literally against the P2 side name instead of being resolved relative to the source.

const GAME_SCENE := preload("res://game.tscn")

const PLAYER_FORWARD := 41   # Squall, 氷
const AI_FORWARD := 43       # Snow,   氷

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Who] ok   %s" % what)
	else:
		_fails += 1
		print("[Who] FAIL %s" % what)


func _on_field(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	card.untap()
	return card


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	var mine: Card = _on_field(PLAYER_FORWARD, "player")
	var theirs: Card = _on_field(AI_FORWARD, "opponent")
	var criteria: Dictionary = {"is_type": "Forward", "controller": "opponent"}

	# --- a HUMAN source: "opponent" is the AI side --------------------------------------------------------
	_field.set_viable_targets(criteria, mine, "Ability")
	print("[Who] human caster -> mine valid=%s, theirs valid=%s" % [mine.is_valid_target, theirs.is_valid_target])
	_expect(not mine.is_valid_target, "a human's \"opponent\" target is NOT their own Forward")
	_expect(theirs.is_valid_target, "it is the AI's Forward")

	# --- an AI source: "opponent" is the HUMAN side --------------------------------------------------------
	_field.set_viable_targets(criteria, theirs, "Ability")
	print("[Who] AI caster -> mine valid=%s, theirs valid=%s" % [mine.is_valid_target, theirs.is_valid_target])
	_expect(mine.is_valid_target, "an AI's \"opponent\" target IS the human's Forward")
	_expect(not theirs.is_valid_target, "and NOT the AI's own Forward — this was the bug")

	# --- no source keeps the literal meaning, for snapshots and probes --------------------------------------
	# LITERAL "opponent" is the P2 side, so it is `theirs` that matches and `mine` that does not.
	_expect(not mine.matches_criteria(criteria, null), "with no source, \"opponent\" does not match the P1 card")
	_expect(theirs.matches_criteria(criteria, null), "it matches the P2 card, literally as before")

	# --- "your"/"their" still work, and agree with "opponent" from the other side ---------------------------
	_field.set_viable_targets({"is_type": "Forward", "controller": "your"}, theirs, "Ability")
	_expect(theirs.is_valid_target and not mine.is_valid_target, "\"your\" is still relative to the source")
	_field.set_viable_targets({"is_type": "Forward", "controller": "theirs"}, mine, "Ability")
	_expect(theirs.is_valid_target and not mine.is_valid_target, "and \"theirs\" is the other side")

	# Clean the flags so the assertion messages above cannot be confused by leftovers.
	_field.reset_targets()

	print("[Who] %d checks | failures: %d" % [_checks, _fails])
	print("[Who] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
