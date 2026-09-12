extends Node3D
class_name Field


const CARD_CHARGE = 1
var front_cards: Array[Card] = []
var back_cards: Array[Card] = []
var opponent_front_cards: Array[Card] = []
var opponent_back_cards: Array[Card] = []
var target_card: Card = null
var source_card: Card = null
var attacker_card: Card = null
## The blocker declared for the current combat. Persisted on the Field because
## Game's transient `_current_blocker_card` is cleared as soon as the blocker's
## instructions finish, which is before DAMAGE_RESOLUTION reads it.
var blocker_card: Card = null
var arrow: BallisticArrow
## If false (e.g. ETB), targeting cannot be cancelled and stack effect is mandatory.
var targeting_allow_cancel: bool = false
signal selected_cards_for_mana_has_changed(amount:int, element:String)
signal add_card_effect_to_stack(card_id:int, keyword:String, source:Card)
signal request_target_confirmation(target_card: Card, allow_cancel: bool)
signal attacker_changed
signal blocker_changed
signal card_activated_ability(cost:Dictionary)
## Read-through to the match's phase (owned by `Game`); Field keeps no copy.
var phase: GlobalVariables.Phase:
	get:
		return get_parent().phase
@export var selected_cards_for_mana_conversion: Array[Card] = []
@onready var TargetScene = preload("res://target.tscn")
@onready var ballistic_arrow_scene = preload("res://ballistic_arrow.tscn")
@onready var assistant: Assistant = get_parent().get_node("Assistant")
@onready var stack: Stack = get_parent().get_node("Stack") as Stack
@onready var hand: Hand = get_parent().get_node("Player/Hand") as Hand

class AuraValue:
	var method: String
	var targets: Dictionary  # Changed from Array[String] to Dictionary
	var value: int

	func _init(p_method: String, p_targets: Dictionary, p_value: int = 0):
		method = p_method
		targets = p_targets
		value = p_value
		

var _auras: Dictionary[int, AuraValue] = {}
func add_aura(aura: Dictionary, id:int):
	var value = aura.get('value', 0)
	var aura_value = AuraValue.new(
	aura['method'],
	aura['targets'], 
	value,
)
	_auras[id] = aura_value
	
func activate_aura_in_field(aura:AuraValue):
	var all_cards: Array[Card] = get_all_cards()
	for card:Card in all_cards:
		add_aura_to_card(aura,card)

func add_aura_to_card(aura: AuraValue, card: Card):
	if card.does_card_match_target(aura.targets):
		if aura.method == 'power_change':
			# -1 = permanent modifier (does not expire at end of turn).
			card.power_change(aura.value, -1)
				
func add_all_auras_to_card(card:Card):
	for aura in _auras.values():
		add_aura_to_card(aura,card)		

func add_card_to_mana_conversion(card:Card):
	if  not selected_cards_for_mana_conversion.has(card):
		selected_cards_for_mana_conversion.push_back(card)
	# Owns the marker, so an agent paying a cost gets the same feedback as a click.
	card.show_mana_crystal()
	selected_cards_for_mana_has_changed.emit(1,card.element)
	
func remove_card_from_mana_conversion(card:Card):
	if selected_cards_for_mana_conversion.has(card):
		selected_cards_for_mana_conversion.erase(card)
	card.clear_mana_crystal()
	selected_cards_for_mana_has_changed.emit(-1,card.element)


func play_card(card, is_opponent: bool = false, animate = true) -> void:
	var trans = card.global_transform
	card.reparent(self, false)
	card.position = Vector3.ZERO
	card.global_transform = trans
	
	var target_node
	var target_array
	
	if card.type == 'Forward':
		target_array = opponent_front_cards if is_opponent else front_cards
		target_node = $OpponentFrontrowCard if is_opponent else $FrontrowCard
	else:  # Backup
		target_array = opponent_back_cards if is_opponent else back_cards
		target_node = $OpponentBackrowCard if is_opponent else $BackrowCard
	
	# Add card to appropriate array
	var n = target_array.size()
	target_array.append(card)
	register_conditional_effects(card)
	recompute_conditional_power()
	
	# Calculate position
	var target_position = target_node.position
	if n % 2 == 0:
		target_position -= (n/2) * Vector3(0.8, 0, 0)
	else:
		target_position += ((n+1)/2) * Vector3(0.8, 0, 0)
	
	if animate:
		var tween = create_tween().set_ease(Tween.EASE_OUT)
		tween.set_parallel(true)
		tween.tween_property(card, "position", target_position + Vector3(0, 0.8, 0), 0.3).set_delay(0.3)
		tween.set_trans(Tween.TRANS_BACK)
		tween.tween_property(card, "scale", Vector3.ONE*1.4, 0.5)
		tween.set_parallel(false)
		tween.tween_property(card, "position", target_position + Vector3(0, 2, 0), 0.6).set_delay(0.2)
		tween.tween_property(card, "position", target_position, 0.4)
		
		# Execute ETB after the ENTIRE tween sequence finishes
		tween.finished.connect(_on_tween_finished.bind(card))
	else:
		card.position = target_position
		card.scale = Vector3.ONE * 1.2
		GlobalVariables.refresh_mode()
	
