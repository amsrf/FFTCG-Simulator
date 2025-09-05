extends Node3D
class_name DamageZone
# The list of cards in the hand

const CARD_CHARGE = 2

var cards = []
var card_width = GlobalVariables.get_card_width();
var card_spacing = -0.3
var start_x;
var grabbed_card_index = 0;
signal charge_start
@onready var field: Field = get_parent().get_node("Field")
@onready var assistant: Assistant = get_parent().get_node("Assistant")

func draw(card):
	add_card_to_tree(card)
	update_card_positions(cards.size() - 1)
	
	var tween = create_tween()
	var path = $Path3D
	var path_follow = $Path3D/PathFollow3D
	var curve = Curve3D.new()
	var target_position = calculate_card_position(cards.size() - 1)
	
	# Add points to the curve
	curve.add_point(card.position)  # Start point
	curve.add_point(card.position + Vector3(0, 0, -0.1))
	curve.add_point(Vector3(0, card.position.y / 2, -1))  # Mid point
	curve.add_point(Vector3(target_position.x + 1.2, 0, -0.9))
	curve.add_point(Vector3(target_position))
	curve.bake_interval = 50
	path.curve = curve
	
	# Reset PathFollow3D progress
	path_follow.progress_ratio = 0
	
	# Configure PathFollow3D
	path_follow.rotation_mode = PathFollow3D.ROTATION_NONE
	
	# Reparent the card to PathFollow3D for the animation
	card.reparent(path_follow)
	
	# Animate the card along the path
	tween.tween_property(path_follow, "progress_ratio", 1.0, 1.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(card, "scale", Vector3(1.2, 1.2, 1.2), 1.3)
	tween.parallel().tween_property(card, "rotation_degrees", Vector3.ZERO, 0.7)
	
	# Reparent the card back to its original parent after the animation
	tween.tween_callback(card.reparent.bind(self))
	tween.tween_callback(path_follow.set.bind("progress_ratio", 0))  # Reset PathFollow3D progress

func add_card_to_tree(card):
	cards.append(card)
	card.index = cards.size()-1
	var trans = card.global_transform
	if card.get_parent():
		card.reparent(self,false)
	else:
		add_child(card)
	card.global_transform = trans
	
	
func add_card(card):
	add_card_to_tree(card)
	update_card_positions()


func calculate_total_width():
	return (cards.size() * card_width) + ((cards.size() - 1) * card_spacing)

# Function to update the positions of the cards in the hand
func update_card_positions(ignore = -1):
	var total_width = calculate_total_width()
	start_x = -total_width / 2 + card_width / 2

	for i in range(cards.size()):
		if(i == ignore):
			continue
		var card = cards[i]
		if(card.is_dragging):
			continue
		card.index = i
		card.rotation = Vector3.ZERO
		animate_card(card, calculate_card_position(i)) # Position relative to the Hand
		
		
func last_card_position():
	return start_x + (card_width + card_spacing)*cards.size()
	
	
func calculate_card_position(i):
	var x_offset = start_x + i * (card_width + card_spacing)
	var y_offset = (i)*0.001
	return Vector3(x_offset, y_offset, 0)
	
func remove_card(card):
	cards.remove_at(card.index)
	

		
func animate_card(card, target_position):
	# Create a Tween to animate the card's movement
	var tween = create_tween()
	tween.tween_property(card, "position", target_position, 0.15)
