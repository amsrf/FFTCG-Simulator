extends Node
## SUMMONER 53 probe — countering a Summon.
##
## "《Ice》, put Summoner into the Break Zone: Choose 1 Summon. Cancel its effect."
##
## This is the first effect whose target lives on the STACK rather than the field. It checks that:
##   * the targeting session's candidates come from the stack and only Summons qualify,
##   * the chosen Summon is removed WITHOUT resolving (a normal Ifrit would have dealt 4000 to Squall),
##   * the card still reaches its owner's Break Zone, because its cost was paid.

const GAME_SCENE := preload("res://game.tscn")

const SUMMONER := 53
const IFRIT := 4
const SQUALL := 41
const ICE_MANA := 31

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _stack = null
var _assistant = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Counter] ok   %s" % what)
	else:
		_fails += 1
		print("[Counter] FAIL %s" % what)


func _card(id: int) -> Card:
	for c in _field.get_all_cards():
		if c.id == id:
			return c
	return null


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": SUMMONER}, {"id": ICE_MANA}],
		"opponent_field": [{"id": SQUALL}],
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

	var summoner: Card = _card(SUMMONER)
	var squall: Card = _card(SQUALL)
	var _ice: Card = _card(ICE_MANA)

	# Put a real Ifrit on the stack, as if the opponent had just cast it.
	var ifrit: Card = _game.call("create_card", IFRIT, "opponent")
	_game.add_child(ifrit)
	_stack.call("add_card_to_tree", ifrit)
	_expect(_stack.stack_length() == 1, "an Ifrit is waiting on the stack")
	_expect(ifrit.is_type("Summon"), "and it is a Summon")

	# The ability is only offered while a Summon is there to counter.
	_game.set("priority_holder", 1)
	_expect(_field.can_activate_now(summoner), "Summoner's ability is available")
	_game.set("_priority_lock", true)

	_field.call("begin_skill_activation", summoner, 0)
	await get_tree().process_frame
	_expect(not summoner.is_on_field(), "activating it puts Summoner into the Break Zone")
	_assistant.call("charge", 1, "氷")
	_expect(_assistant.call("can_pay_cost"), "the ice cost is paid")
	_assistant.call("on_charge_complete")
	await get_tree().process_frame
	await get_tree().process_frame

	var proxy: Card = _stack.get("skill_activation_proxy")
	_expect(GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET,
		"the ability asks for a target")
	_expect(_field.get("targeting_domain") == "stack", "and the session's domain is the STACK")
	_expect(ifrit.is_valid_target, "the Summon IS a legal target")
	_expect(proxy == null or not proxy.is_valid_target, "the ability itself is NOT")

	_field.set_target_card(ifrit)
	await get_tree().process_frame
	_assistant.call("on_target_complete")
	await get_tree().process_frame
	await _stack.resolve_top_effect()
	await get_tree().process_frame

	print("[Counter] stack=%d, Ifrit in stack=%s, in opponent Break Zone=%s, Squall damage=%d" % [
		_stack.stack_length(), str(_stack.cards.has(ifrit)),
		str(_game.get("opponent").graveyard.graveyard_cards.has(ifrit)),
		squall.accumulated_damage])
	_expect(_stack.stack_length() == 0, "the counter clears the stack")
	_expect(not _stack.cards.has(ifrit), "the Summon is gone from the stack")
	_expect(_game.get("opponent").graveyard.graveyard_cards.has(ifrit),
		"and went to its owner's Break Zone, since it was paid for")
	_expect(squall.accumulated_damage == 0, "its effect never resolved, so Squall took no damage")

	print("[Counter] %d checks | failures: %d" % [_checks, _fails])
	print("[Counter] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