func _on_tween_finished(card: Card):
	GlobalVariables.refresh_mode()
	#var instructions = card.create_instruction_from_json(card.card_effects['when_enter_field']['instructions'])
	execute_card_effect(card,"when_enter_field")
	#request_target_confirmation.emit()
	
func execute_card_attack():
	attacker_card.tap()
	execute_card_effect(attacker_card,'when_attack')
	
func end_phase_cleanup():
	# End Phase cleanup: remove all damage from every card on the field and
	# expire "until end of turn" effects. (No end-of-turn priority window
	# exists yet, so this runs immediately on entering the End Phase.)
	for c in get_all_cards():
		c.turn_end()
func try_activate_from_field(card: Card) -> void:
	if not "skill" in card.card_effects:
		return
	var skills: Array = card.card_effects["skill"]
	if skills.is_empty():
		return
	if skills.size() == 1:
		begin_skill_activation(card, 0)
	else:
		card.show_actions()

func begin_skill_activation(card: Card, skill_index: int = 0) -> void:
	var mode = GlobalVariables.get_player_mode()
	if mode != GlobalVariables.Player_Mode.FREE and mode != GlobalVariables.Player_Mode.INSTANT_SPEED_TIME:
		return
	if card.controller != "player":
		return
	if card.tapped:
		return
	if not "skill" in card.card_effects:
		return
	var skills: Array = card.card_effects["skill"]
	if skill_index < 0 or skill_index >= skills.size():
		return
	if not stack.add_skill_activation_proxy(card, skill_index):
		return
	assistant.clear_payment_accumulator()
	var def: Dictionary = skills[skill_index]
	if def.get("s_cost", false):
		# Special ability (S): first discard a card sharing a name with the
		# source, then the regular mana payment step follows.
		stack.begin_s_cost_selection(card, skill_index)
		return
	var cost: Dictionary = def.get("cost", {})
	card_activated_ability.emit(cost)

func continue_skill_activation_after_mana(_proxy: Card) -> void:
	if _proxy == null or _proxy.effect_source == null:
		return
	var src: Card = _proxy.effect_source
	var idx: int = _proxy.skill_activation_index
	if idx < 0 or not "skill" in src.card_effects:
		return
	var skills: Array = src.card_effects["skill"]
	if idx >= skills.size():
		return
	var def: Dictionary = skills[idx]
	var choose_target = def.get("choose_target", null)
	if choose_target:
		request_target(choose_target, src, true, "Ability")
	else:
		GlobalVariables.refresh_mode()
		assistant.generate_confirm_button(func(): stack.confirm_skill_without_target_then_priority())
	
func execute_card_effect(card,keyword):
	if( not card.is_key_word_in_card_effect(keyword)):
		return
	add_card_effect_to_stack.emit(card.id,keyword,card)
	# Most elegant single-line solution
	var choose_target_criteria = card.card_effects.get(keyword, {}).get('choose_target', null)
	
	if choose_target_criteria:
		request_target(choose_target_criteria, card, false, "Ability")
func TEST_get_front_cards():
	return opponent_front_cards
func get_all_cards() -> Array[Card]:
	return front_cards + back_cards + opponent_front_cards + opponent_back_cards
func get_all_cards_from_player():
	return front_cards + back_cards

func get_front_cards_for(controller_name: String) -> Array[Card]:
	# Forwards of one side. Agents use this for attack / block decisions.
	return front_cards if controller_name == "player" else opponent_front_cards

func get_back_cards_for(controller_name: String) -> Array[Card]:
	# Backups of one side: the AI taps these to pay card costs.
	return back_cards if controller_name == "player" else opponent_back_cards

func untap_all_cards():
	for card in get_all_cards_from_player():
		card.untap()

