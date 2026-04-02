extends Node3D

@onready var deck = $Deck
@onready var opponent_deck = $OpponentDeck
@onready var hand = $Hand
@onready var opponent_hand = $OpponentHand
@onready var field: Field = $Field
@onready var stack : Stack = $Stack
@onready var graveyard = $Graveyards
@onready var opponent_front_row_card = $Field/OpponentFrontrowCard
@onready var opponent_damage_zone = $OpponentDamageZone
@onready var select_arrow: BallisticArrow  = $BallisticArrow
@onready var assistant: Assistant = $Assistant
@onready var card_scene = preload("res://Card.tscn")
@onready var turn_owner = 1


var _current_instructions: Array[Instruction]
var _current_source_card: Card
var _current_attacker_card: Card
var _current_blocker_card: Card
var _targets = []



func _ready():
	for i in range(5):
		var card = create_card(i + 29, 'player')
		hand.add_card(card)
	var x = create_card(6, 'player')
	hand.add_card(x)
	
	
	for i in range(5):
		var card = create_card(i + 52, 'opponent')
		opponent_hand.add_card(card)

	var deck_cards = []
	for i in range(50):
		deck_cards.append(create_card(i + 1, 'player'))
	deck.add_cards(deck_cards)
	
	deck_cards = []
	for i in range(50):
		deck_cards.append(create_card(i + 51, 'opponent'))
	opponent_deck.add_cards(deck_cards)
	
	var opponent_cards = [
		{"id": 41, "tapped": false},
		{"id": 32, "tapped": true},
		{"id": 31, "tapped": false}
	]
	
	var my_cards = [
		{"id": 41, "tapped": false},
		{"id": 32, "tapped": true},
		{"id": 31, "tapped": false}
	]
	
	for card_data in opponent_cards:
		var card = create_card(card_data.id, 'opponent')
		opponent_front_row_card.get_parent().add_child(card)
		card.transform = opponent_front_row_card.transform
		field.play_card(card, true, false)
		if card_data.tapped:
			card.tap()
	for card_data in my_cards:
		var card = create_card(card_data.id, 'player')
		opponent_front_row_card.get_parent().add_child(card)
		card.transform = opponent_front_row_card.transform
		field.play_card(card, false, false)
		if card_data.tapped:
			card.tap()
	_enter_phase(GlobalVariables.Phase.FIRST_MAIN_PHASE)
	phase_index = 2

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_D:
		var card = deck.deck_cards.pop_front()
		hand.draw(card)
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_F:
		var card = opponent_deck.deck_cards.pop_front()
		opponent_hand.draw(card)
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_T:
		var card = opponent_deck.deck_cards.pop_front()
		opponent_damage_zone.draw(card)

func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if($FocusCard):
			$FocusCard.visible = false

func create_card(id, controller):
	var card = card_scene.instantiate()  
	card.initialize(id,controller) 
	if card.has_signal("execute_instructions"):
		card.execute_instructions.connect(_execute_instructions)
	if card.has_signal("on_target"):
		card.on_target.connect(_on_target_selected)
	return card

func _execute_instructions(instructions: Array[Instruction]) -> void:
	# Concatenate arrays (new instructions go in front)
	_current_instructions = instructions + _current_instructions
	_process_next_instruction()
	if(_current_instructions.is_empty()):
		_clean_instruction_stack()
	
func _clean_instruction_stack():
	_current_source_card = null
	_current_attacker_card = null
	_current_blocker_card = null
	_targets = []

func _process_next_instruction() -> void:
	if _current_instructions.is_empty():
		#print('empty instructions')
		return
	
	#print(_current_instructions, 'current instrucitons')
	var instruction = _current_instructions.pop_front()
	var executor = _resolve_executor(instruction.executor, _current_source_card)
	print(executor,instruction.action, 'AmandaXXX')
	if executor.has_method(instruction.action):
		var args = []
		if instruction.value != null:
			if instruction.value is Array:
				args = instruction.value
			else:
				args.append(instruction.value)
		#print(executor,instruction.action, args)
		executor.callv(instruction.action, args)
		_process_next_instruction()

func _resolve_executor(executor_key: String, source_card: Card = null) -> Node:
	match executor_key:
		"card":    return source_card
		"hand":    return $Hand
		"deck":    return $Deck
		"assistant": return $Assistant 
		"field": return $Field
		"opponent_damage_zone": return $OpponentDamageZone
		"game":    return self
		"target":  return _targets[0]
		_:         return get_node(executor_key)

