extends Node
## FREEZE + DULL probe.
##
## Freeze is "does not activate during its controller's next Active Phase", so the checks are about the untap step
## and about the status being SPENT there rather than counted down:
##
##   1. a frozen, tapped card is NOT untapped, and the status is consumed
##   2. the very next Active Phase DOES untap it — the freeze does not linger
##   3. turn_end() does not erase the status, so applying it on the victim's own turn still works
##   4. untap_targets("Activate") still works on a frozen card — Freeze denies the Phase, not activation
##   5. dull_targets taps what it is pointed at

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Freeze] ok   %s" % what)
	else:
		_fails += 1
		print("[Freeze] FAIL %s" % what)


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

	# --- 1 & 2: skipped once, then gone ---------------------------------------------------------------
	var card: Card = _new_card()
	card.tap()
	card.status_effects["frozen"] = 1
	_field.untap_cards_for("player")
	_expect(card.tapped, "a frozen card does NOT activate in the Active Phase")
	_expect(not card.is_frozen(), "and the freeze is CONSUMED by the untap it denied")
	_field.untap_cards_for("player")
	_expect(not card.tapped, "the next Active Phase untaps it normally — the freeze does not linger")
	_field.remove_card(card)

	# --- 3: turn_end must not spend it ----------------------------------------------------------------
	card = _new_card()
	card.status_effects["frozen"] = 1
	card.turn_end()
	_expect(card.is_frozen(),
		"turn_end leaves it alone, so a freeze applied on the victim's OWN turn still reaches their Active Phase")
	_field.untap_cards_for("player")
	_expect(not card.is_frozen(), "and that Active Phase then spends it")
	_field.remove_card(card)

	# --- 4: "Activate" still works on a frozen card ----------------------------------------------------
	card = _new_card()
	card.tap()
	card.status_effects["frozen"] = 1
	_game.set("_targets", [card])
	_game.untap_targets()
	_expect(not card.tapped, "untap_targets still works on a frozen card — Freeze denies the Phase, not activation")
	_field.remove_card(card)

	# --- 5: dull_targets is the instruction the data was missing -----------------------------------------
	card = _new_card()
	_expect(not card.tapped, "the card starts untapped")
	_game.set("_targets", [card])
	_game.dull_targets()
	_expect(card.tapped, "dull_targets taps it")
	_field.remove_card(card)

	_finish()


func _finish() -> void:
	print("[Freeze] %d checks | failures: %d" % [_checks, _fails])
	print("[Freeze] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