func untap_cards_for(controller_name: String) -> void:
	# Active Phase untaps only the turn player's cards.
	var cards: Array[Card] = (front_cards + back_cards) if controller_name == "player" else (opponent_front_cards + opponent_back_cards)
	for card in cards:
		card.untap()
		
func request_target(targeting_criteria, card: Card, allow_cancel: bool = false, source_kind: String = ""):
	# Always start a targeting session fresh. Leftover target_card from a
	# previous session made set_target_card() ignore clicks (stuck UI).
	targeting_allow_cancel = allow_cancel
	target_card = null
	source_card = card
	if arrow:
		arrow.queue_free()
		arrow = null
	reset_targets()
	print("[Targeting] request_target source=%s criteria=%s" % [card.card_name, targeting_criteria])
	GlobalVariables.push_modal(GlobalVariables.Player_Mode.TARGET)
	set_viable_targets(targeting_criteria, card, source_kind)
	var ballistic_arrow = ballistic_arrow_scene.instantiate()
	arrow = ballistic_arrow
	add_child(ballistic_arrow)
	ballistic_arrow.set_is_aiming(true, card.global_position)
	if allow_cancel:
		assistant.prepare_targeting_phase_cancel()
	# A non-local owner resolves targeting through its agent instead of waiting
	# for clicks nobody will make (which would hang the turn).
	var owner_id: int = 1 if card.controller == "player" else 2
	var agent: Agent = get_parent().agent_for(owner_id)
	if agent != null and not (agent is LocalAgent):
		agent.choose_target(owner_id, card, targeting_criteria)

func set_target_card(card: Card):
	# A click only counts when the candidate is a legally valid target.
	# is_valid_target is set by set_viable_targets() (criteria + protection).
	if not card.is_valid_target:
		push_warning("[Targeting] %s is not a valid target" % card.card_name)
		return
	if target_card != null:
		push_warning("[Targeting] target already selected (%s); ignoring click on %s" % [target_card.card_name, card.card_name])
		return
	target_card = card
	print("[Targeting] target selected: ", card.card_name)
	arrow.lock_arc(card.get_global_center())
	request_target_confirmation.emit(target_card, targeting_allow_cancel)
	
func set_viable_targets(target_criteria, source: Card = null, source_kind: String = ""):
	for card in get_all_cards():
		var is_targetable = _card_matches_criteria(card, target_criteria, source, source_kind)
		card.set_valid_target(is_targetable)
		if is_targetable:
			# Create and position target above card
			var target: Node3D = TargetScene.instantiate()
			target.add_to_group("target_indicators")
			self.add_child(target)  # Assuming you have a Target scene/class
			target.position = card.position + Vector3(0,0,0.4)
			target.rotation_degrees = Vector3(-100,0,0)
			target.scale = Vector3.ONE * 0.5

func has_viable_target(target_criteria, source: Card = null, source_kind: String = "") -> bool:
	# Used before casting a Summon: a targeted Summon cannot be cast unless
	# at least one legal target exists on the field.
	for card in get_all_cards():
		if _card_matches_criteria(card, target_criteria, source, source_kind):
			return true
	return false

func _card_matches_criteria(card: Card, target_criteria: Dictionary, source: Card = null, source_kind: String = "") -> bool:
	# Legality has two parts: the effect's choose_target criteria (properties of
	# the candidate) and the candidate's own protection against this source.
	# source_kind overrides the source card's own kind, because ability targeting
	# is requested with the field card, which carries no effect_kind.
	if not card.matches_criteria(target_criteria):
		return false
	return card.can_be_chosen_by(source, source_kind)
		
func reset_targets():
	for card in get_all_cards():
		card.is_valid_target = false
	get_tree().call_group("target_indicators", "queue_free")

func remove_card(card):
	unregister_conditional_effects(card)
	front_cards.erase(card)
	back_cards.erase(card)
	opponent_front_cards.erase(card)
	opponent_back_cards.erase(card)
	recompute_conditional_power()

## Conditional continuous effects ("if you control X, this gains power").
## Re-evaluated only when the field composition changes: play_card/remove_card.
var _conditional_effects: Array[Dictionary] = []

func register_conditional_effects(card: Card) -> void:
	if "conditional_power" in card.card_effects:
		for effect in card.card_effects["conditional_power"]:
			_conditional_effects.append({
				"source": card,
				"condition": effect.get("condition", {}),
				"value": int(effect.get("value", 0)),
			})

