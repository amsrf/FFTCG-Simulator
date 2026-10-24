extends Node
## SELF-SACRIFICE probe — "put THIS card into the Break Zone, then …":
##   10 Black Mage  《Fire》《Dull》 → 4000 damage to a Forward
##   88 Archer      《Wind》《Wind》《Dull》 → break a Backup of cost 3 or less
##
## The cost is `"sacrifice": {"is_source": true}`: no picker, because there is nothing to choose. The card leaves the
## field at ACTIVATION, and the ability still resolves from the stack with its own source already in the Break Zone.

const GAME_SCENE := preload("res://game.tscn")

const BLACK_MAGE := 10
const ARCHER := 88
const SQUALL := 41
const CHEMIST := 31
const FIRE_MANA := 3
const WIND_MANA := 68

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _stack = null
var _assistant = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[SelfSac] ok   %s" % what)
	else:
		_fails += 1
		print("[SelfSac] FAIL %s" % what)


func _card(id: int) -> Card:
	for c in _field.get_all_cards():
		if c.id == id:
			return c
	return null


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [
			{"id": BLACK_MAGE}, {"id": ARCHER},
			{"id": FIRE_MANA}, {"id": WIND_MANA}, {"id": WIND_MANA},
		],
		"opponent_field": [{"id": SQUALL}, {"id": CHEMIST}],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	_stack = _game.get("stack")
	_assistant = _game.get("assistant")
	_game.set("priority_holder", 1)
	_game.set("_priority_lock", true)   # absorb request_priority; the probe drives resolution

	var mage: Card = _card(BLACK_MAGE)
	var archer: Card = _card(ARCHER)
	var squall: Card = _card(SQUALL)
	var chemist: Card = _card(CHEMIST)

	# --- 10 Black Mage: sacrifice, pay fire, 4000 damage ----------------------------------------------------
	var mage_skill: Dictionary = mage.card_effects["skill"][0]
	_expect(bool(mage_skill.get("sacrifice", {}).get("is_source", false)),
		"Black Mage's cost sacrifices the source itself")
	_expect(_field.can_activate_now(mage), "the ability is available")

	_field.call("begin_skill_activation", mage, 0)
	await get_tree().process_frame
	print("[SelfSac] Black Mage on field=%s, graveyard=%d" % [
		str(mage.is_on_field()), _game.get("player").graveyard.graveyard_cards.size()])
	_expect(not mage.is_on_field(), "activating it puts Black Mage into the Break Zone")
	_expect(_game.get("player").graveyard.graveyard_cards.has(mage), "and it IS in the Break Zone")
	_expect(_stack.stack_length() == 1, "the ability is on the stack")

	# Pay the 《Fire》 and let the flow continue.
	_assistant.call("charge", 1, "火")
	_expect(_assistant.call("can_pay_cost"), "the fire cost is paid")
	_assistant.call("on_charge_complete")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET,
		"payment leads straight to target selection")
	_field.set_target_card(squall)
	await get_tree().process_frame
	_assistant.call("on_target_complete")
	await get_tree().process_frame
	await _stack.resolve_top_effect()
	await get_tree().process_frame
	print("[SelfSac] Squall took %d" % squall.accumulated_damage)
	_expect(squall.accumulated_damage == 4000, "and the ability resolves for 4000")

	# --- 88 Archer: sacrifice, pay wind, break a cheap Backup ----------------------------------------------
	_game.set("priority_holder", 1)
	var archer_skill: Dictionary = archer.card_effects["skill"][0]
	_expect(bool(archer_skill.get("sacrifice", {}).get("is_source", false)),
		"Archer sacrifices itself too")
	_expect(bool(archer_skill.get("choose_target", {}).get("is_cost_at_most", false)),
		"and its target is a Backup of cost 3 or less")

	_field.call("begin_skill_activation", archer, 0)
	await get_tree().process_frame
	_expect(not archer.is_on_field(), "activating it puts Archer into the Break Zone")
	_assistant.call("charge", 1, "風")
	_assistant.call("charge", 1, "風")
	_expect(_assistant.call("can_pay_cost"), "the two wind are paid")
	_assistant.call("on_charge_complete")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET,
		"and it asks for a target")
	_field.set_target_card(chemist)
	await get_tree().process_frame
	_assistant.call("on_target_complete")
	await get_tree().process_frame
	await _stack.resolve_top_effect()
	await get_tree().process_frame
	print("[SelfSac] Chemist on field=%s" % str(chemist.is_on_field()))
	_expect(not chemist.is_on_field(), "the chosen Backup is broken")

	print("[SelfSac] %d checks | failures: %d" % [_checks, _fails])
	print("[SelfSac] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
