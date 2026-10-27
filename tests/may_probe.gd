extends Node
const EVENTS := preload("res://scripts/effects/events.gd")
## "YOU MAY" + block triggers + free play from hand — Squall 41, Leon 60, Vaan 63.
##
## The optional choice belongs to the INSTRUCTION, at resolution:
##   * `may` asks the effect's controller; `may_by: "opponent"` asks the other player (Leon);
##   * declining is a normal no-op, and `if_last_did_not_succeed` sees it;
##   * the confirm button carries the short prompt ("Deal 6000"), Refuse is the cancel button.
##
## Also covered: `when_blocks` / `when_blocked` fire when the block is DECLARED, and `play_from_hand` plays a card
## from hand for free through the same window used for the Break Zone.

const GAME_SCENE := preload("res://game.tscn")

const SQUALL := 41
const LEON := 60
const VAAN := 63
const TERRA := 47
const SNOW := 43
const CHOCOBO := 75
const DARK_KNIGHT := 55
const AURON := 1
const BACKUP_A := 31
const BACKUP_B := 32

var _checks: int = 0
var _fails: int = 0
var _game = null
var _field = null
var _stack = null
var _assistant = null
var _hand = null
var _opponent_hand = null
var _player: ScriptedAgent = null
var _opponent: ScriptedAgent = null


class ScriptedAgent extends Agent:
	var yes: bool = true
	var hand_pick: int = -1
	var prompts: Array = []

	func confirm_optional(_player_id: int, prompt: String) -> bool:
		await _settle()
		prompts.append(prompt)
		return yes

	func choose_hand_card_to_play(_owner_id: int, ids: Array, _filter: Dictionary) -> int:
		await _settle()
		if hand_pick >= 0:
			return hand_pick
		return int(ids[0]) if not ids.is_empty() else -1


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[May] ok   %s" % what)
	else:
		_fails += 1
		print("[May] FAIL %s" % what)


func _card(id: int, controller: String = "player") -> Card:
	for c in _field.get_all_cards():
		if c.id == id and c.controller == controller:
			return c
	return null


func _wait_for(check: Callable, frames: int = 300) -> bool:
	for _i in range(frames):
		await get_tree().process_frame
		if check.call():
			return true
	return false


