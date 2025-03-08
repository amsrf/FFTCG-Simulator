extends Node3D

func _ready():
	# Load the Hand scene
	var hand_scene = preload("res://Hand.tscn")
	var hand = hand_scene.instantiate()  # Instantiate the Hand
	add_child(hand)                      # Add the Hand to the scene
	
	

							  # Add the card to the scene
	
	 # Load the Card scene
	var card_scene = preload("res://Card.tscn")
	  # Instantiate the scene

	# Add 5 cards to the Hand
	for i in range(5):
 # Instantiate a card
		var card = card_scene.instantiate()  
		card.initialize(i + 1)              # Initialize the card with an ID (e.g., 1 to 5)
		hand.add_card(card)  
func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var focus_card = get_tree().get_nodes_in_group("focus_card")[0]
		focus_card.visible = false  # Hide the focus card
		print("Hide Focus")
