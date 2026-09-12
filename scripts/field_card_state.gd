# FieldCardState.gd
extends CardState
class_name FieldCardState  
var card: Card
var field: Field

func _init(card_ref: Card):
	card = card_ref
	field = card.get_parent()
	

func handle_grabbed():
	var player_mode = GlobalVariables.get_player_mode()
	
	match player_mode:
		GlobalVariables.Player_Mode.PAYING_COST:
			if card.type == 'Backup' and card.tapped == false and card.controller == 'player':
				# The Field owns the "selected for mana" marker (Card.show_mana_crystal).
				if field.selected_cards_for_mana_conversion.has(card):
					field.remove_card_from_mana_conversion(card)
				else:
					field.add_card_to_mana_conversion(card)
		GlobalVariables.Player_Mode.ATTACKING:
			var phase = field.phase
			match phase:
				GlobalVariables.Phase.ATTACK_DECLARATION_STEP:
					if(card.controller == 'player' and card.can_attack()):
						field.set_attacker(card)
					pass
		GlobalVariables.Player_Mode.FREE, GlobalVariables.Player_Mode.INSTANT_SPEED_TIME:
			field.try_activate_from_field(card)
			pass
			
		GlobalVariables.Player_Mode.TARGET:
			#print('on target signal emmited')
			#card.signal_target()
			field.set_target_card(card)
		GlobalVariables.Player_Mode.BLOCKING:
			# Blocking is the local player's call: any of your own untapped
			# Forwards may block, even one that would break — the AI's "only
			# trade up" heuristic is a policy, not a rule.
			if card.controller == 'player' and card.can_attack():
				field.set_blocker_card(card)
		
func handle_released():
	pass