func _choose_target(target: Card) -> void:
	# Code event targets open only after the stack object resolves.
	if _stack.stack_length() > 0 and GlobalVariables.get_player_mode() != GlobalVariables.Player_Mode.TARGET:
		_stack.resolve_top_effect()
	for _i in range(60):
		if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET:
			break
		await get_tree().process_frame
	_field.set_target_card(target)
	await get_tree().process_frame
	# A count > 1 session stays open until its last pick or until the player confirms early.
	if _field.targeting_picked.size() >= _field.targeting_count:
		_assistant.call("on_target_complete")
		await get_tree().process_frame


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {
		"player_field": [{"id": SQUALL}, {"id": VAAN}, {"id": LEON},
			{"id": BACKUP_A}, {"id": BACKUP_B}],
		"player_hand": [CHOCOBO, CHOCOBO],
		"opponent_field": [{"id": TERRA}, {"id": SNOW}],
		"opponent_hand": [DARK_KNIGHT, AURON],
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
	_hand = _game.get("hand")
	_opponent_hand = _game.get("opponent_hand")

	_player = ScriptedAgent.new()
	_player.bind(_game)
	_opponent = ScriptedAgent.new()
	_opponent.bind(_game)
	_game.set("player_agent", _player)
	_game.set("opponent_agent", _opponent)
	_game.set("_priority_lock", true)

	var squall: Card = _card(SQUALL)
	var vaan: Card = _card(VAAN)
	var leon: Card = _card(LEON)
	var terra: Card = _card(TERRA, "opponent")
	var backup_a: Card = _card(BACKUP_A)
	var backup_b: Card = _card(BACKUP_B)

	# --- A. the instruction gate itself, accept and decline ------------------------------------------------
	backup_a.tap()
	_player.yes = false
	var declined: Array[Instruction] = [Instruction.new("untap_targets", "game", [], "", true, "", "Activate?")]
	_game.set("_current_controller", "player")
	_game.set("_targets", [backup_a])
	_game.call("_execute_instructions", declined)
	await _wait_for(func(): return _player.prompts.size() >= 1)
	_expect(backup_a.tapped, "declining a may instruction does nothing")
	_expect(_player.prompts.has("Activate?"), "and the prompt reached the player's agent")

	_player.yes = true
	var accepted: Array[Instruction] = [Instruction.new("untap_targets", "game", [], "", true, "", "Activate?")]
	_game.set("_targets", [backup_a])
	_game.call("_execute_instructions", accepted)
	await _wait_for(func(): return not backup_a.tapped)
	_expect(not backup_a.tapped, "accepting it applies the effect")

	# --- B. Squall: when_blocked, may deal 6000 -----------------------------------------------------------
	_field.set_attacker(squall)
	_player.yes = true
	_field.execute_card_effect(squall, "when_blocked")
	await get_tree().process_frame
	_expect(_stack.stack_length() == 1, "Squall's when_blocked goes on the stack")
	await _choose_target(terra)
	_stack.resolve_top_effect()
	await _wait_for(func(): return terra.accumulated_damage >= 6000)
	print("[May] Terra damage after accepting: %d" % terra.accumulated_damage)
	_expect(terra.accumulated_damage == 6000, "the 6000 lands when the player accepts")
	_expect(_player.prompts.has("Deal 6000"), "the confirm button carried the short prompt")

	_player.yes = false
	_field.execute_card_effect(squall, "when_blocked")
	await get_tree().process_frame
	await _choose_target(terra)
	_stack.resolve_top_effect()
	await get_tree().create_timer(0.2).timeout
	print("[May] Terra damage after declining: %d" % terra.accumulated_damage)
	_expect(terra.accumulated_damage == 6000, "declining deals no further damage")

	# --- C. free play from hand (Vaan) --------------------------------------------------------------------
	_player.hand_pick = CHOCOBO
	_player.yes = true
	_game.set("_current_controller", "player")
	var hand_before: int = _hand.cards.size()
	_field.execute_card_effect(vaan, "when_enter_field")
	await get_tree().process_frame
	_stack.resolve_top_effect()
	var played: Card = await _wait_for_card_in_play(CHOCOBO)
	print("[May] hand %d -> %d, Chocobo on field=%s" % [hand_before, _hand.cards.size(), str(played != null)])
	_expect(played != null, "the chosen Wind Forward is played from hand")
	_expect(_hand.cards.size() == hand_before - 1, "and left the hand")
	_expect(played != null and played.current_zone == Card.Zone.FIELD, "and it is on the field, not still in hand")

	_player.yes = false
	var hand_before_decline: int = _hand.cards.size()
	_field.execute_card_effect(vaan, "when_enter_field")
	await get_tree().process_frame
	_stack.resolve_top_effect()
	await get_tree().create_timer(0.25).timeout
	_expect(_hand.cards.size() == hand_before_decline, "declining the free play keeps the card in hand")

	# --- D. Vaan attacks: activate up to 2 Backups --------------------------------------------------------
	backup_a.tap()
	backup_b.tap()
	_field.execute_card_effect(vaan, "when_attack")
	await get_tree().process_frame
	_stack.resolve_top_effect()
	for _i in range(60):
		if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET:
			break
		await get_tree().process_frame
	_expect(_field.get("targeting_count") == 2, "the attack trigger asks for up to 2 Backups")
	await _choose_target(backup_a)
	await _choose_target(backup_b)
	_stack.resolve_top_effect()
	await _wait_for(func(): return not backup_a.tapped and not backup_b.tapped)
	_expect(not backup_a.tapped and not backup_b.tapped, "both chosen Backups are activated")

	# --- E. Leon: the OPPONENT decides and plays from THEIR hand -------------------------------------------
	_opponent.hand_pick = DARK_KNIGHT
	_opponent.yes = true
	var player_prompts_before: int = _player.prompts.size()
	_game.set("_current_controller", "player")
	_field.execute_card_effect(leon, "when_enter_field")
	await get_tree().process_frame
	_stack.resolve_top_effect()
	var theirs: Card = await _wait_for_opponent_card(DARK_KNIGHT)
	print("[May] opponent dark knight on field=%s hand=%d" % [str(theirs != null), _opponent_hand.cards.size()])
	_expect(theirs != null, "the opponent's Character is played from their hand")
	_expect(not _opponent_hand.cards.has(theirs), "and leaves it")
	_expect(_opponent.prompts.has("Play a Character"), "the OPPONENT was the one asked")
	_expect(_player.prompts.size() == player_prompts_before, "the controller was not asked")

	_opponent.yes = false
	var opp_hand_before: int = _opponent_hand.cards.size()
	_field.execute_card_effect(leon, "when_enter_field")
	await get_tree().process_frame
	_stack.resolve_top_effect()
	await get_tree().create_timer(0.25).timeout
	_expect(_opponent_hand.cards.size() == opp_hand_before, "a refusal leaves the opponent's hand alone")

	# --- E2. Renzokuken: the skill grants ITSELF First Strike ------------------------------------------------
	var effect_obj = load("res://assets/effects/card_41.gd").new()
	var specs: Array = effect_obj.activated_abilities()
	_expect(specs.size() == 1 and specs[0].s_cost,
		"Renzokuken is a code S ability")
	_expect(specs.size() == 1 and specs[0].cost.has("氷"), "and it also costs ice mana")
	if specs.size() == 1:
		var ctx = squall.make_effect_context("activated_ability")
		await specs[0].run.call(ctx)
		await get_tree().process_frame
		_expect(squall.is_first_strike(), "resolving it gives Squall First Strike")

	# --- F. DECLARING the block fires when_blocked --------------------------------------------------------
	_field.reset_attacker()
	_field.set_attacker(squall)
	_game.set_blocker(terra)
	await get_tree().process_frame
	_expect(_stack.stack_length() >= 1, "declaring the block queues Squall's when_blocked")
	if _stack.stack_length() > 0:
		var top: Card = _stack.cards.back()
		_expect(top.effect_event == EVENTS.Event.BLOCKED or top.key_word_effect == "when_blocked",
			"and it is the when_blocked trigger")
	# it opened a target session; close it without resolving the effect
	_field.call("_on_assistant_target_cancel")

	# --- G. the real UI: Confirm and Refuse ---------------------------------------------------------------
	var local := LocalAgent.new()
	local.bind(_game)
	local.confirm_optional(1, "Deal 6000")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(_assistant.confirmButton.visible and _assistant.cancelButton.visible,
		"a may instruction shows Confirm AND Refuse")
	var confirm_label = _assistant.confirmButton.get_node("ButtonTextViewport/Control/CenterContainer/Label")
	_expect(confirm_label.text == "Deal 6000", "and the confirm button carries the prompt")
	# A click runs the Area3D callback directly (the button_pressed SIGNAL only pulses the button), so invoke it.
	var cancel_area = _assistant.cancelButton.get_node("Area3D")
	cancel_area.get("_on_press_callback").call()
	for _i in range(4):
		await get_tree().process_frame
	_expect(not _assistant.confirmButton.visible and not _assistant.cancelButton.visible,
		"and both are cleared once the player answers")

	print("[May] %d checks | failures: %d" % [_checks, _fails])
	print("[May] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()


func _wait_for_card_in_play(id: int) -> Card:
	for _i in range(300):
		await get_tree().process_frame
		for c in _field.get_all_cards():
			if c.id == id and c.is_on_field() and c.controller == "player":
				return c
	return null


func _wait_for_opponent_card(id: int) -> Card:
	for _i in range(300):
		await get_tree().process_frame
		for c in _field.get_all_cards():
			if c.id == id and c.is_on_field() and c.controller == "opponent":
				return c
	return null
