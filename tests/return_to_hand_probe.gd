extends Node
## RETURN TO HAND probe — the zone change and the two-phase animation.
##
## The card must end up a REAL hand card (child of the Hand, in `cards`, HAND zone, hand scale), not just visually
## near the hand. The animation itself is not measurable headlessly beyond "it finished", so what is asserted is the
## end state plus the promise that the instruction waits for it.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[ReturnToHand] ok   %s" % what)
	else:
		_fails += 1
		print("[ReturnToHand] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	var field = _game.get("field")
	var hand = _game.get("hand")
	var before: int = hand.cards.size()

	var card: Card = _game.create_card(41, "player")
	_game.add_child(card)
	field.play_card(card, false, false)
	await get_tree().process_frame
	_expect(card.current_zone == Card.Zone.FIELD, "the card starts on the FIELD")

	_game.set("_targets", [card])
	# AWAITED on purpose: this is what stops the effect resolving while the card is between zones.
	await _game.return_targets_to_hand()

	_expect(hand.cards.has(card), "the card joined the hand's card list (%d -> %d)" % [before, hand.cards.size()])
	_expect(card.get_parent() == hand, "and it is now a child of the Hand")
	_expect(card.current_zone == Card.Zone.HAND, "its zone is HAND (got %d)" % card.current_zone)
	var expected: float = hand.hand_scale
	_expect(absf(card.scale.x - expected) < 0.05,
		"it is at hand scale (%.3f vs %.3f)" % [card.scale.x, expected])

	# It must be usable as a hand card afterwards, not a painted impostor.
	var index: int = hand.cards.find(card)
	_expect(index == hand.cards.size() - 1, "it sits at the end of the row (index %d)" % index)
	var slot: Vector3 = hand.calculate_card_position(index)
	_expect(card.position.distance_to(slot) < 0.12,
		"and it is in its slot (%.3f m off)" % card.position.distance_to(slot))

	# --- the data capability is present ---------------------------------------------------------------
	_expect(_game.has_method("return_targets_to_hand"), "the instruction exists")

	print("[ReturnToHand] %d checks | failures: %d" % [_checks, _fails])
	print("[ReturnToHand] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
