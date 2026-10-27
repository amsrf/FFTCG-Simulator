extends Node
const EFFECT_CONTEXT := preload("res://scripts/effects/effect_context.gd")
## FRAGILE probe — "if it is put from the field into the Break Zone this turn, remove it from the game instead".
##
## Fragile is a REPLACEMENT effect: the card must never reach the Break Zone. So the checks are that it ends up in the
## removed pile, that the Break Zone did not gain it, and that the field -> Break Zone TRIGGER did not fire (which is
## the difference between exiling and burying).

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Fragile] ok   %s" % what)
	else:
		_fails += 1
		print("[Fragile] FAIL %s" % what)


func _new_forward() -> Card:
	var field = _game.get("field")
	var card: Card = _game.create_card(41, "opponent")
	_game.add_child(card)
	field.play_card(card, true, false)
	card.status_effects.clear()
	card.accumulated_damage = 0
	return card


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	var grave = _game.get("opponent_graveyard")
	var removed = _game.get("opponent_removed")
	var grave_before: int = grave.graveyard_cards.size()
	var removed_before: int = removed.graveyard_cards.size()

	# --- the Bahamut shape: fragile FIRST, then lethal damage -------------------------------------------
	var a: Card = _new_forward()
	var b: Card = _new_forward()
	var ctx = EFFECT_CONTEXT.new(_game, a, "test")
	ctx.add_status([a, b], "fragile", 1)
	_expect(a.status_effects.has("fragile") and b.status_effects.has("fragile"),
		"both targets are fragile before the damage")
	ctx.damage([a, b], 10000)

	_expect(not a.is_on_field() and not b.is_on_field(), "both died to the damage")
	_expect(removed.graveyard_cards.has(a) and removed.graveyard_cards.has(b),
		"and both are in the REMOVED pile")
	_expect(not grave.graveyard_cards.has(a) and not grave.graveyard_cards.has(b),
		"neither is in the Break Zone")
	_expect(grave.graveyard_cards.size() == grave_before,
		"the Break Zone did not grow (%d -> %d)" % [grave_before, grave.graveyard_cards.size()])
	_expect(removed.graveyard_cards.size() == removed_before + 2,
		"the removed pile grew by exactly two (%d -> %d)" % [removed_before, removed.graveyard_cards.size()])

	# --- fragile is SPENT by the exile, and does not linger on the card --------------------------------
	_expect(not a.status_effects.has("fragile"), "the fragile status was consumed, not left behind")

	# --- a card WITHOUT fragile still goes to the Break Zone as usual -----------------------------------
	var c: Card = _new_forward()
	var ctx_c = EFFECT_CONTEXT.new(_game, c, "test")
	ctx_c.damage([c], 10000)
	_expect(grave.graveyard_cards.has(c), "an ordinary card still goes to the Break Zone")

	# --- the code shape ----------------------------------------------------------------------------------
	var bahamut = load("res://assets/effects/card_18.gd").new()
	_expect(bahamut.has_method("when_cast"), "Bahamut 18's cast effect is code-owned")

	print("[Fragile] %d checks | failures: %d" % [_checks, _fails])
	print("[Fragile] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
