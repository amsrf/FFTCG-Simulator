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
@onready var select_arrow: BallisticArrow  = $BallisticArrow
@onready var assistant: Assistant = $Assistant
@onready var card_scene = preload("res://Card.tscn")
@onready var turn_owner = 1
@onready var priority = true


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

func _execute_instructions(instructions: Array[Instruction], source_card: Card = null) -> void:
	# Concatenate arrays (new instructions go in front)
	_current_instructions = instructions + _current_instructions
	_current_source_card = source_card
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
		print('empty instructions')
		return
	
	print(_current_instructions, 'current instrucitons')
	var instruction = _current_instructions.pop_front()
	var executor = _resolve_executor(instruction.executor, _current_source_card)
	print(executor,instruction.action)
	if(instruction.action == 'pass_priority'):
		var opponent_instructions = await executor.callv(instruction.action, [])
		_current_instructions.append_array(opponent_instructions)
		_process_next_instruction()
		return
	if executor.has_method(instruction.action):
		var args = []
		if instruction.value != null:
			if instruction.value is Array:
				args = instruction.value
			else:
				args.append(instruction.value)
		print(executor,instruction.action, args)
		executor.callv(instruction.action, args)
		if(instruction.action != 'request_target'):
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
		print(blocker.card_name, 'blocker')
func _await_player_response():
	await get_tree().create_timer(1.0).timeout
	return null

func cause_damage():
	var card = opponent_deck.deck_cards.pop_front()
	opponent_damage_zone.draw(card)
	
func cause_attacking_damage():
	print(_current_blocker_card,'blockerrrrr')
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
		print(card2.power,card2.life,card1.power,card1.life)
		enforce_game_state_rules()
	pass
func clash_attacker_blocker():
	clash_cards(_current_attacker_card,_current_blocker_card)
	
func nothing():
	pass

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
