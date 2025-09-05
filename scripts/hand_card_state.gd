# HandCardState.gd
extends CardState
class_name HandCardState  
var card: Card
var hand: Hand

func _init(card_ref: Card):
	card = card_ref
	hand = card.get_parent()

func handle_grabbed():
	var player_mode = GlobalVariables.get_player_mode()
	var instructions: Array[Instruction]
	match player_mode:
		GlobalVariables.Player_Mode.PAYING_COST:
			if card.selected:
				card.selected = false
				card.crystal_instance.queue_free()
				instructions  = [
						Instruction.new("discharge", "assistant", [2,card.element])
					]
			else:
				card.selected = true
				card.crystal_instance = card.crystal_scene.instantiate()
				card.add_child(card.crystal_instance)
				card.crystal_instance.position = Vector3(0, 0.05, -0.35)
				instructions  = [
						Instruction.new("charge", "assistant", [2,card.element])
					]
			card.execute_instructions.emit(instructions, card)
		_:
			card.is_dragging = true
			card.position +=  Vector3(0, 0.1,-0.1)
			card.rotation = Vector3.ZERO
			card.scale = Vector3.ONE * 1.05
			card.offset = card.global_transform.origin - card._get_mouse_3d_position_on_card_plane()
			
func handle_released():
	var new_index = hand.find_index(card)
	# Define the rectangle bounds
	var x_min = -1.5
	var x_max = 1.5
	var z_min = -1.25
	var z_max = 0
	
	# Get the card's global position
	var card_position = card.global_position
	# Check if the card is inside the rectangle
	if (card_position.x >= x_min && card_position.x <= x_max &&
		card_position.z >= z_min && card_position.z <= z_max && card.can_be_played()):
		hand.remove_card(card)
		hand.emit_signal('charge_start', card)
		hand.assistant.set_charging(card.get_cost())
	else:
		hand.move_element(hand.cards,card.index,new_index)
		card.index = new_index
	card.is_dragging = false
	hand.update_card_positions()
	card.scale = Vector3.ONE
