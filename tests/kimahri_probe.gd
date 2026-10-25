extends Node
## KIMAHRI 1-102H — Ronso Rage copies one Special Ability.
##
## Covers the copy slot, the two-S-ability choice, cost stripping, the one-use permission, overwrite, the stack
## snapshot, and end-of-turn expiry.

const GAME_SCENE := preload("res://game.tscn")
const TEST_GROUNDS := preload("res://scripts/test_grounds.gd")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field: Node = null
var _kimahri: Card = null
var _cloud: Card = null
var _no_skill: Card = null


class ChoiceAgent extends MockAgent:
	var last_skills: Array = []
	var pick: int = 1

	func choose_skill(_player_id: int, _card: Card, skills: Array, _usable: Array = []) -> int:
		last_skills = skills.duplicate()
		return pick


func _ready() -> void:
	await get_tree().process_frame
	MatchSetup.config = TEST_GROUNDS.config("clean")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	_game.player_agent = ChoiceAgent.new()
	_game.player_agent.bind(_game)
	_game.opponent_agent = MockAgent.new()
	_game.opponent_agent.bind(_game)
	_field = _game.field
	await get_tree().process_frame
	_kimahri = _place(102)
	_cloud = _place(182, "opponent")
	_no_skill = _place(12, "opponent")

	await _check_copy_and_choice()
	await _check_once_overwrite_and_snapshot()
	await _check_no_special_ability()
	await _check_copied_activation()
	await _check_end_of_turn_and_free_activation()

	print("[Kimahri] %d checks | failures: %d" % [_checks, _fails])
	print("[Kimahri] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Kimahri] ok   ", what)
	else:
		_fails += 1
		print("[Kimahri] FAIL ", what)


func _place(id: int, controller: String = "player") -> Card:
	var card: Card = _game.create_card(id, controller)
	_game.add_child(card)
	_field.play_card(card, controller == "opponent", false)
	return card


func _set_copy_target(kimahri: Card, target: Card) -> void:
	_game._current_source_card = kimahri
	_game._current_controller = "player"
	_game._targets = [target]
	await _game.copy_skill()


func _check_copy_and_choice() -> void:
	var kimahri: Card = _kimahri
	var cloud: Card = _cloud
	var squall: Card = _no_skill
	var criteria: Dictionary = {"is_type": "Forward", "controller": "opponent", "has_special_ability": true}
	_expect(cloud.matches_criteria(criteria, kimahri), "Cloud 182 is a legal Ronso Rage target")
	_expect(not squall.matches_criteria(criteria, kimahri),
		"Zack 12 has no Special Ability and cannot be chosen")
	_expect(kimahri.copied_skill.is_empty(), "Kimahri starts with no copied skill")

	var agent: ChoiceAgent = _game.player_agent
	await _set_copy_target(kimahri, cloud)
	_expect(not kimahri.copied_skill.is_empty(), "Ronso Rage installs a copied skill")
	_expect(kimahri.copied_skill_from == cloud.card_name, "the copied skill remembers its source")
	_expect(agent.last_skills.size() == 2, "Cloud offers both of its Special Abilities in the picker")
	_expect(kimahri.activation_skills().size() == 2,
		"Kimahri now has Ronso Rage plus the copied ability")
	var copied: Dictionary = kimahri.copied_skill
	_expect(not copied.has("cost") and not copied.has("s_cost") and not copied.has("tap"),
		"the copied definition has no CP, S, or Dull cost")
	_expect(bool(copied.get("free_activation", false)), "and is marked free to activate")
	_expect(bool(copied.get("special_ability", false)), "and still counts as a Special Ability")


func _check_once_overwrite_and_snapshot() -> void:
	var kimahri: Card = _kimahri
	var cloud: Card = _cloud
	await _set_copy_target(kimahri, cloud)
	var first_token: int = kimahri.copied_skill_token
	var first_text: String = str(kimahri.copied_skill.get("text", ""))
	_expect(first_token != 0 and not first_text.is_empty(), "a copied permission has an identity and text")

	# A second Ronso Rage replaces the slot, even before the first is used.
	await _set_copy_target(kimahri, cloud)
	_expect(kimahri.copied_skill_token != first_token, "a second copy creates a new permission token")
	_expect(not kimahri.copied_skill.is_empty(), "and the slot remains filled")

	# The stack copy must survive the source losing or replacing its copy.
	var index: int = kimahri.activation_skills().size() - 1
	_game.stack.call("add_skill_activation_proxy", kimahri, index)
	var proxy: Card = _game.stack.skill_activation_proxy
	_expect(proxy != null and not proxy.skill_def_override.is_empty(),
		"activating the copied skill snapshots its definition onto the stack")
	var snapshot_text: String = str(proxy.skill_def_override.get("text", "")) if proxy != null else ""
	kimahri.clear_copied_skill()
	_expect(kimahri.copied_skill.is_empty(), "clearing the source clears its copied slot")
	_expect(proxy != null and str(proxy.skill_def_override.get("text", "")) == snapshot_text,
		"but the stack copy still has its own definition")
	_game.stack.call("_clear_skill_proxy")


func _check_no_special_ability() -> void:
	var kimahri: Card = _kimahri
	var squall: Card = _no_skill
	kimahri.clear_copied_skill()
	await _set_copy_target(kimahri, squall)
	_expect(kimahri.copied_skill.is_empty(), "copying a card with no S ability does nothing")
	_expect(not _game._last_action_succeeded, "and reports that the copy failed")


func _check_copied_activation() -> void:
	var agent: ChoiceAgent = _game.player_agent
	agent.pick = 0
	_kimahri.clear_copied_skill()
	await _set_copy_target(_kimahri, _cloud)
	_expect(not _kimahri.copied_skill.is_empty(), "setup: the free copy is installed")
	_game.priority_holder = 1
	GlobalVariables.set_base_mode(GlobalVariables.Player_Mode.FREE)
	var copied_index: int = _kimahri.activation_skills().size() - 1
	_field.begin_skill_activation(_kimahri, copied_index)
	_expect(_game.stack.skill_activation_proxy != null,
		"the copied ability puts an activation proxy on the stack")
	_expect(_game.stack.cards.size() == 1, "and the proxy is visible on the stack")
	_game.stack.confirm_skill_without_target_then_priority()
	_expect(_kimahri.copied_skill.is_empty(), "committing the free copy consumes its permission")
	await _game.stack.resolve_top_effect()
	_expect(_cloud.accumulated_damage >= 4000,
		"the copied Meteorain still applies its effect (Cloud took %d)" % _cloud.accumulated_damage)


func _check_end_of_turn_and_free_activation() -> void:
	var kimahri: Card = _kimahri
	var cloud: Card = _cloud
	kimahri.clear_copied_skill()
	await _set_copy_target(kimahri, cloud)
	_expect(not kimahri.copied_skill.is_empty(), "setup: a copied skill is present")
	kimahri.tapped = true
	_game.priority_holder = 1
	GlobalVariables.set_base_mode(GlobalVariables.Player_Mode.FREE)
	_expect(_field.can_activate_now(kimahri),
		"the copied skill is offered even while Kimahri is tapped (no Dull cost)")
	kimahri.turn_end()
	_expect(kimahri.copied_skill.is_empty(), "the copied skill expires at end of turn")
	_expect(kimahri.activation_skills().size() == 1,
		"leaving only Kimahri's printed Ronso Rage")
