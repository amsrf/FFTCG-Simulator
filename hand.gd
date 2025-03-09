extends Node3D
class_name Hand
# The list of cards in the hand
var cards = []
var card_width = GlobalVariables.get_card_width();
var card_spacing = GlobalVariables.get_card_spacing();
var hand_center = GlobalVariables.get_hand_center();
var hand_rotation = GlobalVariables.get_hand_rotation();
var start_x;
var grabbed_card_index = 0;

# Function to add a card to the hand

func _ready():
	global_transform.origin = hand_center
	self.rotation_degrees = hand_rotation
	 # Connect to the signals of all child cards
			

func add_card(card):
	cards.append(card)
	var area = card.get_node("CardArea3D")
	if area.has_signal("card_grabbed"):
		area.connect("card_grabbed", Callable(self, "_on_card_grabbed"))
	if area.has_signal("card_released"):
		area.connect("card_released", Callable(self, "_on_card_released"))
	# Store the card's global transform before reparenting
	var card_global_transform = card.global_transform
	
	# Reparent the card to the Hand
	if card.get_parent():
		card.reparent(self,false)
	else:
		add_child(card)
	
	# Reset the card's global transform to match the Hand's coordinate system
	card.position = Vector3.ZERO
	card.rotation = Vector3.ZERO
	card.scale = Vector3.ONE
	
	update_card_positions()

# Function to remove a card from the hand
func remove_card(card):
	cards.erase(card)
	update_card_positions()

func calculate_total_width():
	return (cards.size() * card_width) + ((cards.size() - 1) * card_spacing)

# Function to update the positions of the cards in the hand
func update_card_positions():
	var total_width = calculate_total_width()
	start_x = -total_width / 2 + card_width / 2

	for i in range(cards.size()):
		var x_offset = start_x + i * (card_width + card_spacing)
		animate_card(cards[i], Vector3(x_offset, 0, 0)) # Position relative to the Hand
	for card in cards:
		print(card.position)
func last_card_position():
	return start_x + (card_width + card_spacing)*cards.size()	
		
func find_index(card):
	var total_width = calculate_total_width()
	var card_zone_width = total_width/cards.size()
	var index : int = floor((card.position.x + (total_width / 2))/card_zone_width)
	if(index <= 0):
		return 0
	if(index >= cards.size() -1):
		return cards.size() -1 
	return index

func move_element(arr: Array, from_index: int, to_index: int) -> Array:
	if from_index < 0 or from_index >= arr.size() or to_index < 0 or to_index >= arr.size():
		return arr
	var element = arr.pop_at(from_index)
	arr.insert(to_index, element)
	return arr

func _on_card_released(card):
	var new_index = find_index(card)
	move_element(cards,grabbed_card_index,new_index)
	update_card_positions()
	
func _on_card_grabbed(card):
	grabbed_card_index = find_index(card)

func animate_card(card, target_position):
	# Create a Tween to animate the card's movement
	var tween = create_tween()
	tween.tween_property(card, "position", target_position, 0.2)
