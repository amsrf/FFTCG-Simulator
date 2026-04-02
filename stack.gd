extends Node3D
class_name Stack

var cards = []
var card_width = GlobalVariables.get_card_width() * 2;
var card_spacing = -0.2
var player_mode = GlobalVariables.get_player_mode();
var start_x;
var casting_card: Card;
@onready var field: Node = get_parent().get_node("Field")
@onready var card_scene = preload("res://Card.tscn")

signal execute_card_effect(card:Card)
signal request_priority()

func calculate_total_width():
	return (cards.size() * card_width) + ((cards.size() - 1) * card_spacing)
	
func stack_length():
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
	if(casting_card.type == 'Summon'):
		pass
	else:
		cards.pop_back()
		field.play_card(casting_card)
		pass
	
	
func pop_stack():
	return cards.pop_back()

func _on_assistant_charge_complete() -> void:
	if(casting_card):
		cast_card()
		casting_card = null


func _on_hand_charge_start(card: Card) -> void:
	casting_card = card
	add_card_to_tree(card)
	update_card_positions()


func _on_assistant_charge_cancelled() -> void:
	var card = cards.pop_back()
	if(card.is_effect_card()):
		card.queue_free()
	update_card_positions()


func _on_field_add_card_effect_to_stack(card_id: int, keyword:String, source:Card) -> void:
	create_card(card_id, 'player', keyword,source)
	update_card_positions()
	pass # Replace with function body.

func create_card(id,controller,keyword, source):
	var card: Card = card_scene.instantiate()  
	card.initialize(id,controller)
	card.key_word_effect = keyword
	card.effect_source = source
	add_created_card_to_tree(card)
	update_card_positions()
	
	return card

func resolve_top_effect():
	var card: Card = cards.pop_back()
	print('Resolve ', card.card_name)
	execute_card_effect.emit(card)
	if(len(cards) == 0):
		GlobalVariables.reset_to_default_phase_player_mode()
	
func process_next_effect():
	await get_tree().create_timer(1.0).timeout
	var card: Card = cards.pop_back()
	execute_card_effect.emit(card)
	if len(cards) > 0:
		process_next_effect()
	


func _on_field_request_target_confirmation(target_card: Card) -> void:
	var effect_card: Card = cards[-1]
	effect_card.effect_target = target_card
	pass # Replace with function body.

'''Change for REQUEST PRIORITY SIGNAL'''
func _on_assistant_target_complete() -> void:
	request_priority.emit()
	# the card effect on the stack has all the information now, it has a target and instructions. Effectively
	# if we reach this call it means the effect is completely on the stack (for real). Now we process the stack. 
	pass # Replace with function body.
