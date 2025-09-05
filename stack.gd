extends Node3D
class_name Stack

var cards = []
var card_width = GlobalVariables.get_card_width() * 2;
var card_spacing = -0.2
var player_mode = GlobalVariables.get_player_mode();
var start_x;
var casting_card: Card;
@onready var parser = Parser.new()
@onready var field: Node = get_parent().get_node("Field")


func calculate_total_width():
	return (cards.size() * card_width) + ((cards.size() - 1) * card_spacing)
	
	
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
	
func cast_card():
	if(casting_card.type == 'Summon'):
		var instructions = parser.get_summon_instructions(casting_card.text)
		casting_card.emit_signal("execute_instructions",instructions,casting_card)
	else:
		cards.pop_back()
		field.play_card(casting_card)
		pass
	
	
func pop_stack():
	return cards.pop_back()

func _on_assistant_charge_complete() -> void:
	cast_card()


func _on_hand_charge_start(card: Card) -> void:
	casting_card = card
	add_card_to_tree(card)
	update_card_positions()