func _on_target_selected(card: Card):
	if(card.is_valid_target):
		_targets.append(card)
		select_arrow.lock_arc(card.get_global_center())
		var cancelTarget = func():
			_targets = []
			select_arrow.unlock_arc()
			assistant.hide_buttons()
		if(check_target_requirements()):
			assistant.set_confirm_button(finish_target)
			assistant.set_cancel_button(cancelTarget)
			assistant.set_confirm_text('Confirm')
			assistant.set_cancel_text('Cancel')
			assistant.show_buttons()
		else:
			assistant.hide_buttons()
	else:
		assistant.hide_buttons()
		_targets = []
		select_arrow.unlock_arc()

func check_target_requirements():
	if len(_targets) >= 1:
		return true

func request_target(targeting_criteria):
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.TARGET)
	$Field.set_viable_targets(targeting_criteria)
	select_arrow.set_is_aiming(true, _current_source_card.global_position)

func finish_target():
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.FREE)
	select_arrow.set_is_aiming(false)
	$Field.reset_targets()
	_process_next_instruction()

func pass_priority():
	TEST_blocker()
	await get_tree().create_timer(2.0).timeout
	return []
func TEST_blocker():
	var front_cards = field.TEST_get_front_cards()
	var blocker: Card = front_cards[0] if front_cards.size() > 0 else null
	if(blocker != null):
		blocker.declare_blocker()
func _await_player_response():
	await get_tree().create_timer(1.0).timeout
	return null

func cause_damage():
	var card = opponent_deck.deck_cards.pop_front()
	opponent_damage_zone.draw(card)
	
func cause_attacking_damage():
	if _current_blocker_card == null:
		cause_damage()

func damage_forward(damage):
	var card: Card = _targets[0]
	card.suffer_damage(damage)
	
func set_attacker(card):
	_current_attacker_card = card
func set_blocker(card):
	_current_blocker_card = card
	
func clash_cards(card1:Card,card2:Card):
	if card1.is_on_field() and card2.is_on_field():
		card1.suffer_damage(card2.power)
		card2.suffer_damage(card1.power)
		enforce_game_state_rules()
	pass
func clash_attacker_blocker():
	clash_cards(field.attacker_card,_current_blocker_card)
	
	

var phases = [
	GlobalVariables.Phase.ACTIVE_PHASE,           # 2.1 0
	GlobalVariables.Phase.DRAW_PHASE,             # 2.2   1
	GlobalVariables.Phase.FIRST_MAIN_PHASE,       # 2.3 2 
	GlobalVariables.Phase.ATTACK_PREPARATION_STEP,   # 2.5 3
	GlobalVariables.Phase.ATTACK_DECLARATION_STEP,   # 2.6 4
	GlobalVariables.Phase.BLOCKER_DECLARATION_STEP,  # 2.7 5
	GlobalVariables.Phase.DAMAGE_RESOLUTION_STEP,    # 2.8 6
	GlobalVariables.Phase.SECOND_MAIN_PHASE,       # 2.10 7
	GlobalVariables.Phase.END_PHASE                # 2.11 8
]
var phase_index = 0


func next_phase():
	# Finish current phase
	# Move to next phase
	if(phases[phase_index] == GlobalVariables.Phase.ATTACK_DECLARATION_STEP):
		if(field.attacker_card):
			phase_index = 5
		else:
			phase_index = 7
		_enter_phase(phases[phase_index])
		return
		
	if(phases[phase_index] == GlobalVariables.Phase.DAMAGE_RESOLUTION_STEP):
		phase_index = 3
		_enter_phase(phases[phase_index])
		return
	
	phase_index += 1
	if phase_index >= phases.size():
		phase_index = 0
		# Switch turn player here
		print("Turn completed")
	
	# Enter new phase
	_enter_phase(phases[phase_index])

func _enter_phase(phase_enum: GlobalVariables.Phase):
	print("Entering: ", phase_enum) # This will print the integer value
	GlobalVariables.set_phase(phase_enum)
	$PhaseText.text = phase_to_string(phase_enum)
	field.phase = phase_enum
	
	match phase_enum:
		GlobalVariables.Phase.ACTIVE_PHASE:
			GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.NO_PRIORITY)
			field.untap_all_cards()
			next_phase()
		GlobalVariables.Phase.DRAW_PHASE:
			var card = deck.deck_cards.pop_front()
			hand.draw(card)
		GlobalVariables.Phase.FIRST_MAIN_PHASE:
			GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.FREE)
			await priority()
			print('PASSED PRIORITY')
			pass
		GlobalVariables.Phase.ATTACK_PREPARATION_STEP:
			GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.INSTANT_SPEED_TIME)
			await priority()
			# Signal UI to enable attacker selection
			pass
		GlobalVariables.Phase.ATTACK_DECLARATION_STEP:
			GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.ATTACKING)
			assistant.set_declare_attack_button('No Attack')
			await assistant.advance_attack_declaration_step
			if(field.attacker_card):
				field.execute_card_attack()
			await priority()
			#await declare_attacker()
			#await priority() #must be something different perhaps, becaus
			# Signal UI to enable attacker selection
			pass
		GlobalVariables.Phase.BLOCKER_DECLARATION_STEP:
			
			await MOCK_opponent_pass_piority() # no blockers
			#await declare_blocker
			await priority()
			pass
		GlobalVariables.Phase.DAMAGE_RESOLUTION_STEP:
			if(_current_blocker_card):
				clash_attacker_blocker()
			else:
				cause_damage()
			await priority()
			field.reset_attacker()
			
		GlobalVariables.Phase.COMBAT_END_STEP:
			pass
		GlobalVariables.Phase.SECOND_MAIN_PHASE:
			await priority()
			pass
		GlobalVariables.Phase.END_PHASE:
			field.turn_end_reset()
			next_phase()
			pass
	
