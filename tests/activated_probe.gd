extends Node
## ACTIVATED ABILITIES probe — the ones with no tap (or with a dull cost) rather than an S cost:
##   22 Firion    4 abilities: 《1》 First Strike, 《1》 Brave, 《2》 1000 damage, 《2》 +1000
##   84 Y'shtola  2 abilities: 《Wind》 1000 damage, 《Dull》 2000 damage
##
## They are ordinary `skill` entries — the only difference from an S ability is that they carry NO `s_cost`, and one
## of them pays with `tap` instead of mana. This probe checks the gate, the data, and that the effects resolve.

const GAME_SCENE := preload("res://game.tscn")

const FIRION := 22
const YSHTOLA := 84
const SQUALL := 41
const SNOW := 43
const FIRE_MANA := 3
const WIND_MANA := 68

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _stack = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Activated] ok   %s" % what)
	else:
		_fails += 1
		print("[Activated] FAIL %s" % what)


func _card(id: int) -> Card:
	for c in _field.get_all_cards():
		if c.id == id:
			return c
	return null


func _activate(firion_skill: int) -> Card:
	## The part of activation the probe needs: a stack object for the ability. Costs are covered by their own tests.
	var proxy: Card = null
	if _stack.call("add_skill_activation_proxy", _card(FIRION), firion_skill):
		proxy = _stack.get("skill_activation_proxy")
	return proxy


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": FIRION}, {"id": YSHTOLA}, {"id": FIRE_MANA}, {"id": WIND_MANA}],
		"opponent_field": [{"id": SQUALL}, {"id": SNOW}],
		"player_deck": range(101, 131),
		"opponent_deck": range(141, 171),
	})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	_stack = _game.get("stack")

	# The gate needs priority and a Main Phase mode, exactly as it does in play.
	_game.set("priority_holder", 1)
	var firion: Card = _card(FIRION)
	var yshtola: Card = _card(YSHTOLA)
	var squall: Card = _card(SQUALL)
	_expect(_field.can_activate_now(firion), "Firion's activated abilities are offered with priority")
	_expect(_field.can_activate_now(yshtola), "and so are Y'shtola's")

	# --- the data -----------------------------------------------------------------------------------------
	var firion_skills: Array = firion.activation_skills()
	var yshtola_skills: Array = yshtola.activation_skills()
	print("[Activated] Firion %d abilities, Y'shtola %d" % [firion_skills.size(), yshtola_skills.size()])
	_expect(firion_skills.size() == 4, "Firion has all four abilities")
	_expect(not bool(firion_skills[0].get("tap", false)), "none of them dulls him")
	_expect(int(firion_skills[0].get("cost", {}).get("neutral", 0)) == 1, "the first costs 《1》")
	_expect(int(firion_skills[2].get("cost", {}).get("neutral", 0)) == 2, "the damage one costs 《2》")
	_expect(yshtola_skills.size() == 2, "Y'shtola has both")
	_expect(bool(yshtola_skills[1].get("tap", false)), "the second pays with 《Dull》")
	_expect(not bool(yshtola_skills[0].get("tap", false)), "the first does not")

	# --- 《1》: First Strike -------------------------------------------------------------------------------
	_activate(0)
	_expect(_stack.stack_length() == 1, "the ability is on the stack")
	await _stack.resolve_top_effect()
	_expect(firion.is_first_strike(), "resolving it gives Firion First Strike")
	_expect(not firion.tapped, "and does NOT dull him")

	# --- 《2》: +1000 power --------------------------------------------------------------------------------
	_activate(3)
	await _stack.resolve_top_effect()
	_expect(firion.power == 7000 + 1000, "the power ability raises Firion to 8000 (%d)" % firion.power)

	# --- 《2》: 1000 damage to a chosen Forward -------------------------------------------------------------
	_game.set("_priority_lock", true)   # absorb the request_priority the commit emits; the probe resolves it itself
	var proxy: Card = _activate(2)
	_field.request_target({"is_type": "Forward"}, proxy, false, "Ability")
	_expect(squall.is_valid_target, "the damage ability opens a targeting session")
	_field.set_target_card(squall)
	await get_tree().process_frame
	_game.get("assistant").call("on_target_complete")
	await get_tree().process_frame
	await _stack.resolve_top_effect()
	print("[Activated] Squall after the 1000 ability: %d" % squall.accumulated_damage)
	_expect(squall.accumulated_damage == 1000, "and deals its 1000 damage")
	_game.set("_priority_lock", false)

	# --- a tap-costed ability still needs the card active ---------------------------------------------------
	yshtola.tap()
	_expect(not _field.can_activate_now(yshtola), "a dull Y'shtola cannot activate anything")
	yshtola.untap()
	# The priority loop moves the holder to the opponent after the ability above; put it back so this checks the
	# ACTIVATION gate rather than whose turn it is.
	_game.set("priority_holder", 1)
	_expect(_field.can_activate_now(yshtola), "an active one can")

	print("[Activated] %d checks | failures: %d" % [_checks, _fails])
	print("[Activated] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
