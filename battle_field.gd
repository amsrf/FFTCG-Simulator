extends Node3D
class_name Field


const CARD_CHARGE = 1
var front_cards: Array[Card] = []
var back_cards: Array[Card] = []
var opponent_front_cards: Array[Card] = []
var opponent_back_cards: Array[Card] = []
@onready var TargetScene = preload("res://target.tscn")
@onready var assistant: Assistant = get_parent().get_node("Assistant")

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
		tween.tween_property(card, "scale", Vector3.ONE * 1.2, 0.5)
		tween.set_parallel(false)
		tween.tween_property(card, "position", target_position + Vector3(0, 2, 0), 0.6).set_delay(0.2)
		tween.tween_property(card, "position", target_position, 0.4)
		
		# Execute ETB after the ENTIRE tween sequence finishes
		tween.finished.connect(_on_tween_finished.bind(card))
	else:
		card.position = target_position
		card.scale = Vector3.ONE * 1.2
		GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.FREE)
	
func _on_tween_finished(card: Node):
	GlobalVariables.set_player_mode(GlobalVariables.Player_Mode.FREE)
	card.execute_etb()
	
func get_all_cards():
	return front_cards + back_cards + opponent_front_cards + opponent_back_cards
func set_viable_targets(target_criteria):
	for card in get_all_cards():
		var method_name = target_criteria[0]
		var method_args = [target_criteria[1]]
		print('canarias,  ', method_name)
		print('canarias,  ', method_args)
		var is_targetable = card.callv(method_name, method_args)
		print('canarias', is_targetable)
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
		
func get_breakable_cards():
	var ans = []
	for card in (front_cards + opponent_front_cards):
		if(card.life == 0):
			ans.append(card)
	return ans
	
'''func charge():
		assistant.charge(CARD_CHARGE)
		
func discharge():
		assistant.discharge(CARD_CHARGE)'''