func unregister_conditional_effects(card: Card) -> void:
	_conditional_effects = _conditional_effects.filter(func(e): return e["source"] != card)
	if card.current_conditional_bonus != 0:
		card.power -= card.current_conditional_bonus
		card.current_conditional_bonus = 0
		if card.power_label:
			card.power_label.changePower(card.power)

func recompute_conditional_power() -> void:
	for effect in _conditional_effects:
		var source: Card = effect["source"]
		if source == null or not is_instance_valid(source) or not source.is_inside_tree():
			continue
		var desired: int = int(effect["value"]) if _condition_met(effect["condition"]) else 0
		if desired != source.current_conditional_bonus:
			source.power += desired - source.current_conditional_bonus
			source.current_conditional_bonus = desired
			if source.power_label:
				source.power_label.changePower(source.power)

func _condition_met(condition: Dictionary) -> bool:
	if condition.is_empty():
		return false
	for card in get_all_cards():
		if card.matches_criteria(condition):
			return true
	return false
	
func get_breakable_cards():
	# Forwards whose accumulated damage is equal to or greater than their
	# current power. A card at 0 power is handled separately (it is put into
	# the Graveyard, not broken).
	var ans = []
	for card in (front_cards + opponent_front_cards):
		if card.has_zero_power():
			continue
		if card.is_broken():
			ans.append(card)
	return ans

func get_zero_power_cards():
	# Forwards whose current power is 0 or less. These are put into the
	# Graveyard without triggering break effects.
	var ans = []
	for card in (front_cards + opponent_front_cards):
		if card.has_zero_power():
			ans.append(card)
	return ans

func _tap_selected_cards():
	for c in selected_cards_for_mana_conversion:
		c.tap()
		
func set_attacker(card:Card):
	if(attacker_card == null):
		attacker_card = card
		attacker_card.set_attacker_status(true)
	elif(attacker_card == card):
		attacker_card.set_attacker_status(false)
		attacker_card = null
	elif(attacker_card != card):
		attacker_card.set_attacker_status(false)
		attacker_card = card
		attacker_card.set_attacker_status(true)
	attacker_changed.emit()
func reset_attacker():
	attacker_card = null

## Select/deselect a blocker for the current combat (human input only).
## Game.set_blocker() is what *declares* it (via the set_blocker instruction).
func set_blocker_card(card: Card) -> void:
	if card == null or card.controller != "player" or not card.can_attack():
		return
	if blocker_card == card:
		card.set_blocker_status(false)
		blocker_card = null
	else:
		if blocker_card != null and is_instance_valid(blocker_card):
			blocker_card.set_blocker_status(false)
		blocker_card = card
		card.set_blocker_status(true)
	blocker_changed.emit()

func reset_blocker():
	# The blocker may have broken in the clash, so only clear the marker while it
	# is still a card on the field.
	if blocker_card != null and is_instance_valid(blocker_card) and blocker_card.is_on_field():
		blocker_card.set_blocker_status(false)
	blocker_card = null
func _on_assistant_charge_cancelled() -> void:
	for c in selected_cards_for_mana_conversion:
		c.reset()
	selected_cards_for_mana_conversion = []


func _on_assistant_charge_complete() -> void:
	if stack.skill_mana_deferred_until_target_confirm or stack.summon_mana_deferred_until_target_confirm:
		return
	for c in selected_cards_for_mana_conversion:
		c.reset()
	_tap_selected_cards()
	selected_cards_for_mana_conversion = []

func apply_deferred_skill_mana_payment() -> void:
	for c in selected_cards_for_mana_conversion:
		c.reset()
	_tap_selected_cards()
	selected_cards_for_mana_conversion = []


func _on_assistant_target_cancel() -> void:
	if stack.skill_mana_deferred_until_target_confirm or stack.summon_mana_deferred_until_target_confirm:
		for c in selected_cards_for_mana_conversion:
			c.reset()
		selected_cards_for_mana_conversion.clear()
	targeting_allow_cancel = false
	target_card = null
	source_card = null
	if arrow:
		arrow.queue_free()
		arrow = null
	reset_targets()
	# NOTE: the TARGET modal is popped by Assistant.on_target_cancel() /
	# on_target_complete(), which owns the modal it opened. Don't pop here too.


func _on_stack_execute_card_effect(card: Card) -> void:
	# Targeting session is over: clear all targeting state so the next
	# session starts fresh.
	if arrow:
		arrow.queue_free()
		arrow = null
	target_card = null
	source_card = null
	targeting_allow_cancel = false
	reset_targets()
