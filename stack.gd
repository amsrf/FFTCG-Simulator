extends Node3D
class_name Stack

var cards = []
var card_width = GlobalVariables.get_card_width() * 2;
var card_spacing = -0.2
var player_mode = GlobalVariables.get_player_mode();
var start_x: float = 0.0
var casting_card: Card
## Stack copy for skill activation. The node exists early for UI; the activation is not
## de facto committed until commit_skill_activation_costs_if_pending runs (after final Confirm).
var skill_activation_proxy: Card = null
## While true, mana/hand discard and JSON tap on source are deferred until stack commit (final Confirm).
var skill_mana_deferred_until_target_confirm: bool = false
## Summon being cast from hand. The card stays in hand until the cost is paid
## and targets are chosen; only then does it enter the stack.
var summon_casting_card: Card = null
## While true, summon mana payment is deferred until the target is confirmed.
var summon_mana_deferred_until_target_confirm: bool = false
## True while an effect resolution is still running (it may await a modal).
var resolution_pending: bool = false
## Special ability (S) cost state: a card sharing a name with the source,
## selected from hand and discarded at the final skill commit.
var s_cost_active: bool = false
var s_cost_source: Card = null
var s_cost_skill_index: int = -1
var s_cost_selected_card: Card = null
@onready var field: Field = get_parent().get_node("Field") as Field
@onready var hand: Hand = get_tree().current_scene.get_node("Player/Hand") as Hand
@onready var assistant: Assistant = get_parent().get_node("Assistant") as Assistant
@onready var card_scene = preload("res://Card.tscn")

signal execute_card_effect(card:Card)
signal request_priority()
## Emitted by the game when a stack effect has fully finished resolving.
signal resolution_complete

func _ready() -> void:
	assistant.choose_card_finished.connect(_on_choose_card_finished)

func calculate_total_width():
	return (cards.size() * card_width) + ((cards.size() - 1) * card_spacing)
	
func stack_length() -> int:
	return len(cards)	
func update_card_positions():
	var total_width = calculate_total_width()
	start_x = -total_width / 2 + card_width / 2

	for i in range(cards.size()):
		var card = cards[i]
		card.index = i
		card.rotation = Vector3.ZERO
		animate_card(card, calculate_card_position(i)) # Position relative to the Hand
		
func calculate_card_position(i):
	var x_offset = start_x + i * (card_width + card_spacing)
	var y_offset = (i)*0.001
	return Vector3(x_offset, y_offset, 0)
	
func animate_card(card, target_position):
	# Create a Tween to animate the card's movement
	var tween = create_tween()
	tween.set_parallel(true) 
	tween.tween_property(card, "position", target_position, 0.3)
	tween.tween_property(card, "scale", Vector3.ONE*1.4, 0.3)
	
	
func add_card_to_tree(card):
	cards.append(card)
	card.index = cards.size()-1
	var trans = card.global_transform
	card.reparent(self,false)
	card.global_transform = trans
	
func add_created_card_to_tree(card:Card):
	cards.append(card)
	card.index = cards.size()-1
	var trans = card.global_transform
	add_child(card)
	if(card.key_word_effect):
		print("Adding effect to the stack")
		#GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.INSTANT_SPEED_TIME)
	card.global_transform = trans
	
func cast_card():
	if casting_card.type == 'Summon':
		# Summons stay on the stack and resolve as effects. Resolution
		# (game._on_stack_execute_card_effect) sends them to the graveyard.
		casting_card.key_word_effect = "when_cast"
	else:
		# Forwards/Backups are played directly to the field.
		cards.pop_back()
		field.play_card(casting_card)
	
	
func pop_stack():
	return cards.pop_back()

func _on_assistant_charge_complete() -> void:
	if summon_casting_card != null:
		_continue_summon_after_mana(summon_casting_card)
		return
	if casting_card:
		cast_card()
		casting_card = null
	elif skill_activation_proxy != null:
		field.continue_skill_activation_after_mana(skill_activation_proxy)

func _continue_summon_after_mana(card: Card) -> void:
	# Payment is only committed when the summon actually enters the stack
	# (after target confirmation). If the summon needs a target, target
	# selection happens now and may still be cancelled.
	var criteria: Dictionary = card.get_cast_target_criteria()
	if criteria.is_empty():
		_commit_summon_to_stack()
		request_priority.emit()
		return
	field.request_target(criteria, card, true, "Summon")

