extends Node
## Tama 1-111C: 《X》 declaration before payment, exact CP payment, deferred self-sacrifice, and the cost-X hand pick.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


class TamaAgent extends Agent:
	var chosen_x: int = 0
	var wanted: Card = null

	func choose_number(_owner_id: int, _minimum: int, _maximum: int, _prompt: String = "") -> int:
		await _settle()
		return chosen_x

	func choose_field_card(_owner_id: int, candidates: Array, _prompt: String = "") -> Card:
		await _settle()
		if wanted != null and candidates.has(wanted):
			return wanted
		return candidates[0] if not candidates.is_empty() else null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Tama] ok   %s" % what)
	else:
		_fails += 1
		print("[Tama] FAIL %s" % what)


func _make(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_game.get("field").play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	card.untap()
	return card


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	var field = _game.get("field")
	var stack = _game.get("stack")
	var hand = _game.get("hand")
	var assistant = _game.get("assistant")

	var tama: Card = _make(111, "player")
	var mana_a: Card = _make(105, "player")
	var mana_b: Card = _make(120, "player")
	var played: Card = _game.call("create_card", 29, "player")
	_game.add_child(played)
	hand.add_card(played)

	var agent := TamaAgent.new()
	agent.bind(_game)
	agent.chosen_x = 2
	agent.wanted = played
	_game.set("player_agent", agent)
	_game.set("priority_holder", 1)
	GlobalVariables.refresh_mode()

	_expect(tama.activation_skills().size() == 1, "Tama exposes one activated ability")
	_expect(tama.activation_ability_spec(0) != null, "the ability is a code-defined AbilitySpec")
	_expect(bool(tama.activation_skill(0).get("x_cost", false)), "the ability declares an 《X》 cost")
	_expect(field.ability_x_max(tama) == 2,
		"X is capped by the best Character in hand and by the two available mana sources")

	await field.begin_skill_activation(tama, 0)
	_expect(tama.tapped, "the Dull cost is paid at activation")
	_expect(stack.skill_activation_proxy != null, "the ability has a stack proxy before payment")
	_expect(stack.skill_activation_proxy.ability_x_value == 2,
		"the declared X is stored on the stack proxy")
	_expect(int(stack.skill_activation_proxy.skill_def_override.get("x_value", -1)) == 2,
		"and the proxy's snapshot carries X")
	_expect(int(stack.skill_activation_proxy.skill_def_override.get("cost", {}).get("neutral", -1)) == 2,
		"the payment cost becomes {neutral: 2}")

	# Cancel the payment once: the deferred self-sacrifice must leave Tama on the field.
	assistant.on_charge_cancelled()
	await get_tree().process_frame
	_expect(tama.current_zone == Card.Zone.FIELD and not tama.tapped,
		"cancelling the payment keeps Tama on the field and untaps it")
	_expect(stack.skill_activation_proxy == null, "and clears the ability proxy")
	_game.set("priority_holder", 1)
	GlobalVariables.refresh_mode()
	await field.begin_skill_activation(tama, 0)

	field.add_card_to_mana_conversion(mana_a)
	field.add_card_to_mana_conversion(mana_b)
	_expect(assistant.can_pay_cost(), "two untapped sources pay the declared X exactly")
	assistant.on_charge_complete()
	stack.confirm_skill_without_target_then_priority()

	_expect(tama.current_zone == Card.Zone.GRAVEYARD,
		"Tama is put into the Break Zone when the activation commits")
	_expect(stack.stack_length() == 1, "the ability itself is on the stack")
	if stack.stack_length() > 0:
		await stack.resolve_top_effect()

	_expect(played.is_on_field(), "the cost-2 Character from hand is played onto the field")
	_expect(not hand.cards.has(played), "and it leaves the hand")
	_expect(played.current_zone == Card.Zone.FIELD, "the played Character reports the FIELD zone")
	_expect(mana_a.tapped and mana_b.tapped, "both mana sources were spent")

	print("[Tama] %d checks | failures: %d" % [_checks, _fails])
	print("[Tama] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
