extends Node
## GRANTED TARGET IMMUNITY — the runtime half of the cannot_be_chosen family.
##
## Zidane PRINTS the rule on the card, so it is always true and is read from card_effects. Aerith GRANTS it for a turn, so
## it lives in status_effects and expires in Card.turn_end(). Both are decided in ONE function, Card.can_be_chosen_by() —
## if these two ever need separate readers, that is the bug.
##
## Also covers apply_effect: the ability picking its own targets, as a SNAPSHOT taken when it resolves. A Forward that
## arrives later in the turn is not affected, which is the rule for "all Forwards you control".
##
##   godot --headless res://tests/immunity_probe.tscn --quit-after 900

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Immunity] ok   ", what)
	else:
		_fails += 1
		print("[Immunity] FAIL ", what)

func _a_forward(named_fire: bool) -> int:
	var db: Array = CardDatabase.card_database
	for i in range(db.size()):
		var e: Dictionary = db[i]
		if str(e.get("type_en", "")) != "Forward":
			continue
		var fire: bool = _is_fire(e)
		if fire == named_fire:
			return i + 1
	return 0

## NOT `"火" in (e.get("element") or [])`. GDScript's `or` yields a BOOL, so a missing element turns that into
## `"火" in true` and the whole expression dies with "Invalid operands 'String' and 'bool'". Worth spelling out, because
## the one-line version looks right and reads right.
func _is_fire(e: Dictionary) -> bool:
	var raw = e.get("element")
	if raw is Array:
		return "火" in raw
	return str(raw) == "火"

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var field = game.field

	var fire_forward: int = _a_forward(true)
	var plain_forward: int = _a_forward(false)
	_expect(fire_forward > 0 and plain_forward > 0, "the database has a Fire Forward and a non-Fire one")

	var mine: Card = game.create_card(fire_forward, "player")
	var theirs: Card = game.create_card(plain_forward, "player")
	field.add_child(mine)
	field.add_child(theirs)
	field.play_card(mine, false, false)
	field.play_card(theirs, false, false)

	# --- a NORMAL card is choosable by anyone -------------------------------------------------------
	_expect(mine.can_be_chosen_by(mine), "an ordinary card can be chosen by its own controller's effects")
	_expect(mine.can_be_chosen_by(null), "and by a caller that names no source")

	# --- the GRANT ---------------------------------------------------------------------------------
	mine.add_status_effect("cannot_be_chosen", 1)
	print("[Immunity] after the grant: has_status=%s" % mine.status_effects.has("cannot_be_chosen"))
	_expect(mine.status_effects.has("cannot_be_chosen"), "the status is on the card")
	_expect(not mine.can_be_chosen_by(null), "a granted card cannot be chosen even when no source is named")
	_expect(not mine.can_be_chosen_by(theirs), "nor by a card it does not control — a Summon or ability from elsewhere")
	_expect(not mine.can_be_chosen_by(mine),
		"AND NOT BY ITS OWN CONTROLLER EITHER — that is what 'even from yourself' means")
	_expect(theirs.can_be_chosen_by(null), "while a card that was not granted is untouched")

	# --- it is one turn, and no more ---------------------------------------------------------------
	mine.turn_end()
	print("[Immunity] after turn_end: has_status=%s" % mine.status_effects.has("cannot_be_chosen"))
	_expect(not mine.status_effects.has("cannot_be_chosen"), "the grant expires at the end of the turn")
	_expect(mine.can_be_chosen_by(theirs), "and the card is choosable again")

	# --- PRINTED protection is a different thing and still works -----------------------------------
	var zidane: Card = null
	for c in field.get_all_cards():
		if c.card_name == "Zidane":
			zidane = c
	_expect(zidane != null, "the debug board has Zidane on it (printed cannot_be_chosen)")
	if zidane != null:
		_expect(not zidane.can_be_chosen_by(mine, "Summon"),
			"Zidane still refuses an opponent's Summon — the printed rule is decided by SOURCE")
		_expect(zidane.can_be_chosen_by(null),
			"and with no source named the printed rule does not apply, unlike a GRANT, which is unconditional")

	# --- apply_effect chooses its own targets, ONCE -------------------------------------------------
	var block: Dictionary = game._apply_effect_block(mine)
	_expect(block.is_empty(), "an ordinary card has no apply_effect block")
	var snapshot: Array = game._cards_matching({"is_type": "Forward", "controller": "player"})
	print("[Immunity] apply_effect snapshot: %d player Forward(s)" % snapshot.size())
	_expect(snapshot.has(mine) and snapshot.has(theirs), "the block selects the player's own Forwards")
	var arrival: Card = game.create_card(fire_forward, "player")
	field.add_child(arrival)
	field.play_card(arrival, false, false)
	_expect(not snapshot.has(arrival),
		"and a Forward that arrives LATER is not in it — the set is a snapshot, not a standing effect")
	_expect(game._cards_matching({"is_type": "Forward", "controller": "player"}).has(arrival),
		"while a fresh query does see it, which is the difference between a snapshot and a rule")

	_finish()

func _finish() -> void:
	print("[Immunity] %d checks | failures: %d" % [_checks, _fails])
	print("[Immunity] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0)