func _commit_summon_to_stack() -> void:
	if summon_casting_card == null:
		return
	# Target is confirmed: finalize mana payment now (discard hand mana,
	# tap backup mana), then put the summon on the stack.
	field.apply_deferred_skill_mana_payment()
	hand.apply_deferred_skill_mana_payment()
	summon_mana_deferred_until_target_confirm = false

	var card: Card = summon_casting_card
	summon_casting_card = null
	card.key_word_effect = "when_cast"
	card.effect_kind = "Summon"
	hand.finish_summon_cast(card)
	# The card is already parked on the stack node; now it legally enters
	# the stack list and resolves as a normal stack object.
	cards.append(card)
	card.index = cards.size() - 1
	update_card_positions()


func begin_triggered_ability(source: Card, keyword: String) -> void:
	## Triggered auto-abilities go on the stack during rules processing,
	## before a player receives priority. Any "may" choice (e.g. Auron's
	## "play a Fire Backup") is made when the ability RESOLVES.
	if source == null or not source.card_effects.has(keyword):
		return
	_add_triggered_effect_to_stack(source, keyword)
	request_priority.emit()

func _add_triggered_effect_to_stack(source: Card, keyword: String) -> void:
	create_card(source.id, source.controller, keyword, source)
	update_card_positions()

func _mark_resolution_complete() -> void:
	resolution_pending = false
	resolution_complete.emit()

## Special ability (S) cost step 1: choose a card in hand that shares a name
## with the source. The actual discard is deferred until the skill commits.
func begin_s_cost_selection(source: Card, skill_index: int) -> void:
	var criteria: Dictionary = {"is_named": source.card_name}
	if not hand.has_card_matching_criteria(criteria):
		# Cannot pay the S cost: abort the whole activation.
		_clear_skill_proxy()
		GlobalVariables.reset_to_default_phase_player_mode()
		assistant.show_pass_priority_button()
		return
	s_cost_active = true
	s_cost_source = source
	s_cost_skill_index = skill_index
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND)
	hand.begin_choose_card(criteria)
	assistant.show_choose_card_buttons("Discard", "Cancel")

func _on_choose_card_finished(play: bool) -> void:
	if not s_cost_active:
		return
	s_cost_active = false
	var chosen: Card = hand.selected_card_for_effect
	hand.end_choose_card()
	assistant.hide_buttons()
	GlobalVariables.reset_to_default_phase_player_mode()
	assistant.show_pass_priority_button()

	if not play or chosen == null:
		_clear_skill_proxy()
		return

	s_cost_selected_card = chosen
	# S cost chosen: proceed to the regular mana payment step.
	var def: Dictionary = s_cost_source.card_effects["skill"][s_cost_skill_index]
	field.card_activated_ability.emit(def.get("cost", {}))

func add_skill_activation_proxy(source: Card, skill_index: int) -> bool:
	## Physical stack object for UI (pay + target). Costs apply later at de facto stack commit.
	if skill_activation_proxy != null:
		return false
	var proxy: Card = card_scene.instantiate()
	proxy.initialize(source.id, source.controller)
	proxy.skill_activation_index = skill_index
	proxy.key_word_effect = "skill"
	proxy.effect_source = source
	proxy.effect_kind = "Ability"
	skill_activation_proxy = proxy
	skill_mana_deferred_until_target_confirm = true
	add_created_card_to_tree(proxy)
	update_card_positions()
	return true

func _apply_skill_source_tap_from_proxy() -> void:
	## Part of stack commit: JSON "tap" is a cost, not tied to resolution (instructions run in game._on_stack_execute_card_effect).
	if skill_activation_proxy == null:
		return
	var src: Card = skill_activation_proxy.effect_source
	var idx: int = skill_activation_proxy.skill_activation_index
	if src == null or not src.is_inside_tree():
		return
	if not "skill" in src.card_effects:
		return
	var skills: Array = src.card_effects["skill"]
	if idx < 0 or idx >= skills.size():
		return
	var def: Dictionary = skills[idx]
	if def.get("tap", false):
		src.tap()