func priority():
	#GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.INSTANT_SPEED_TIME)
	GlobalVariables.set_priority_holder(1)
	var beginning_stack_len = stack.stack_length()
	assistant.show_pass_priority_button()
	print('qqqqqqcc')
	await assistant.pressed_pass_priority
	print(beginning_stack_len, stack.stack_length(), 'aksakask')
	if(stack.stack_length() > beginning_stack_len):
		priority()
		print('xcxcxccc')
		return
	print('aaaacccc')
	GlobalVariables.set_priority_holder(2)
	beginning_stack_len = stack.stack_length()
	await MOCK_opponent_pass_piority()
	print('aaaa')
	#await assistant.opponent_passed_priority
	if(stack.stack_length() > beginning_stack_len):
		print('aaaaasasasas')
		priority()
		return
	if(stack.stack_length() > 0):
		stack.resolve_top_effect()
	else:
		next_phase()
		pass
	#if both pass priority go to next phase!!!

func _exit_phase(phase_name: String):
	match phase_name:
		"End Phase":
			pass

func MOCK_opponent_pass_piority():
	await get_tree().create_timer(0.5).timeout

func enforce_game_state_rules():
	var breakable_cards = field.get_breakable_cards()
	print(breakable_cards,'lala')
	for card in breakable_cards:
		break_card(card)

func break_card(card:Card):
	if not 'unbreakable' in card.status_effects:
		card.untap()
		field.remove_card(card)
		graveyard.add_card(card)

func pop_stack():
	var card = stack.pop_stack()
	graveyard.add_card(card)

func _on_assistant_process_next_instruction() -> void:
	_process_next_instruction()

static func phase_to_string(phase):
	match phase:
		GlobalVariables.Phase.ACTIVE_PHASE:
			return "ACTIVE_PHASE"
		GlobalVariables.Phase.DRAW_PHASE:
			return "DRAW_PHASE"
		GlobalVariables.Phase.FIRST_MAIN_PHASE:
			return "FIRST_MAIN_PHASE"
		GlobalVariables.Phase.ATTACK_PREPARATION_STEP:
			return "ATTACK_PREPARATION_STEP"
		GlobalVariables.Phase.ATTACK_DECLARATION_STEP:
			return "ATTACK_DECLARATION_STEP"
		GlobalVariables.Phase.BLOCKER_DECLARATION_STEP:
			return "BLOCKER_DECLARATION_STEP"
		GlobalVariables.Phase.DAMAGE_RESOLUTION_STEP:
			return "DAMAGE_RESOLUTION_STEP"
		GlobalVariables.Phase.COMBAT_END_STEP:
			return "COMBAT_END_STEP"
		GlobalVariables.Phase.SECOND_MAIN_PHASE:
			return "SECOND_MAIN_PHASE"
		GlobalVariables.Phase.END_PHASE:
			return "END_PHASE"
		_:
			return "UNKNOWN_PHASE"
	

func _on_stack_execute_card_effect(card: Card) -> void:
	var instructions = card.get_card_effect_instructions()
	var target = card.effect_target
	_current_source_card = card.effect_source
	_targets = [target]
	print(card.card_name,'Amanda vagabundinha\n', instructions)
	_execute_instructions(instructions)
	card.queue_free()
	priority()
	pass # Replace with function body.


func _on_stack_request_priority() -> void:
	priority()
	pass # Replace with function body.


func _on_assistant_pressed_next_phase() -> void:
	next_phase()
	pass # Replace with function body.


func _on_field_attacker_changed() -> void:
	
	if(field.attacker_card != null):
		print(field.attacker_card.card_name,'andre')
		assistant.set_declare_attack_button('Attack')
	else:
		assistant.set_declare_attack_button('No Attack')
	pass # Replace with function body.
