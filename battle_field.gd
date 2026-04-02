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
var arrow: BallisticArrow
## If false (e.g. ETB), targeting cannot be cancelled and stack effect is mandatory.
var targeting_allow_cancel: bool = false
signal selected_cards_for_mana_has_changed(amount:int, element:String)
signal add_card_effect_to_stack(card_id:int, keyword:String, source:Card)
signal request_target_confirmation(target_card: Card, allow_cancel: bool)
signal attacker_changed
signal card_activated_ability(cost:Dictionary)
@export var phase: GlobalVariables.Phase
@export var selected_cards_for_mana_conversion: Array[Card] = []
@onready var TargetScene = preload("res://target.tscn")
@onready var ballistic_arrow_scene = preload("res://ballistic_arrow.tscn")
@onready var assistant: Assistant = get_parent().get_node("Assistant")
@onready var stack: Stack = get_parent().get_node("Stack") as Stack

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

func add_aura_to_card(aura:AuraValue, card:Card):
	if(card.does_card_match_target(aura.targets)):
			if aura.method == 'power_change':
				card.power_change(aura.value,null)
			else:
				pass
				
func add_all_auras_to_card(card:Card):
	for aura in _auras.values():
		add_aura_to_card(aura,card)		

func add_card_to_mana_conversion(card:Card):
	if  not selected_cards_for_mana_conversion.has(card):
		selected_cards_for_mana_conversion.push_back(card)
	selected_cards_for_mana_has_changed.emit(1,card.element)
	
func remove_card_from_mana_conversion(card:Card):
	if selected_cards_for_mana_conversion.has(card):
		selected_cards_for_mana_conversion.erase(card)
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
		GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.FREE)
	
func _on_tween_finished(card: Card):
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.FREE)
	#var instructions = card.create_instruction_from_json(card.card_effects['when_enter_field']['instructions'])
	execute_card_effect(card,"when_enter_field")
	#request_target_confirmation.emit()
	
func execute_card_attack():
	attacker_card.tap()
	execute_card_effect(attacker_card,'when_attack')
	
func turn_end_reset():
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
	var cost: Dictionary = skills[skill_index].get("cost", {})
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
		request_target(choose_target, src, true)
	else:
		GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.FREE)
		assistant.generate_confirm_button(func(): stack.confirm_skill_without_target_then_priority())
	
func execute_card_effect(card,keyword):
	if( not card.is_key_word_in_card_effect(keyword)):
		return
	add_card_effect_to_stack.emit(card.id,keyword,card)
	# Most elegant single-line solution
	var choose_target_criteria = card.card_effects.get(keyword, {}).get('choose_target', null)
	
	if choose_target_criteria:
		request_target(choose_target_criteria, card, false)
func TEST_get_front_cards():
	return opponent_front_cards
func get_all_cards() -> Array[Card]:
	return front_cards + back_cards + opponent_front_cards + opponent_back_cards
func get_all_cards_from_player():
	return front_cards + back_cards

func untap_all_cards():
	for card in get_all_cards_from_player():
		card.untap()
		
func request_target(targeting_criteria, card: Card, allow_cancel: bool = false):
	targeting_allow_cancel = allow_cancel
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.TARGET)
	set_viable_targets(targeting_criteria)
	source_card = card
	var ballistic_arrow = ballistic_arrow_scene.instantiate()
	arrow = ballistic_arrow
	add_child(ballistic_arrow)
	ballistic_arrow.set_is_aiming(true, card.global_position)
	if allow_cancel:
		assistant.prepare_targeting_phase_cancel()
	
func set_target_card(card: Card):
	if target_card == null:
		target_card = card
		arrow.lock_arc(card.get_global_center())
		request_target_confirmation.emit(target_card, targeting_allow_cancel)
	
func set_viable_targets(target_criteria):
	for card in get_all_cards():
		var is_targetable = true
		for key in target_criteria:
			var method_name = key
			var method_args = [target_criteria[key]]
			is_targetable = is_targetable and card.callv(method_name, method_args)
		card.set_valid_target(is_targetable)
		if is_targetable:
			# Create and position target above card
			var target: Node3D = TargetScene.instantiate()
			target.add_to_group("target_indicators")
			self.add_child(target)  # Assuming you have a Target scene/class
			target.position = card.position + Vector3(0,0,0.4)
			target.rotation_degrees = Vector3(-100,0,0)
			target.scale = Vector3.ONE * 0.5
		
func reset_targets():
	for card in get_all_cards():
		card.is_valid_target = false
	get_tree().call_group("target_indicators", "queue_free")

func remove_card(card):
	front_cards.erase(card)
	back_cards.erase(card)
	opponent_front_cards.erase(card)
	opponent_back_cards.erase(card)
	
func get_breakable_cards():
	var ans = []
	for card in (front_cards + opponent_front_cards):
		if(card.life == 0):
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
func _on_assistant_charge_cancelled() -> void:
	for c in selected_cards_for_mana_conversion:
		c.reset()
	selected_cards_for_mana_conversion = []


func _on_assistant_charge_complete() -> void:
	if stack.skill_mana_deferred_until_target_confirm:
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
	if stack.skill_mana_deferred_until_target_confirm:
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
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.FREE)


func _on_stack_execute_card_effect(card: Card) -> void:
	if(arrow):
		arrow.queue_free()
		reset_targets()


func _on_game_phase_change(new_phase: GlobalVariables.Phase) -> void:
	phase = new_phase	
	pass # Replace with function body.