## Skill stack commit: activation is legally complete (costs paid, target on proxy if required).
## Resolution (execute instructions) happens later in resolve_top_effect -> game._on_stack_execute_card_effect.
func commit_skill_activation_costs_if_pending() -> void:
	if not skill_mana_deferred_until_target_confirm:
		return
	field.apply_deferred_skill_mana_payment()
	hand.apply_deferred_skill_mana_payment()
	_apply_skill_source_tap_from_proxy()
	# Special ability (S) cost: discard the card chosen from hand.
	if s_cost_selected_card != null:
		hand.discard_card(s_cost_selected_card)
		s_cost_selected_card = null
	skill_mana_deferred_until_target_confirm = false

func _clear_skill_proxy() -> void:
	s_cost_active = false
	s_cost_source = null
	s_cost_skill_index = -1
	s_cost_selected_card = null
	if skill_activation_proxy == null:
		return
	var p = skill_activation_proxy
	skill_activation_proxy = null
	skill_mana_deferred_until_target_confirm = false
	cards.erase(p)
	if is_instance_valid(p):
		p.queue_free()
	update_card_positions()


func _on_hand_charge_start(card: Card) -> void:
	if card.type == 'Summon':
		# Park the summon visually on the stack while it is being cast. It is
		# NOT in the stack.cards list yet, so it is not legally on the stack
		# until payment and target are committed.
		summon_casting_card = card
		summon_mana_deferred_until_target_confirm = true
		var trans = card.global_transform
		card.reparent(self, false)
		card.global_transform = trans
		card.rotation = Vector3.ZERO
		update_card_positions()
		animate_card(card, calculate_card_position(cards.size()))
		return
	casting_card = card
	add_card_to_tree(card)
	update_card_positions()


func _on_assistant_charge_cancelled() -> void:
	if skill_activation_proxy != null:
		_clear_skill_proxy()
		return
	if summon_casting_card != null:
		summon_casting_card = null
		summon_mana_deferred_until_target_confirm = false
		return
	if cards.is_empty():
		return
	var card = cards.pop_back()
	if card.is_effect_card():
		card.queue_free()
	update_card_positions()


func _on_field_add_card_effect_to_stack(card_id: int, keyword: String, source: Card) -> void:
	create_card(card_id, source.controller, keyword, source)
	update_card_positions()

func create_card(id, controller, keyword, source) -> Card:
	var card: Card = card_scene.instantiate()  
	card.initialize(id,controller)
	card.key_word_effect = keyword
	card.effect_source = source
	card.effect_kind = "Ability"
	add_created_card_to_tree(card)
	update_card_positions()
	
	return card

func resolve_top_effect() -> void:
	## Stack resolution: run effect instructions only; costs were applied at
	## commit for skills. The effect handler may await a modal (e.g. Auron's
	## "may play a Backup" choice), so resolution waits for the game to signal
	## resolution_complete before continuing.
	if cards.is_empty():
		return
	var card: Card = cards.pop_back()
	if card == skill_activation_proxy:
		skill_activation_proxy = null
		skill_mana_deferred_until_target_confirm = false
	print('Resolve ', card.card_name)
	resolution_pending = true
	execute_card_effect.emit(card)
	if resolution_pending:
		await resolution_complete
	resolution_pending = false
	if len(cards) == 0:
		GlobalVariables.reset_to_default_phase_player_mode()
	
func process_next_effect():
	await get_tree().create_timer(1.0).timeout
	var card: Card = cards.pop_back()
	execute_card_effect.emit(card)
	if len(cards) > 0:
		process_next_effect()
	


func _on_field_request_target_confirmation(target_card: Card, _allow_cancel: bool = false) -> void:
	if summon_casting_card != null:
		summon_casting_card.effect_target = target_card
		return
	var effect_card: Card = cards[-1]
	effect_card.effect_target = target_card

func _on_assistant_target_complete() -> void:
	if summon_casting_card != null:
		_commit_summon_to_stack()
		request_priority.emit()
		return
	commit_skill_activation_costs_if_pending()
	request_priority.emit()

func confirm_skill_without_target_then_priority() -> void:
	commit_skill_activation_costs_if_pending()
	request_priority.emit()

func _on_assistant_target_cancel() -> void:
	## Only activated-ability (skill) flow may abort and remove the stack copy; ETB is mandatory.
	if skill_activation_proxy != null:
		_clear_skill_proxy()
	elif summon_casting_card != null:
		# Payment was deferred and is now refunded: nothing is discarded or
		# tapped, and the summon returns to hand without entering the stack.
		summon_casting_card = null
		summon_mana_deferred_until_target_confirm = false
		hand.cancel_summon_cast()
