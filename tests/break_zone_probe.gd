extends Node
## BREAK ZONE trigger probe — who fires, when, and with what flag.
##
## The rule under test: the effect is added to the stack only AFTER the card has arrived in the Break Zone, and the
## difference between the two keywords is a flag, not a separate code path.
##
##   broke (damage >= power)      -> when_enter_break_from_field + when_break
##   power reduced to 0           -> when_enter_break_from_field only
##   discarded from hand          -> neither (not "from the field")
##   exiled by fragile            -> neither (never reaches the pile)
##   and `broken` is cleared in every case

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[BreakZone] ok   %s" % what)
	else:
		_fails += 1
		print("[BreakZone] FAIL %s" % what)


## A Forward on the field with BOTH keywords, so every case can be told apart.
func _new_forward() -> Card:
	var field = _game.get("field")
	var card: Card = _game.create_card(41, "opponent")
	_game.add_child(card)
	field.play_card(card, true, false)
	card.status_effects.clear()
	card.accumulated_damage = 0
	card.broken = false
	card.card_effects["when_enter_break_from_field"] = {"instructions": []}
	card.card_effects["when_break"] = {"instructions": []}
	return card


## Which keywords the stack gained since `before`.
func _new_keywords(before: int) -> Array:
	var stack = _game.get("stack")
	var out: Array = []
	for i in range(before, stack.cards.size()):
		out.append(str(stack.cards[i].key_word_effect))
	return out


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	var stack = _game.get("stack")

	# --- 1. BROKE: both keywords, after the card is in the pile ---------------------------------------
	var breaker: Card = _new_forward()
	var before: int = stack.stack_length()
	breaker.accumulated_damage = breaker.power + 1000
	_game.enforce_game_state_rules()
	var got: Array = _new_keywords(before)
	print("[BreakZone] broke -> %s" % str(got))
	_expect(got.has("when_enter_break_from_field"), "a broken card pushes when_enter_break_from_field")
	_expect(got.has("when_break"), "and when_break")
	_expect(not breaker.broken, "and the broken flag is cleared once the effects are on the stack")
	_expect(breaker.current_zone == Card.Zone.GRAVEYARD, "the card is already in the pile when the effects are added")

	# --- 2. POWER ZERO: arrival only ------------------------------------------------------------------
	var zero: Card = _new_forward()
	before = stack.stack_length()
	zero.set_base_power(0)
	_game.enforce_game_state_rules()
	got = _new_keywords(before)
	print("[BreakZone] power 0 -> %s" % str(got))
	_expect(got.has("when_enter_break_from_field"), "a card removed at 0 power still ARRIVES in the Break Zone")
	_expect(not got.has("when_break"), "but it did not break, so when_break does not fire")
	_expect(not zero.broken, "flag cleared")

	# --- 3. DISCARDED FROM HAND: nothing --------------------------------------------------------------
	var hand = _game.get("hand")
	var discarded: Card = hand.cards[0]
	before = stack.stack_length()
	hand.discard_card(discarded)
	got = _new_keywords(before)
	print("[BreakZone] discarded -> %s" % str(got))
	_expect(got.is_empty(), "a card discarded from hand fires neither keyword — it was not put from the FIELD")

	# --- 4. EXILED: nothing ---------------------------------------------------------------------------
	var exiled: Card = _new_forward()
	exiled.status_effects["fragile"] = 1
	before = stack.stack_length()
	exiled.accumulated_damage = exiled.power + 1000
	_game.enforce_game_state_rules()
	got = _new_keywords(before)
	print("[BreakZone] exiled -> %s" % str(got))
	_expect(got.is_empty(), "an exiled card fires neither keyword — it never reaches the pile")
	_expect(not exiled.broken, "flag cleared on exile too")

	print("[BreakZone] %d checks | failures: %d" % [_checks, _fails])
	print("[BreakZone] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
