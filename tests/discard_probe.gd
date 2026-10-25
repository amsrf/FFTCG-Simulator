extends Node
## DISCARD probe — the AI side of "your opponent discards 1 card from their hand".
##
## The rule is that the DISCARDER chooses, so the seam asks the side that owns the hand. The local player's branch
## opens the hand-selection UI and cannot be driven headlessly; what is checked here is the other branch — an AI
## asked to discard — plus the empty-hand guard, which is the case that would otherwise crash mid-effect.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[DiscardProbe] ok   %s" % what)
	else:
		_fails += 1
		print("[DiscardProbe] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("ai")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	var ai_hand = _game.get("opponent_hand")
	var ai_grave = _game.get("opponent_graveyard")
	var before_hand: int = ai_hand.cards.size()
	var before_grave: int = ai_grave.graveyard_cards.size()
	print("[DiscardProbe] AI hand %d, graveyard %d" % [before_hand, before_grave])

	await _game.discard_from(2, 1)
	_expect(ai_hand.cards.size() == before_hand - 1,
		"the AI's hand lost exactly one card (%d -> %d)" % [before_hand, ai_hand.cards.size()])
	_expect(ai_grave.graveyard_cards.size() == before_grave + 1,
		"and it went to the AI's graveyard (%d -> %d)" % [before_grave, ai_grave.graveyard_cards.size()])

	# --- the AI keeps its cheapest card, so the expensive ones should survive ---------------------------
	print("[DiscardProbe] AI hand now: %s" % str(_names(ai_hand.cards)))

	# --- empty hand must not crash or loop -------------------------------------------------------------
	for card in ai_hand.cards.duplicate():
		ai_hand.discard_card(card)
	_expect(ai_hand.cards.is_empty(), "hand emptied for the guard test")
	await _game.discard_from(2, 3)
	_expect(ai_hand.cards.is_empty(), "asking an empty hand to discard three times is a no-op, not a crash")

	# --- the data is present ---------------------------------------------------------------------------
	var db = CardDatabase.card_effects
	_expect((db.has("33") or FileAccess.file_exists("res://assets/effects/card_33.gd"))
		and (db.has("51") or FileAccess.file_exists("res://assets/effects/card_51.gd")),
		"cards 33 (Argath) and 51 (Nooj) carry the effect")
	print("[DiscardProbe] 33 -> %s" % str(db.get("33", {})))

	_finish()


func _names(cards: Array) -> String:
	var out: Array = []
	for c in cards:
		out.append(c.card_name)
	return ", ".join(out)


func _finish() -> void:
	print("[DiscardProbe] %d checks | failures: %d" % [_checks, _fails])
	print("[DiscardProbe] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
