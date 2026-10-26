extends Node
## Code-defined activated abilities: activation, target-at-activation, stack snapshot, handler.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


class TargetAgent extends Agent:
	var wanted: Card = null

	func choose_target(_owner_id: int, _source: Card, _criteria: Dictionary) -> void:
		if wanted != null and is_instance_valid(wanted) and wanted.is_valid_target:
			game.field.set_target_card(wanted)
		game.assistant.on_target_complete()


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Ability] ok   %s" % what)
	else:
		_fails += 1
		print("[Ability] FAIL %s" % what)


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

	# Ramza 145: 《Dull》: choose a Backup, activate it. Free mana cost, so the activation goes straight to targeting.
	var ramza: Card = _make(145, "player")
	var backup: Card = _make(31, "player")
	backup.tap()
	var spec = ramza.activation_ability_spec(0)
	_expect(spec != null, "145 exposes an AbilitySpec, not only a JSON dictionary")
	_expect(ramza.activation_skills().size() == 1, "and exactly one activated ability")
	_expect(str(ramza.activation_skill(0).get("text", "")).begins_with("《Dull》"),
		"the activation dictionary carries the display text")

	var agent := TargetAgent.new()
	agent.bind(_game)
	agent.wanted = backup
	_game.set("player_agent", agent)
	_game.set("priority_holder", 1)
	GlobalVariables.refresh_mode()
	field.begin_skill_activation(ramza, 0)

	# The activation taps Ramza, asks for the Backup, and commits the proxy. Poll until the proxy is on the stack.
	var guard: int = 0
	while stack.stack_length() == 0 and guard < 60:
		await get_tree().create_timer(0.05).timeout
		guard += 1
	_expect(ramza.tapped, "the Dull cost is paid at activation")
	_expect(stack.stack_length() == 1, "the ability proxy is on the stack")
	if stack.stack_length() > 0:
		await stack.resolve_top_effect()
	_expect(not backup.tapped, "the ability's handler activates the chosen Backup")

	# Vincent 94: S cost (discard a same-named card), Dull, choose a Forward, deal 6000. Cost is otherwise free, so
	# after the S pick the activation goes straight to targeting.
	var vincent: Card = _make(94, "player")
	var victim: Card = _make(41, "opponent")
	var duplicate: Card = _game.call("create_card", 94, "player")
	_game.add_child(duplicate)
	_game.get("hand").add_card(duplicate)
	var hand = _game.get("hand")
	agent.wanted = victim
	_game.set("player_agent", agent)
	_game.set("priority_holder", 1)
	GlobalVariables.refresh_mode()
	field.begin_skill_activation(vincent, 0)
	hand.toggle_effect_card_selection(duplicate)
	stack.call("_on_choose_card_finished", true)
	guard = 0
	while stack.stack_length() == 0 and guard < 60:
		await get_tree().create_timer(0.05).timeout
		guard += 1
	_expect(stack.stack_length() == 1, "the S-cost ability reaches the stack")
	if stack.stack_length() > 0:
		await stack.resolve_top_effect()
	_expect(victim.accumulated_damage == 6000, "Vincent's Berserk Dance deals 6000 to the chosen Forward")
	_expect(not hand.cards.has(duplicate), "the S cost discarded the same-named card")

	# 66 Dancer: a no-target, no-mana ability. After the tap it asks for the normal Confirm, then the handler damages
	# every opponent Forward.
	var dancer: Card = _make(66, "player")
	var f1: Card = _make(41, "opponent")
	var f2: Card = _make(43, "opponent")
	_game.set("priority_holder", 1)
	GlobalVariables.refresh_mode()
	field.begin_skill_activation(dancer, 0)
	stack.confirm_skill_without_target_then_priority()
	var guard2: int = 0
	while stack.stack_length() == 0 and guard2 < 60:
		await get_tree().create_timer(0.05).timeout
		guard2 += 1
	if stack.stack_length() > 0:
		await stack.resolve_top_effect()
	_expect(f1.accumulated_damage == 1000 and f2.accumulated_damage == 1000,
		"Dancer's code ability damages every opponent Forward")

	# Multi-ability descriptors are exposed in order, with their own texts.
	var firion_effect = load("res://assets/effects/card_22.gd").new()
	_expect(firion_effect.activated_abilities().size() == 4, "Firion exposes four activated abilities")
	var yshtola_effect = load("res://assets/effects/card_84.gd").new()
	_expect(yshtola_effect.activated_abilities().size() == 2, "Y'shtola exposes two activated abilities")

	print("[Ability] %d checks | failures: %d" % [_checks, _fails])
	print("[Ability] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
