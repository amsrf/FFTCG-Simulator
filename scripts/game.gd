extends Node3D
@onready var deck = $Deck
@onready var opponent_deck = $OpponentDeck
@onready var hand = $Hand
@onready var opponent_hand = $OpponentHand
@onready var field = $Field
@onready var stack = $Stack
@onready var graveyard = $Graveyards
@onready var opponent_front_row_card = $Field/OpponentFrontrowCard
@onready var opponent_damage_zone = $OpponentDamageZone
@onready var card_scene = preload("res://Card.tscn")
@onready var arrow_scene = preload("res://ballistic_arrow.tscn")
@onready var turn_owner = 1
@onready var priority = true

var _current_instructions: Array[Instruction]
var _current_source_card: Card
var _waiting_for_target: bool = false
var _targets = []
var _arrow


func create_card(id, controller):
	var card = card_scene.instantiate()  
	card.initialize(id,controller) 
	if card.has_signal("execute_instructions"):
		card.execute_instructions.connect(_execute_instructions)
	if card.has_signal("on_target"):
		card.on_target.connect(_on_target_selected)
	return card
	
func cause_damage():
	var card = opponent_deck.deck_cards.pop_front()
	opponent_damage_zone.draw(card)
	
func await_instant_response():
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.INSTANT_SPEED_RESPONSE)
	var resp = await _await_player_response()
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.NO_PRIORITY)
	var response = await _await_opponent_response()
	
	
func _await_player_response():
	await get_tree().create_timer(1.0).timeout
	return null
	
func _await_opponent_response():
	
	# For now, we'll just simulate a delay and return nothing
	await get_tree().create_timer(2.0).timeout  # 2 second delay
	
	# In a real game, you would:
	# 1. Activate opponent AI or wait for network input
	# 2. Connect to the response_received signal

	return null  # No response for now
	
func _ready():
	# Initialize player hand
	for i in range(5):
		var card = create_card(i + 29, 'player')
		hand.add_card(card)
	
	# Initialize opponent hand
	for i in range(5):
		var card = create_card(i + 52, 'opponent')
		opponent_hand.add_card(card)

	# Initialize player deck
	var deck_cards = []
	for i in range(50):
		deck_cards.append(create_card(i + 1, 'player'))
	deck.add_cards(deck_cards)
	
	# Initialize opponent deck
	deck_cards = []
	for i in range(50):
		deck_cards.append(create_card(i + 51, 'opponent'))
	opponent_deck.add_cards(deck_cards)
	
	# Setup opponent front row cards
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


func _process_next_instruction() -> void:
	
	if _current_instructions.is_empty():
		print('empty instructions')
		return
	
	print(_current_instructions, 'current instrucitons')
	var instruction = _current_instructions.pop_front()
	var executor = _resolve_executor(instruction.executor, _current_source_card)
	print(executor,instruction.action)
	if executor.has_method(instruction.action):
		var args = []
		if instruction.value != null:
			if instruction.value is Array:  # If it's already an array
				args = instruction.value   # Use it directly
			else:                          # If it's a single value
				args.append(instruction.value)  # Wrap it
		print(executor,instruction.action, args)
		executor.callv(instruction.action, args)
		if(instruction.action != 'request_target'):
			_process_next_instruction()


func _execute_instructions(instructions: Array[Instruction], source_card: Card = null) -> void:
	_current_instructions = instructions.duplicate()
	_current_source_card = source_card
	_process_next_instruction()
		
func clash_card():
	pass

func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if($FocusCard):
			$FocusCard.visible = false
		
func _input(event):
	# Check if the "D" key is pressed
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_D:
		var card = deck.deck_cards.pop_front()
		hand.draw(card)
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_F:
		var card = opponent_deck.deck_cards.pop_front()
		opponent_hand.draw(card)
	if event is InputEventKey and event.pressed and event.keycode == Key.KEY_T:
		var card = opponent_deck.deck_cards.pop_front()
		opponent_damage_zone.draw(card)
		

func enforce_game_state_rules():
	var breakable_cards = field.get_breakable_cards()
	for card in breakable_cards:
		break_card(card)
	
func break_card(card:Card):
	if not 'unbreakable' in card.status_effects:
		card.untap()
		graveyard.add_card(card)
	
func damage_forward(damage):
	var card: Card = _targets[0]
	card.suffer_damage(damage)
	
func pop_stack():
	var card = stack.pop_stack()
	graveyard.add_card(card)
	
func finish_target():
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.FREE)
	$BallisticArrow.set_is_aiming(false)
	$Field.reset_targets()
	_process_next_instruction()
	
func request_target(targeting_criteria):
	print('alchemist request target')
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.TARGET)
	$Field.set_viable_targets(targeting_criteria)
	$BallisticArrow.set_is_aiming(true, _current_source_card.global_position)
	
	# When action completes:
	#await arrow.fade_out()
func _on_target_selected(card: Card):
	print('on_target_selected')
	if(card.is_valid_target):
		_targets.append(card)
		if(check_target_requirements()):
			$Assistant.generate_confirm_button(finish_target)
		else:
			$Assistant.hide_confirm_button()
	else:
		$Assistant.hide_confirm_button()
		_targets = []
func nothing():
	pass
func check_target_requirements():
	if len(_targets) >= 1:
		return true
	
func _resolve_executor(executor_key: String, source_card: Card = null) -> Node:
		match executor_key:
			"card":    return source_card
			"hand":    return $Hand
			"deck":    return $Deck
			"assistant": return $Assistant 
			"field": return $Field
			"opponent_damage_zone": return $OpponentDamageZone
			"game":    return self
			"target":  return _targets[0]  # Will be set by player selection
			_:         return get_node(executor_key) 
	


func _on_assistant_process_next_instruction() -> void:
	_process_next_instruction()
