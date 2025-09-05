# FieldCardState.gd
extends CardState
class_name FieldCardState  
var card: Card

func _init(card_ref: Card):
	card = card_ref

func handle_grabbed():
	var player_mode = GlobalVariables.get_player_mode()
	
	match player_mode:
		GlobalVariables.Player_Mode.PAYING_COST:
			var instructions: Array[Instruction]
			if card.type == 'Backup' and card.controller == 'player':
				if card.tapped:
					instructions  = [
						Instruction.new("untap", "card"),
						Instruction.new("discharge", "assistant", [1, card.type])
					]
				else:
					instructions  = [
						Instruction.new("tap", "card"),
						Instruction.new("charge", "assistant", [1, card.type])
					]
				card.execute_instructions.emit(instructions, card) 
		GlobalVariables.Player_Mode.FREE:
			if(card.controller == 'player'):
				card.show_actions()
		GlobalVariables.Player_Mode.TARGET:
			print('on target signal emmited')
			card.emit_signal('on_target',card)
		
func handle_released():
	pass
