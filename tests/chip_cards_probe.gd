extends Node
const EVENTS := preload("res://scripts/effects/events.gd")
## CHIP CARDS probe — the three that needed one small piece of vocabulary each:
##   78 Ninja    《Wind》, discard 1 card from hand: 2000 damage to a Forward   (discard as a COST)
##   81 Bartz    "Bartz has all the jobs"                                        (job checks always succeed)
##   91 Amodar   ETB: search for Lightning OR Snow                               (OR filter)

const GAME_SCENE := preload("res://game.tscn")
const CARD_FILTER := preload("res://scripts/card_filter.gd")
const LOCAL_AGENT := preload("res://scripts/agents/local_agent.gd")

const NINJA := 78
const BARTZ := 81
const SQUALL := 41
const WIND_MANA := 68
const LIGHTNING := 141   # 1-141L
const SNOW := 43         # 1-043H
const AURON := 1

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _stack = null
var _assistant = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Chip] ok   %s" % what)
	else:
		_fails += 1
		print("[Chip] FAIL %s" % what)


func _card(id: int) -> Card:
	for c in _field.get_all_cards():
		if c.id == id:
			return c
	return null


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": NINJA}, {"id": BARTZ}, {"id": WIND_MANA}],
		"player_hand": [AURON],
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

	# --- 78 Ninja: discard a card as part of the cost -------------------------------------------------------
	var ninja: Card = _card(NINJA)
	var squall: Card = _card(SQUALL)
	var hand = _game.get("hand")
	_expect(hand.cards.size() == 1, "one card in hand to discard")
	var hand_before: int = hand.cards.size()

	# The owner answers the discard through the agent seam; AIAgent picks the cheapest, which is what a probe needs.
	var agent = AIAgent.new()
	agent.bind(_game)
	_game.set("player_agent", agent)
	_game.set("priority_holder", 1)
	_game.set("_priority_lock", true)
	_expect(_field.can_activate_now(ninja), "Ninja's ability is available")

	_field.call("begin_skill_activation", ninja, 0)
	for _i in range(6):
		await get_tree().process_frame
	print("[Chip] hand %d -> %d, graveyard=%d" % [
		hand_before, hand.cards.size(), _game.get("player").graveyard.graveyard_cards.size()])
	_expect(hand.cards.size() == hand_before - 1, "activating it discards one card from hand")
	_expect(_game.get("player").graveyard.graveyard_cards.size() == 1,
		"and that card went to the Break Zone")
	_expect(_stack.stack_length() == 1, "the ability is on the stack")

	# The AI agent was only there to answer the DISCARD. Put the human back before targeting, or the same agent
	# would also auto-pick the damage target and pop the TARGET modal before the probe can look at it.
	var human = LOCAL_AGENT.new()
	human.bind(_game)
	_game.set("player_agent", human)

	_assistant.call("charge", 1, "風")
	_expect(_assistant.call("can_pay_cost"), "the wind cost is paid")
	_assistant.call("on_charge_complete")
	for _i in range(20):
		await get_tree().process_frame
		if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET:
			break
	print("[Chip] mode after payment: %s | modals=%s | source=%s" % [
		str(GlobalVariables.get_player_mode()), str(GlobalVariables.get("_modal_stack")),
		str(_field.get("source_card"))])
	_expect(GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET,
		"payment leads to target selection")
	_field.set_target_card(squall)
	await get_tree().process_frame
	_assistant.call("on_target_complete")
	await get_tree().process_frame
	await _stack.resolve_top_effect()
	await get_tree().process_frame
	print("[Chip] Squall took %d" % squall.accumulated_damage)
	_expect(squall.accumulated_damage == 2000, "and it deals 2000 damage")

	# With an empty hand the ability is no longer offered.
	_game.set("priority_holder", 1)
	_expect(not _field.can_activate_now(ninja), "with no card to discard, the ability is closed")

	# --- 81 Bartz: all jobs --------------------------------------------------------------------------------
	var bartz: Card = _card(BARTZ)
	_expect(bartz.is_job("Pilot"), "Bartz counts as every job (Pilot)")
	_expect(bartz.matches_criteria({"job": "Pilot"}), "so a 'job' criteria block finds him")
	_expect(not squall.is_job("Pilot"), "while a normal card does not")
	_expect(squall.is_job("SeeD"), "though its printed job (SeeD) still matches")

	# --- 91 Amodar: Lightning OR Snow ----------------------------------------------------------------------
	var lightning: Dictionary = CARD_FILTER.card_by_id(LIGHTNING)
	var snow: Dictionary = CARD_FILTER.card_by_id(SNOW)
	var auron: Dictionary = CARD_FILTER.card_by_id(AURON)
	var or_filter: Dictionary = {"any": [{"name": "Lightning"}, {"name": "Snow"}]}
	_expect(CARD_FILTER.matches(lightning, or_filter), "the OR filter accepts Lightning")
	_expect(CARD_FILTER.matches(snow, or_filter), "and Snow")
	_expect(not CARD_FILTER.matches(auron, or_filter), "but not an unrelated card")
	_expect(load("res://assets/effects/card_91.gd").new().ex_burst_event() == EVENTS.Event.ENTER_FIELD,
		"Amodar's code EX burst runs its enter-the-field search")

	print("[Chip] %d checks | failures: %d" % [_checks, _fails])
	print("[Chip] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
