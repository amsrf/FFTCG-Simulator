extends Node
## BLOCKING / ATTACKING criteria probe.
##
## A criteria block is turned into Card method calls, so the predicates have to answer BOTH directions: "a blocking
## Forward" (is_blocking true) and "not blocking" (is_blocking false). The old is_tapped ignored its argument and
## returned tapped-ness either way, which would silently select the opposite set — so it is checked here too.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Criteria] ok   %s" % what)
	else:
		_fails += 1
		print("[Criteria] FAIL %s" % what)


func _new_card() -> Card:
	var card: Card = _game.create_card(41, "player")
	_game.add_child(card)
	_field.play_card(card, false, false)
	card.status_effects.clear()
	card.accumulated_damage = 0
	return card


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	var attacker: Card = _new_card()
	var blocker: Card = _new_card()
	var bystander: Card = _new_card()
	attacker.set_attacker_status(true)
	blocker.set_blocker_status(true)

	# --- is_blocking, both directions ------------------------------------------------------------------
	_expect(blocker.matches_criteria({"is_blocking": true}), "the blocker matches {is_blocking: true}")
	_expect(not attacker.matches_criteria({"is_blocking": true}), "the attacker does not")
	_expect(attacker.matches_criteria({"is_blocking": false}),
		"and {is_blocking: false} picks the ones that are NOT blocking")

	# --- is_attacking -----------------------------------------------------------------------------------
	_expect(attacker.matches_criteria({"is_attacking": true}), "the attacker matches {is_attacking: true}")
	_expect(not blocker.matches_criteria({"is_attacking": true}),
		"a blocker is not attacking, even though it is in combat")
	_expect(bystander.matches_criteria({"is_attacking": false}),
		"a card outside combat is not attacking")

	# --- DECLARING a block must mark the card, whoever declared it ---------------------------------------
	# This is the bug the user hit: the status was only set by the human's CLICK selection, so an AI-declared
	# blocker was never "blocking" and effects targeting a blocking Forward found nothing. Game.set_blocker() is
	# the declaration for both sides, so it must be the one that marks the card.
	var ai_blocker: Card = _new_card()
	ai_blocker.status_effects.clear()
	_expect(not ai_blocker.is_blocking(), "a fresh card is not blocking")
	_game.set_blocker(ai_blocker)
	_expect(ai_blocker.is_blocking(),
		"set_blocker() marks the card — an AI/summoned block goes through here, not through the click handler")
	_expect(ai_blocker.matches_criteria({"is_type": "Forward", "is_blocking": true}),
		"so card 100's 'blocking Forward' block now matches it")
	_field.reset_blocker()
	_expect(not ai_blocker.is_blocking(), "and reset_blocker() clears it at the end of combat")
	_field.remove_card(ai_blocker)

	# --- is_tapped now honours its argument -------------------------------------------------------------
	attacker.tap()
	_expect(attacker.matches_criteria({"is_tapped": true}), "{is_tapped: true} finds a tapped card")
	_expect(bystander.matches_criteria({"is_tapped": false}),
		"{is_tapped: false} finds an untapped card — it used to return the opposite set")

	# --- a realistic block, as card 100 would write it ---------------------------------------------------
	var blocking_forward: Dictionary = {"is_type": "Forward", "is_blocking": true}
	_expect(blocker.matches_criteria(blocking_forward), "card 100's 'blocking Forward' block matches the blocker")
	_expect(not bystander.matches_criteria(blocking_forward), "and not an idle Forward")

	# --- the data is present and well-formed -------------------------------------------------------------
	var db = CardDatabase.card_effects
	_expect(db.has("100") and db.has("43"), "cards 100 and 43 are in the effects file")
	print("[Criteria] 100 -> %s" % str(db.get("100", {})))
	print("[Criteria] 43  -> %s" % str(db.get("43", {})))

	_finish()


func _finish() -> void:
	print("[Criteria] %d checks | failures: %d" % [_checks, _fails])
	print("[Criteria] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
