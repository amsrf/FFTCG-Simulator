extends Node
## Exact CP payment: once the cost is fulfilled, extra selections are ignored. The one legal overpay is a hand card
## producing 2 CP against a 1-CP gap (rule 11.2.2.2). This probe drives the two selection APIs directly.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _assistant = null
var _hand = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[ManaLimit] ok   ", what)
	else:
		_fails += 1
		print("[ManaLimit] FAIL ", what)


func _fire_card(side: String = "player") -> Card:
	var card: Card = _game.call("create_card", 30, side)  # 1-030R, Fire Backup
	_game.add_child(card)
	return card


func _clear_field_selection() -> void:
	for card in _field.selected_cards_for_mana_conversion.duplicate():
		_field.remove_card_from_mana_conversion(card)


func _clear_hand_selection() -> void:
	for card in _hand.selected_cards_for_mana_conversion.duplicate():
		_hand.remove_card_from_mana_conversion(card)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	_assistant = _game.get("assistant")
	_hand = _game.player.hand

	# --- FIELD: 2 CP, exactly two one-point sources -------------------------------------------------------
	_assistant.clear_payment_accumulator()
	_assistant.mana_cost = {"火": 2}
	GlobalVariables.push_modal(GlobalVariables.Player_Mode.PAYING_COST)

	var a: Card = _fire_card()
	var b: Card = _fire_card()
	var c: Card = _fire_card()
	_field.add_card_to_mana_conversion(a)
	_expect(not _assistant.can_pay_cost(), "one of two CP is not enough")
	_field.add_card_to_mana_conversion(b)
	_expect(_assistant.can_pay_cost(), "two of two CP fulfils the cost")
	_field.add_card_to_mana_conversion(c)
	_expect(_field.selected_cards_for_mana_conversion.size() == 2,
		"a third source is IGNORED once the 2-CP cost is fulfilled")
	_expect(c.crystal_instance == null, "and the ignored source shows no mana crystal")

	GlobalVariables.pop_modal(GlobalVariables.Player_Mode.PAYING_COST)
	_assistant.reset_buttons()
	_clear_field_selection()

	# --- HAND: the legal overpay is one hand card producing 2 against a 1-CP gap -------------------------
	_assistant.clear_payment_accumulator()
	_assistant.mana_cost = {"火": 1}
	GlobalVariables.push_modal(GlobalVariables.Player_Mode.PAYING_COST)

	var h1: Card = _fire_card()
	var h2: Card = _fire_card()
	_hand.add_card(h1)
	_hand.add_card(h2)
	_hand.add_card_to_mana_conversion(h1)
	_expect(_assistant.can_pay_cost(), "a hand card may overpay a 1-CP gap by one")
	_hand.add_card_to_mana_conversion(h2)
	_expect(_hand.selected_cards_for_mana_conversion.size() == 1,
		"a second hand card is IGNORED after the overpay fulfils the cost")
	_expect(h2.crystal_instance == null, "and the ignored hand card shows no mana crystal")

	GlobalVariables.pop_modal(GlobalVariables.Player_Mode.PAYING_COST)
	_assistant.reset_buttons()
	_clear_hand_selection()

	print("[ManaLimit] %d checks | failures: %d" % [_checks, _fails])
	print("[ManaLimit] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
